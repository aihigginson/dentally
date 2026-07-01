"""
xero_model.py  --  Model-first proof for the profitability slice.

Builds Dim_GL_Account + a P&L-grain Fact_Finance from the raw Xero JSON dumped by
xero_extract.py, then RECONCILES the summed Fact_Finance back to Xero's own Profit
& Loss report. If they agree, the transaction->P&L modelling logic is sound and
the Fabric (Bronze->Silver->Gold) build is a mechanical translation of this.

Usage:  python API/xero_model.py   (after running xero_extract.py)
"""
import json
import os
from collections import defaultdict
from datetime import date, timedelta

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xero_data")

# Same 12-month window the extractor requested the P&L for, so the model aligns.
WIN_TO   = date.today()
WIN_FROM = WIN_TO - timedelta(days=365)


def in_window(datestr):
    try:
        d = date.fromisoformat(datestr[:10])
    except (ValueError, TypeError):
        return False
    return WIN_FROM <= d <= WIN_TO


def load(name):
    with open(os.path.join(D, name + ".json")) as f:
        return json.load(f)


def ex_tax(line, line_amount_types):
    """Net (P&L) amount for a line: strip tax only when line amounts are tax-inclusive."""
    amt = line.get("LineAmount", 0) or 0
    if line_amount_types == "Inclusive":
        amt -= line.get("TaxAmount", 0) or 0
    return amt


def main():
    accounts = load("accounts")
    # Dim_GL_Account keyed by Code (line items reference AccountCode)
    dim = {a["Code"]: a for a in accounts if a.get("Code")}
    pl_class = {code: a["Class"] for code, a in dim.items() if a["Class"] in ("REVENUE", "EXPENSE")}

    # Fact_Finance: one row per P&L-affecting transaction line.
    # Convention: revenue positive, expense positive; net profit = revenue - expense.
    fact = []  # dicts: Date, AccountCode, Class, Amount, Source

    def add_lines(txn, lines, source, direction):
        # direction: +1 = inflow (money in: ACCREC / RECEIVE), -1 = outflow (ACCPAY / SPEND).
        # P&L contribution: revenue accounts move WITH inflow; expense accounts move
        # AGAINST it (a refund received onto an expense account reduces the expense).
        dstr = (txn.get("DateString") or txn.get("Date", ""))[:10]
        if not in_window(dstr):
            return
        lat = txn.get("LineAmountTypes")
        for ln in lines:
            code = ln.get("AccountCode")
            if code in pl_class:
                cls  = pl_class[code]
                sign = direction if cls == "REVENUE" else -direction
                fact.append({
                    "Date":        dstr,
                    "AccountCode": code,
                    "Class":       cls,
                    "Amount":      round(ex_tax(ln, lat) * sign, 2),
                    "Source":      source,
                })

    # Invoices: ACCREC = sales (revenue), ACCPAY = bills (expense). P&L statuses only.
    for inv in load("invoices_page1"):
        if inv.get("Status") not in ("AUTHORISED", "PAID"):
            continue
        add_lines(inv, inv.get("LineItems", []), "INVOICE_" + inv.get("Type", ""),
                  direction=1 if inv.get("Type") == "ACCREC" else -1)

    # Credit notes net DOWN the P&L: ACCRECCREDIT reduces revenue, ACCPAYCREDIT
    # reduces expense -> sign -1 against whatever account they hit.
    for cn in load("creditnotes_page1"):
        if cn.get("Status") not in ("AUTHORISED", "PAID"):
            continue
        add_lines(cn, cn.get("LineItems", []), "CREDIT_" + cn.get("Type", ""),
                  direction=-1 if cn.get("Type") == "ACCRECCREDIT" else 1)

    # Bank transactions: SPEND (out) / RECEIVE (in). Lines to P&L accounts only.
    for bt in load("banktransactions_page1"):
        if bt.get("Status") not in ("AUTHORISED", None):
            continue
        add_lines(bt, bt.get("LineItems", []), "BANK_" + bt.get("Type", ""),
                  direction=1 if bt.get("Type") == "RECEIVE" else -1)

    # Manual journals: JournalLines carry signed LineAmount (debit +, credit -).
    for mj in load("manualjournals_page1"):
        if mj.get("Status") not in ("POSTED", None):
            continue
        if not in_window((mj.get("DateString") or mj.get("Date", ""))[:10]):
            continue
        for jl in mj.get("JournalLines", []):
            code = jl.get("AccountCode")
            if code in pl_class:
                fact.append({
                    "Date": (mj.get("DateString") or mj.get("Date", ""))[:10],
                    "AccountCode": code, "Class": pl_class[code],
                    "Amount": round(jl.get("LineAmount", 0) or 0, 2), "Source": "MANJRNL",
                })

    # ---- Summaries ----
    by_class = defaultdict(float)
    by_account = defaultdict(float)
    for r in fact:
        by_class[r["Class"]] += r["Amount"]
        by_account[(r["AccountCode"], dim[r["AccountCode"]]["Name"])] += r["Amount"]

    print(f"Fact_Finance rows: {len(fact)}")
    print(f"Dim_GL_Account (P&L accounts): {len(pl_class)} of {len(dim)}\n")

    revenue = by_class["REVENUE"]
    expense = by_class["EXPENSE"]
    print("MODEL (built from transactions):")
    print(f"   Revenue : {revenue:>12,.2f}")
    print(f"   Expense : {expense:>12,.2f}")
    print(f"   Net     : {revenue - expense:>12,.2f}\n")

    # Xero's own P&L totals for comparison
    pl = load("profit_and_loss")["Reports"][0]
    xero_summary, xero_by_name = {}, {}

    def to_f(s):
        try:
            return float((s or "0").replace(",", ""))
        except ValueError:
            return 0.0

    def walk(rows):
        for r in rows:
            rt = r.get("RowType")
            if rt == "Section":
                walk(r.get("Rows", []))
            elif rt in ("Row", "SummaryRow"):
                c = r.get("Cells", [])
                if len(c) >= 2:
                    name, val = c[0].get("Value", ""), to_f(c[-1].get("Value", ""))
                    (xero_summary if rt == "SummaryRow" else xero_by_name)[name] = val
    walk(pl.get("Rows", []))

    print("XERO P&L report (summary rows):")
    for k, v in xero_summary.items():
        print(f"   {k}: {v:,.2f}")

    # Per-account reconciliation, model vs Xero P&L (by account name)
    model_by_name = {name: round(amt, 2) for (code, name), amt in by_account.items()}
    diffs = [(n, model_by_name.get(n, 0.0), xero_by_name.get(n, 0.0))
             for n in set(model_by_name) | set(xero_by_name)
             if abs(model_by_name.get(n, 0.0) - xero_by_name.get(n, 0.0)) > 0.01]
    print("\nPer-account differences (model vs Xero P&L):")
    if not diffs:
        print("   none - reconciles to the penny.")
    for n, m, x in sorted(diffs, key=lambda t: -abs(t[1] - t[2])):
        print(f"   {n:<32} model {m:>10,.2f}  xero {x:>10,.2f}  diff {m - x:>8,.2f}")


if __name__ == "__main__":
    main()
