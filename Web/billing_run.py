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
    python billing_run.py --year-month 202609 --tenant 100 --credit-note --dry-run
    python billing_run.py --year-month 202609 --tenant 100 --credit-note

Runnable on ANY day of the following month, and re-runnable until the money moves: an existing
DRAFT is discarded and re-raised with current figures, while a FINALISED invoice is never touched.

PUTTING RIGHT AN INVOICE THAT WAS ALREADY ISSUED is --credit-note, and it is the only route: a
finalised invoice cannot be edited and a paid one cannot be voided. It credits the invoice IN FULL,
line by line so the VAT mirrors it (crediting by flat amount produces a credit note with no VAT on
it -- see credit_note()), refunds the card, and removes the Billing.Stripe_Invoice row. That last
step is what reopens the month, so an ordinary run afterwards regenerates the lines from current
data and raises the corrected draft. Two deliberate steps, because the credit note reaches the
practice before the replacement does.

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


def new_run_id():
    """Start a fresh idempotency scope.

    RUN_ID exists to collapse network retries within ONE action, and the script gets a new one per
    invocation. A long-lived process -- the web app -- would otherwise keep the SAME key for its
    whole lifetime, so a deliberate second raise for a tenant-month would silently hand back the
    first (now deleted) invoice instead of creating one. Every admin action calls this first.
    """
    global RUN_ID
    RUN_ID = uuid.uuid4().hex[:12]
    return RUN_ID


def vat_rate_id(st=None):
    """The one active GB 20% INCLUSIVE VAT rate, resolved by its properties.

    Deliberately not configuration. A pinned txr_ id that is stale or mistyped would render a
    plausible invoice with the wrong VAT and nobody would notice until an accountant did. Resolving
    by properties either finds the single right rate or refuses to invoice at all.

    Prices in Billing.Profile_Pricing are VAT-INCLUSIVE, so the rate must be inclusive: Stripe
    derives the VAT from the gross figure rather than adding 20% on top. An exclusive rate here
    would bill 72.00 for a 60.00 seat.
    """
    st = st or stripe_client()
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


def find_in_stripe(st, cust_id, ym):
    """Any invoice Stripe already holds for this customer-month, found via invoice metadata.

    THE SECOND GUARD, and the one that saves us when the first fails. Billing.Stripe_Invoice is the
    primary idempotency control, but it is only as good as its contents: lose a row -- a bad
    restore, a manual DELETE, a migration -- and the tenant-month looks unbilled, so the next run
    would raise a SECOND invoice for a month the practice has already paid. Asking Stripe closes
    that, because Stripe cannot lose its own invoices.

    Uses list+filter rather than Invoice.search: search is index-backed and lags creation by
    seconds to a minute, which is exactly the window a re-run happens in. Listing a customer's
    invoices is immediate and exact, and a practice has one invoice a month.

    AN INVOICE THAT HAS BEEN CREDITED IN FULL IS NOT "ALREADY BILLED". It has been withdrawn: the
    money is back with the practice and the month is owed again. Without this, --credit-note would
    be a dead end -- the guard above would find the credited invoice, conclude the month was
    handled, and silently refuse to raise the corrected one. Voided invoices go the same way.
    """
    if not cust_id:
        return None
    for inv in st.Invoice.list(customer=cust_id, limit=100).data:   # newest first
        md = inv.metadata.to_dict() if hasattr(inv.metadata, 'to_dict') else {}
        if str(md.get('year_month')) != str(ym):
            continue
        if (inv.status or '').lower() == 'void':
            continue
        if credited_pence(inv) >= (inv.total or 0) > 0:
            continue
        return inv
    return None


def credited_pence(inv):
    """How much of this invoice has been credited, before and after payment."""
    d = inv.to_dict() if hasattr(inv, 'to_dict') else dict(inv)
    return ((d.get('pre_payment_credit_notes_amount') or 0)
            + (d.get('post_payment_credit_notes_amount') or 0))


def reconcile(st, cur, ym):
    """Make Billing.Stripe_Invoice agree with Stripe for this month. Stripe wins.

    Stripe is the financial record: it holds invoices we cannot delete and statuses a human changed
    in the dashboard. Our table is a local index of it, so where they disagree the table is what is
    wrong.
    """
    cur.execute("SELECT Tenant_ID, Stripe_Customer_ID FROM Billing.Account_Billing "
                "WHERE Stripe_Customer_ID IS NOT NULL")
    customers = {r[0]: (r[1] or '').strip() for r in cur.fetchall() if (r[1] or '').strip()}
    ours = already_raised(cur, ym)
    fixed = 0
    for tid, cust in sorted(customers.items()):
        inv  = find_in_stripe(st, cust, ym)
        mine = ours.get(tid)
        if inv is None and mine is None:
            continue
        if inv is None:
            print(f'  tenant {tid}: we record {mine["invoice"]} but Stripe has no invoice for '
                  f'this month -- clearing the row')
            cur.execute("DELETE FROM Billing.Stripe_Invoice WHERE Tenant_ID = ? AND Year_Month = ?",
                        tid, ym)
            fixed += 1
            continue
        if mine is None:
            print(f'  tenant {tid}: Stripe holds {inv.id} ({inv.status}) with NO row here '
                  f'-- restoring it')
        elif mine['invoice'] != inv.id or (mine['status'] or '') != inv.status:
            print(f'  tenant {tid}: {mine["invoice"]}/{mine["status"]} -> {inv.id}/{inv.status}')
        else:
            continue
        now = datetime.now(timezone.utc).replace(tzinfo=None)
        cur.execute("DELETE FROM Billing.Stripe_Invoice WHERE Tenant_ID = ? AND Year_Month = ?",
                    tid, ym)
        cur.execute(
            "INSERT INTO Billing.Stripe_Invoice (Tenant_ID, Year_Month, Stripe_Invoice_ID, "
            " Stripe_Customer_ID, Status, Amount_Pence, Currency, Line_Count, Error_Message, "
            " Created_At, Updated_At) VALUES (?,?,?,?,?,?,?,?,NULL,?,?)",
            tid, ym, inv.id, cust, inv.status, inv.total, 'gbp',
            len(inv.lines.data) if getattr(inv, 'lines', None) else None, now, now)
        fixed += 1
    print(f'  {fixed} row(s) corrected' if fixed else '  already in agreement with Stripe')
    return fixed


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


def credit_note(st, cur, tid, ym, reason, memo, to_balance=False, dry_run=False):
    """Credit an issued invoice IN FULL, so the month can be corrected and re-invoiced.

    The remedy when a practice queries an invoice that is simply wrong -- a user billed who had
    already left, a price applied that should not have been. A finalised invoice cannot be edited
    and a paid one cannot be voided; the only honest instrument is a credit note, which withdraws
    the original and leaves a matching document the practice's bookkeeper can file against it.

    ==> IT CREDITS LINE BY LINE, NEVER BY FLAT AMOUNT. <== Stripe will happily take
    CreditNote.create(invoice=..., amount=41680) and produce a credit note for exactly that -- with
    NO VAT ON IT. The preview is unambiguous: crediting £416.80 by amount yields total_excluding_tax
    = 41680 and an empty tax list, against an invoice that charged £69.47 of VAT. We would have
    collected VAT and credited none of it, on a document HMRC expects to mirror the invoice.
    Crediting each invoice line reproduces the invoice's own inclusive rate exactly: £416.80 gross,
    £347.33 net, £69.47 VAT. Verified against a real sandbox invoice before this was written.

    WHERE THE MONEY GOES. A paid invoice must have its credit allocated somewhere, and Stripe
    requires us to say where: back to the card (the default, and what a practice expects when they
    have queried a charge) or onto their Stripe credit balance, which is applied to the next invoice
    automatically. An issued-but-unpaid invoice needs neither -- the credit reduces what is owed.

    AFTERWARDS the Billing.Stripe_Invoice row is REMOVED, which is what reopens the month: the
    normal run then regenerates the lines and raises a corrected draft. That is safe here, and only
    here, because the invoice those lines were evidence for has been withdrawn in full. It is NOT a
    second billing -- find_in_stripe skips fully-credited invoices precisely so the corrected one
    can be raised.

    Deliberately does NOT re-invoice: the credit note is a document going to a practice, and a human
    should see it land before the replacement goes out.
    """
    cur.execute("SELECT si.Stripe_Invoice_ID, si.Stripe_Customer_ID, t.Tenant_Name "
                "FROM Billing.Stripe_Invoice si "
                "LEFT JOIN Audit.Tenants t ON t.Tenant_ID = si.Tenant_ID "
                "WHERE si.Tenant_ID = ? AND si.Year_Month = ?", tid, ym)
    row = cur.fetchone()
    if not row or not row[0]:
        print(f'  tenant {tid}: no invoice recorded for {ym // 100}-{ym % 100:02d} -- nothing to '
              f'credit. (--status lists what has been raised.)')
        return 0
    inv_id, cust_id, tname = row[0], (row[1] or '').strip(), row[2] or f'Tenant {tid}'

    inv = st.Invoice.retrieve(inv_id)
    status = (inv.status or '').lower()
    print(f'  {tname} (tenant {tid}): {inv_id} [{inv.number or "-"}] is {status}, '
          f'£{(inv.total or 0) / 100:.2f}')

    # A draft has been sent to nobody and taken nothing. Crediting one is meaningless -- and Stripe
    # refuses anyway. The ordinary run already discards and re-raises drafts.
    if status == 'draft':
        print(f'  -> REFUSED: that invoice is still a DRAFT -- nothing has been issued or charged. '
              f'Just re-run:  python billing_run.py --year-month {ym}')
        return 0
    if status == 'void':
        print('  -> REFUSED: that invoice is already void.')
        return 0

    # Stripe is the authority on what has already been credited, not our table: a credit note may
    # have been raised by hand in the dashboard. Without this, a second run would refund the
    # practice TWICE -- the credit-note equivalent of double billing, and just as damaging.
    already = credited_pence(inv)
    if already >= (inv.total or 0) > 0:
        print(f'  -> REFUSED: already credited in full (£{already / 100:.2f}). Nothing to do.')
        return 0
    if already:
        print(f'  -> REFUSED: partially credited already (£{already / 100:.2f}); this issues FULL '
              f'credit notes only. Finish it in the Stripe dashboard.')
        return 0

    lines = list(st.Invoice.list_lines(inv_id, limit=100).auto_paging_iter())
    total = sum(l.amount for l in lines)
    if total != (inv.total or 0):
        raise RuntimeError(f'invoice {inv_id}: lines sum to {total} but the invoice total is '
                           f'{inv.total} -- refusing to credit a figure I cannot explain')

    params = {
        'invoice': inv_id,
        'reason': reason,
        'memo': memo,
        'lines': [{'type': 'invoice_line_item', 'invoice_line_item': l.id, 'amount': l.amount}
                  for l in lines],
        'metadata': {'tenant_id': str(tid), 'year_month': str(ym), 'app_env': APP_ENV},
    }
    # Only the part that was actually PAID can be refunded or credited to the balance; any unpaid
    # remainder simply comes off the invoice.
    allocate = min(inv.amount_paid or 0, total)
    if allocate > 0:
        params['credit_amount' if to_balance else 'refund_amount'] = allocate

    pv  = st.CreditNote.preview(**{k: v for k, v in params.items() if k != 'metadata'})
    pvd = pv.to_dict()
    vat = sum((t.get('amount') or 0) for t in (pvd.get('total_taxes') or []))
    where = ('credit balance, applied to the next invoice' if to_balance else 'refunded to the card') \
        if allocate else 'deducted from the amount owed'
    print(f'      {len(lines)} line(s), £{total / 100:.2f} gross '
          f'= net £{(pvd.get("total_excluding_tax") or 0) / 100:.2f} '
          f'+ VAT £{vat / 100:.2f}   -> {where}')

    # The check the whole function exists to pass. A credit note that does not mirror the invoice's
    # VAT is worse than none at all, because it looks right on the total line.
    if vat != invoice_tax_pence(inv):
        raise RuntimeError(f'credit note VAT £{vat / 100:.2f} does not match the invoice VAT '
                           f'£{invoice_tax_pence(inv) / 100:.2f} -- refusing to issue it')

    if dry_run:
        print('  -> DRY RUN: no credit note issued, nothing refunded.')
        return 0

    cn  = st.CreditNote.create(**params,
                               idempotency_key=f'cn-{STRIPE_ENV}-{tid}-{ym}-{RUN_ID}')
    cnd = cn.to_dict()
    cn_vat = sum((t.get('amount') or 0) for t in (cnd.get('total_taxes') or []))
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    cur.execute(
        "INSERT INTO Billing.Credit_Note (Tenant_ID, Year_Month, Stripe_Credit_Note_ID, "
        " Credit_Note_Number, Stripe_Invoice_ID, Invoice_Number, Stripe_Customer_ID, Amount_Pence, "
        " Tax_Pence, Currency, Refund_Pence, Credit_Balance_Pence, Reason, Memo, Created_At, "
        " Created_By) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        tid, ym, cn.id, cnd.get('number'), inv_id, inv.number, cust_id, cnd.get('total'), cn_vat,
        'gbp', (allocate if (allocate and not to_balance) else None),
        (allocate if (allocate and to_balance) else None), reason, (memo or '')[:1000], now,
        (os.environ.get('USERNAME') or 'billing_run')[:128])

    # Reopen the month. Done AFTER the credit note is safely recorded, so a failure here leaves the
    # month closed rather than open -- the direction that cannot double-bill.
    cur.execute("DELETE FROM Billing.Stripe_Invoice WHERE Tenant_ID = ? AND Year_Month = ?", tid, ym)

    print(f'  -> CREDIT NOTE {cn.id} [{cnd.get("number") or "-"}] for £{(cnd.get("total") or 0) / 100:.2f}')
    print(f'     {"credited to their Stripe balance" if to_balance else "refunded to the card"}: '
          f'£{allocate / 100:.2f}' if allocate else '     deducted from the amount owed')
    print()
    print(f'  The month is now OPEN again. To raise the corrected invoice:')
    print(f'      python billing_run.py --year-month {ym}')
    print(f'  That regenerates the lines from current data and raises a DRAFT. Nothing is charged '
          f'until you finalise it.')
    return 1


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
    ap.add_argument('--reconcile', action='store_true',
                    help='make our table agree with Stripe for this month (Stripe wins)')
    ap.add_argument('--credit-note', action='store_true',
                    help='credit an ISSUED invoice in full so the month can be re-invoiced; '
                         'requires --tenant')
    ap.add_argument('--tenant', type=int, default=None, help='tenant id, for --credit-note')
    ap.add_argument('--reason', default='order_change',
                    choices=['duplicate', 'fraudulent', 'order_change', 'product_unsatisfactory'],
                    help='Stripe credit note reason (default order_change)')
    ap.add_argument('--memo', default=None, help='note printed on the credit note PDF')
    ap.add_argument('--credit-balance', action='store_true',
                    help='hold the credit on the customer balance instead of refunding the card')
    args = ap.parse_args()
    ym = args.year_month or last_month()

    started = datetime.now(timezone.utc).replace(tzinfo=None)
    cn = _connect()
    cur = cn.cursor()
    print(f'billing run [{APP_ENV}]  month {ym // 100}-{ym % 100:02d}'
          f'{"  (DRY RUN -- nothing will change)" if args.dry_run else ""}')

    if args.reconcile:
        reconcile(stripe_client(), cur, ym)
        return 0

    if args.credit_note:
        # --tenant is REQUIRED, with no "all tenants" convenience. A credit note refunds real money
        # and is emailed to the practice; it is a remedy for one practice's queried invoice, and
        # anything that could fan it out across every practice on a mistyped month is not worth the
        # keystrokes it saves.
        if args.tenant is None:
            print('  --credit-note needs --tenant <id>. It refunds money and emails a document to '
                  'the practice, so it is deliberately one practice at a time.')
            return 2
        memo = args.memo or (f'Credit note for the Analytically subscription invoice for '
                             f'{ym // 100}-{ym % 100:02d}. A corrected invoice follows.')
        try:
            n = credit_note(stripe_client(), cur, args.tenant, ym, args.reason, memo,
                            to_balance=args.credit_balance, dry_run=args.dry_run)
            log_run(cur, ym, 'SUCCEEDED', started, n=n)
            return 0
        except Exception as e:
            log_run(cur, ym, 'FAILED', started, error=e)
            raise
        finally:
            cn.close()

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

            # Belt and braces: even with no row here, Stripe may already hold an invoice for this
            # month -- our row could have been lost. Raising a second one would bill a practice
            # twice for the same period, which is the failure that matters most.
            if not existing and not args.dry_run:
                orphan = find_in_stripe(st, t['customer'], ym)
                if orphan is not None:
                    print(f'{head}  -> Stripe already holds {orphan.id} ({orphan.status}) for this '
                          f'month with no row here; recording it and skipping')
                    now = datetime.now(timezone.utc).replace(tzinfo=None)
                    cur.execute("INSERT INTO Billing.Stripe_Invoice (Tenant_ID, Year_Month, "
                                " Stripe_Invoice_ID, Stripe_Customer_ID, Status, Amount_Pence, "
                                " Currency, Line_Count, Created_At, Updated_At) "
                                "VALUES (?,?,?,?,?,?,?,?,?,?)",
                                tid, ym, orphan.id, t['customer'], orphan.status, orphan.total,
                                'gbp', len(t['lines']), now, now)
                    continue

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
