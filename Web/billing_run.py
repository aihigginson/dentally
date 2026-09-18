"""Monthly billing run: generate the month's invoice lines, then raise Stripe DRAFT invoices.

CREATES DRAFTS ONLY. Nothing is charged by this script. Finalising a draft -- which is what
actually takes money from a practice -- is a deliberate act in the Stripe dashboard, by a human who
has read the summary this prints. That is the agreed posture while the pro-rata and VAT-inclusive
arithmetic have never been tested against a real month: a wrong invoice is far more damaging to a
practice relationship than a late one.

Manual trigger only, so this output IS the review. There is deliberately no email: an unattended
schedule would need one, and this is not that yet.

    python billing_run.py --dry-run                 # compute and report, touch NO STRIPE
    python billing_run.py                           # regenerate lines + raise drafts, month just ended
    python billing_run.py --year-month 202609       # a specific month
    python billing_run.py --status                   # what has already been raised

Runnable on ANY day of the following month, and re-runnable until the money moves: an existing
DRAFT is discarded and re-raised with current figures, while a FINALISED invoice is never touched.

WHAT IS OWED comes from SQL and only SQL: Billing.usp_Generate_Invoice_Lines bills each user for
the highest-priced profile they held in the month, pro-rates the sign-up month, excludes our own
@analytically.info logins and skips cancelled tenants. Stripe is handed the resulting figures and
never computes an amount -- see the note in Web/app.py about why there is no Stripe Subscription.

IDEMPOTENCY, which is the thing that must not be got wrong, has two layers:
  1. Billing.Stripe_Invoice holds one row per (Tenant_ID, Year_Month). A tenant-month that already
     has a row is SKIPPED outright. This is the primary control: it is visible in SQL and survives
     indefinitely.
  2. Stripe's own idempotency_key, derived from (env, tenant, year_month), catches a retry inside
     its 24-hour window even if the SQL write failed after the Stripe call succeeded.
Re-running this script is therefore safe. It is expected to be re-run.

A month that has ALREADY been invoiced never has its lines regenerated, in either mode. Once an
invoice has gone to a practice, Billing.Invoice_Line is evidence of what they were charged, not a
view that may be rebuilt -- and since Profile_Pricing is date-ranged, a later price change would
otherwise rewrite history silently.
"""
import argparse
import os
import struct
import sys
import uuid
from datetime import datetime, timezone

import msal
import pyodbc

TENANT_ID     = os.environ['TENANT_ID']
CLIENT_ID     = os.environ.get('AZURE_CLIENT_ID',     os.environ['CLIENT_ID'])
CLIENT_SECRET = os.environ.get('AZURE_CLIENT_SECRET', os.environ['CLIENT_SECRET'])
FABRIC_SERVER = os.environ['FABRIC_SERVER']
FABRIC_DB     = os.environ['FABRIC_DB']
APP_ENV       = os.environ.get('APP_ENV', 'dev')
STRIPE_ENV    = APP_ENV if APP_ENV in ('dev', 'prod') else 'prod'
KEYVAULT_URL  = os.environ.get('XERO_KEYVAULT_URL', 'https://kv-analytically.vault.azure.net/')

PROFILE_LABEL = {'full': 'All reports', 'clinician': 'Clinician', 'front_office': 'Front Office'}

_msal_app = None
_stripe   = None
# One id per invocation. The Stripe idempotency_key only needs to collapse network
# retries WITHIN a single call -- the durable guard is Billing.Stripe_Invoice. Reusing a
# fixed key across invocations would make a deliberate re-raise silently return the old
# (now deleted) invoice instead of creating a new one.
RUN_ID = uuid.uuid4().hex[:12]


def _token_struct():
    global _msal_app
    if _msal_app is None:
        _msal_app = msal.ConfidentialClientApplication(
            CLIENT_ID, authority=f'https://login.microsoftonline.com/{TENANT_ID}',
            client_credential=CLIENT_SECRET)
    r = _msal_app.acquire_token_for_client(scopes=['https://database.windows.net//.default'])
    if 'access_token' not in r:
        raise RuntimeError(r.get('error_description', 'token acquisition failed'))
    tb = r['access_token'].encode('utf-16-le')
    return struct.pack(f'<I{len(tb)}s', len(tb), tb)


def _connect():
    cs = (f'Driver={{ODBC Driver 18 for SQL Server}};Server={FABRIC_SERVER},1433;'
          f'Database={FABRIC_DB};Encrypt=yes;TrustServerCertificate=no;Login Timeout=30;')
    return pyodbc.connect(cs, attrs_before={1256: _token_struct()}, autocommit=True)


def stripe_client():
    """Stripe, keyed for THIS environment only.

    Same guard as the web app: live/test must match APP_ENV, so a dev billing run cannot invoice a
    real practice. sk_ or rk_ are both fine -- prod holds a restricted key.
    """
    global _stripe
    if _stripe is None:
        import stripe
        from azure.identity import DefaultAzureCredential
        from azure.keyvault.secrets import SecretClient
        name = 'stripe-secret-key-' + STRIPE_ENV
        key  = SecretClient(vault_url=KEYVAULT_URL,
                            credential=DefaultAzureCredential()).get_secret(name).value.strip()
        expected = ('sk_live_', 'rk_live_') if STRIPE_ENV == 'prod' else ('sk_test_', 'rk_test_')
        if not key.startswith(expected):
            raise RuntimeError(f'{name} does not start with one of {expected} -- refusing in {STRIPE_ENV}')
        stripe.api_key = key
        _stripe = stripe
    return _stripe


def vat_rate_id():
    """The one active GB 20% INCLUSIVE VAT rate, resolved by its properties.

    Deliberately not configuration. A pinned txr_ id that is stale or mistyped would render a
    plausible invoice with the wrong VAT and nobody would notice until an accountant did. Resolving
    by properties either finds the single right rate or refuses to invoice at all.

    Prices in Billing.Profile_Pricing are VAT-INCLUSIVE, so the rate must be inclusive: Stripe
    derives the VAT from the gross figure rather than adding 20% on top. An exclusive rate here
    would bill 72.00 for a 60.00 seat.
    """
    st = stripe_client()
    m = [r for r in st.TaxRate.list(active=True, limit=100).data
         if r.percentage == 20.0 and r.inclusive and r.country == 'GB']
    if len(m) != 1:
        raise RuntimeError(f'expected exactly one active GB 20% INCLUSIVE VAT rate, found {len(m)}: '
                           f'{[r.id for r in m]} -- refusing to invoice')
    return m[0].id


def invoice_tax_pence(inv):
    """VAT on an invoice, in pence, across Stripe API versions.

    There is no flat `tax` field on a modern invoice -- it is a `total_taxes` list, one entry per
    applied rate. Reading inv.tax raises AttributeError rather than returning None, which is how
    this surfaced. Falls back to total - total_excluding_tax, which holds for inclusive and
    exclusive rates alike.
    """
    d = inv.to_dict() if hasattr(inv, 'to_dict') else dict(inv)
    taxes = d.get('total_taxes')
    if taxes:
        return sum((t.get('amount') or 0) for t in taxes)
    if d.get('tax') is not None:
        return d['tax']
    return (d.get('total') or 0) - (d.get('total_excluding_tax') or d.get('total') or 0)


def pence(value):
    """Decimal pounds -> integer pence. ONE definition, so rounding cannot drift between callers."""
    return int(round(float(value) * 100))


def last_month():
    t = datetime.now(timezone.utc).date()
    first = t.replace(day=1)
    prev = first.replace(year=first.year - 1, month=12) if first.month == 1 \
        else first.replace(month=first.month - 1)
    return prev.year * 100 + prev.month


def fetch_month(cur, ym):
    """Everything needed to bill a month, per tenant. Returns {tenant_id: {...}}.

    Joins the billing state in with the lines so a tenant that cannot be billed is identified here
    rather than discovered half way through talking to Stripe.
    """
    cur.execute("""
        SELECT il.Tenant_ID, t.Tenant_Name, ab.Stripe_Customer_ID, ab.Paid_From, ab.Cancelled_At,
               il.User_UPN, il.Display_Name, il.Profile_Key, il.Value
        FROM Billing.Invoice_Line il
        LEFT JOIN Audit.Tenants t            ON t.Tenant_ID  = il.Tenant_ID
        LEFT JOIN Billing.Account_Billing ab ON ab.Tenant_ID = il.Tenant_ID
        WHERE il.Year_Month = ?
        ORDER BY il.Tenant_ID, il.Value DESC, il.Display_Name
    """, ym)
    out = {}
    for tid, tname, cust, paid_from, cancelled, upn, name, profile, value in cur.fetchall():
        t = out.setdefault(tid, {'tenant_id': tid, 'name': tname or f'Tenant {tid}',
                                 'customer': (cust or '').strip(), 'paid_from': paid_from,
                                 'cancelled_at': cancelled, 'lines': []})
        t['lines'].append({'upn': upn, 'name': name or upn, 'profile': profile, 'value': value})
    for t in out.values():
        t['total_pence'] = sum(pence(l['value']) for l in t['lines'])
    return out


def already_raised(cur, ym):
    cur.execute("SELECT Tenant_ID, Stripe_Invoice_ID, Status, Amount_Pence "
                "FROM Billing.Stripe_Invoice WHERE Year_Month = ?", ym)
    return {r[0]: {'invoice': r[1], 'status': r[2], 'pence': r[3]} for r in cur.fetchall()}


def blocked_reason(t, has_card):
    """Why this tenant cannot be invoiced, or None. Checked BEFORE any Stripe call."""
    if not t['customer']:
        return 'no Stripe customer (nobody has saved a card)'
    if not has_card:
        return 'no card on file'
    if t['total_pence'] <= 0:
        return 'nothing to bill (trial, free, or zero lines)'
    # usp_Generate_Invoice_Lines already excludes cancelled tenants, so this is a belt-and-braces
    # check against a line set generated before a cancellation landed.
    if t['cancelled_at'] is not None:
        return f"tenant cancelled at {t['cancelled_at']:%Y-%m-%d}"
    return None


def raise_draft(st, t, ym, tax_rate):
    """Create ONE draft invoice for a tenant-month and attach its lines. Charges nothing.

    The invoice is created FIRST and each item attached to it explicitly with invoice=<id>. Creating
    pending invoice items and letting Stripe sweep them into the next invoice would also pull in any
    unrelated pending item on that customer -- this way the invoice contains exactly these lines.

    auto_advance=False keeps it a draft: Stripe will not finalise or collect on its own.
    """
    inv = st.Invoice.create(
        customer=t['customer'],
        currency='gbp',
        auto_advance=False,                       # DRAFT -- no automatic finalise, no collection
        collection_method='charge_automatically',  # applies when a human finalises it
        default_tax_rates=[tax_rate],
        description=f"Analytically subscription — {ym // 100}-{ym % 100:02d}",
        metadata={'tenant_id': str(t['tenant_id']), 'year_month': str(ym), 'app_env': APP_ENV},
        idempotency_key=f'inv-{STRIPE_ENV}-{t["tenant_id"]}-{ym}-{RUN_ID}',
    )
    for i, line in enumerate(t['lines']):
        label = PROFILE_LABEL.get(line['profile'], line['profile'])
        st.InvoiceItem.create(
            customer=t['customer'],
            invoice=inv.id,
            currency='gbp',
            amount=pence(line['value']),
            description=f"{line['name']} — {label}",
            metadata={'upn': line['upn'], 'profile': line['profile']},
            idempotency_key=f'item-{STRIPE_ENV}-{t["tenant_id"]}-{ym}-{i}-{RUN_ID}',
        )
    return st.Invoice.retrieve(inv.id)


def refresh_status(st, cur, ym, prior):
    """Re-read each recorded invoice's status FROM STRIPE and write it back.

    Stripe is the authority on invoice status, because finalising -- the act that takes the money
    -- happens there, by a human, in the dashboard. Our row still says 'draft' at that moment.
    Judging "already finalised" from our own copy therefore got it wrong in the one case that
    matters: the run tried to discard a PAID invoice and died on Stripe's "You can only delete
    draft invoices". Stripe's own constraint stopped any harm, but the run aborted with a cryptic
    error rather than skipping cleanly.

    An invoice that has vanished from Stripe (someone deleted the draft there) is treated as absent
    so it can be raised again.
    """
    for tid, r in list(prior.items()):
        if not r.get('invoice'):
            continue
        try:
            inv = st.Invoice.retrieve(r['invoice'])
            if inv.status != r['status']:
                print(f'      tenant {tid}: status {r["status"]} -> {inv.status} (from Stripe)')
                cur.execute("UPDATE Billing.Stripe_Invoice SET Status = ?, Updated_At = ? "
                            "WHERE Tenant_ID = ? AND Year_Month = ?",
                            inv.status, datetime.now(timezone.utc).replace(tzinfo=None), tid, ym)
            r['status'] = inv.status
        except Exception as e:
            print(f'      tenant {tid}: invoice {r["invoice"]} not readable in Stripe '
                  f'({str(e)[:80]}) -- treating as absent')
            prior.pop(tid, None)
    return prior


def record(cur, t, ym, invoice=None, error=None):
    """Record the Stripe side of a tenant-month.

    AN ERROR MUST NEVER DESTROY A KNOWN INVOICE ID. This originally deleted and re-inserted
    unconditionally, so a failure AFTER the invoice was created -- even a trivial one, like the
    summary line raising AttributeError -- replaced the good row with an ERROR row and lost the
    id. The draft then existed in Stripe with nothing pointing at it, so the next run could not
    discard it and would raise a SECOND draft for the same month. That is precisely the
    double-billing this table exists to prevent, reintroduced by the error handler.

    So: on error, UPDATE in place and leave Stripe_Invoice_ID alone. Only a successful raise
    replaces the row outright.
    """
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    if error is not None:
        cur.execute(
            "UPDATE Billing.Stripe_Invoice SET Error_Message = ?, Updated_At = ?, "
            "  Status = CASE WHEN Stripe_Invoice_ID IS NULL THEN 'ERROR' ELSE Status END "
            "WHERE Tenant_ID = ? AND Year_Month = ?",
            str(error)[:4000], now, t['tenant_id'], ym)
        if cur.rowcount == 0:
            cur.execute(
                "INSERT INTO Billing.Stripe_Invoice (Tenant_ID, Year_Month, Stripe_Customer_ID, "
                " Status, Amount_Pence, Currency, Line_Count, Error_Message, Created_At, Updated_At) "
                "VALUES (?,?,?,'ERROR',?,?,?,?,?,?)",
                t['tenant_id'], ym, t['customer'], t['total_pence'], 'gbp',
                len(t['lines']), str(error)[:4000], now, now)
        return

    cur.execute("DELETE FROM Billing.Stripe_Invoice WHERE Tenant_ID = ? AND Year_Month = ?",
                t['tenant_id'], ym)
    cur.execute(
        "INSERT INTO Billing.Stripe_Invoice (Tenant_ID, Year_Month, Stripe_Invoice_ID, "
        " Stripe_Customer_ID, Status, Amount_Pence, Currency, Line_Count, Error_Message, "
        " Created_At, Updated_At) VALUES (?,?,?,?,?,?,?,?,NULL,?,?)",
        t['tenant_id'], ym, invoice.id, t['customer'], invoice.status,
        invoice.total, 'gbp', len(t['lines']), now, now)


def log_run(cur, ym, status, started, error=None, n=None):
    """Audit row, best effort -- same posture as appdb_sync: never mask the real error."""
    try:
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        cur.execute(
            "INSERT INTO Audit.Process_Execution_Log (Run_UUID, Process_Name, Process_Type, "
            " Start_Time, End_Time, Duration_Seconds, Num_Of_Records, Status, Error_Message, "
            " Executed_By, Run_Date, Process_Options) "
            "VALUES (?,?,'JOB',?,?,?,?,?,?,'billing_run',?,?)",
            str(uuid.uuid4()), 'billing_run', started, now,
            (now - started).total_seconds(), n, status,
            (str(error)[:8000] if error else None), now.date(), f'year_month={ym}')
    except Exception as e:
        print(f'WARNING: could not write Audit.Process_Execution_Log: {str(e)[:200]}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--year-month', type=int, default=None, help='YYYYMM; default = month just ended')
    ap.add_argument('--dry-run', action='store_true', help='compute and report, change nothing')
    ap.add_argument('--status', action='store_true', help='show what has already been raised')
    args = ap.parse_args()
    ym = args.year_month or last_month()

    started = datetime.now(timezone.utc).replace(tzinfo=None)
    cn = _connect()
    cur = cn.cursor()
    print(f'billing run [{APP_ENV}]  month {ym // 100}-{ym % 100:02d}'
          f'{"  (DRY RUN -- nothing will change)" if args.dry_run else ""}')

    if args.status:
        prior = already_raised(cur, ym)
        if not prior:
            print('  nothing raised for this month')
        for tid, r in sorted(prior.items()):
            print(f'  tenant {tid}: {r["invoice"]}  status={r["status"]}  '
                  f'£{(r["pence"] or 0) / 100:.2f}')
        return 0

    try:
        # Look at what has already been raised FIRST, because it decides whether the lines may be
        # regenerated at all.
        prior = already_raised(cur, ym)

        # A DRAFT has taken no money, so it may be discarded and re-raised -- that is the whole
        # point of drafts, and this script is expected to be re-run on any day of the following
        # month until the figures look right. A FINALISED invoice (open/paid/uncollectible/void)
        # has been sent to the practice and possibly collected: it is never touched here.
        # Ask Stripe what these invoices actually are now -- our Status is stale the moment a
        # human finalises one in the dashboard, which is the intended workflow.
        if prior and not args.dry_run:
            prior = refresh_status(stripe_client(), cur, ym, prior)
        finalised = {tid: r for tid, r in prior.items()
                     if (r['status'] or '').lower() not in ('draft', 'error', '')}

        # NEVER regenerate a month that holds a FINALISED invoice. usp_Generate_Invoice_Lines
        # clears and rebuilds, so re-running it would rewrite the lines out from under an invoice
        # already sent -- the figures on their PDF would no longer match anything in our records,
        # and because Profile_Pricing is date-ranged a later price change would silently alter
        # history. Once collected, Invoice_Line is evidence, not a derived view.
        if finalised:
            print(f'  lines NOT regenerated: {len(finalised)} tenant(s) hold a FINALISED invoice '
                  f'for this month')
        else:
            # Regenerate even in a dry run: otherwise the review shows whatever was last generated,
            # which may predate a price change -- and a review of the wrong figures is worse than
            # no review. --dry-run means "do not touch Stripe", not "do not compute".
            cur.execute("EXEC Billing.usp_Generate_Invoice_Lines @Year_Month = ?", ym)
            print('  invoice lines regenerated')

        tenants = fetch_month(cur, ym)
        if not tenants:
            print('  no invoice lines for this month -- nothing to bill')
            log_run(cur, ym, 'SUCCEEDED', started, n=0)
            return 0

        st = stripe_client() if not args.dry_run else None
        tax = vat_rate_id() if not args.dry_run else '(not resolved in dry run)'
        if not args.dry_run:
            print(f'  VAT rate: {tax}')

        raised = 0
        for tid, t in sorted(tenants.items()):
            gross = t['total_pence'] / 100
            head  = f'  {t["name"]} (tenant {tid}): {len(t["lines"])} line(s), £{gross:.2f} inc. VAT'

            existing = prior.get(tid)
            if existing and tid in finalised:
                print(f'{head}  -> SKIPPED: {existing["invoice"]} is {existing["status"]}, '
                      f'already sent to the practice')
                continue
            if existing and existing['invoice'] and not args.dry_run:
                # Discard the previous draft so the practice is never left with two invoices for
                # one month. Invoice.delete only works on drafts, which is exactly the safety we
                # want: if this ever hits a finalised invoice it errors rather than destroying it.
                try:
                    st.Invoice.delete(existing['invoice'])
                    print(f'      discarded previous draft {existing["invoice"]}')
                except Exception as e:
                    print(f'{head}  -> FAILED to discard draft {existing["invoice"]}: {str(e)[:160]}')
                    raise

            has_card = True
            if not args.dry_run and t['customer']:
                cust = st.Customer.retrieve(t['customer'],
                                            expand=['invoice_settings.default_payment_method'])
                inv_s = getattr(cust, 'invoice_settings', None)
                has_card = getattr(inv_s, 'default_payment_method', None) is not None

            why = blocked_reason(t, has_card)
            if why:
                print(f'{head}  -> SKIPPED: {why}')
                continue

            for line in t['lines']:
                label = PROFILE_LABEL.get(line['profile'], line['profile'])
                print(f'      {line["name"]:<28} {label:<14} £{float(line["value"]):>8.2f}')

            if args.dry_run:
                print(f'{head}  -> would raise a DRAFT invoice')
                continue

            try:
                inv = raise_draft(st, t, ym, tax)
                record(cur, t, ym, invoice=inv)
                raised += 1
                net = (inv.to_dict().get('total_excluding_tax') or 0) / 100
                print(f'{head}  -> DRAFT {inv.id}  gross £{inv.total / 100:.2f} '
                      f'= net £{net:.2f} + VAT £{invoice_tax_pence(inv) / 100:.2f}')
            except Exception as e:
                record(cur, t, ym, error=e)
                print(f'{head}  -> FAILED: {str(e)[:200]}')
                raise

        print()
        if args.dry_run:
            print('DRY RUN complete -- nothing was created.')
        else:
            print(f'{raised} draft invoice(s) raised. NOTHING HAS BEEN CHARGED.')
            if raised:
                print('Review them in Stripe, then Finalise to collect. On the first one, check '
                      'the VAT split: a £60.00 seat should read £50.00 net + £10.00 VAT.')
        log_run(cur, ym, 'SUCCEEDED', started, n=raised)
        return 0
    except Exception as e:
        log_run(cur, ym, 'FAILED', started, error=e)
        raise
    finally:
        cn.close()


if __name__ == '__main__':
    sys.exit(main())
