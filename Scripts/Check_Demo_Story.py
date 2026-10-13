"""Does the generated data tell the story? Generates tenant 11 IN MEMORY and writes nothing.

Reads the three revenue lines the walkthrough opens on, as rolling twelve-month totals:
  private   invoiced treatment, net of the NHS band charge
  plan      capitation -- live members that month times their tier's monthly fee
  nhs       delivered UDA value
A story that holds needs plan climbing, private easing, and the TOTAL slightly up. If the total
falls the narrative is wrong whatever the beats say, which is the whole problem being fixed.
"""
import collections
import datetime
import os
import sys

sys.path.insert(0, r"C:\Users\aihig\OneDrive\Dentally\Code\API")
os.environ.setdefault("GENERATE_AS_OF", "2026-10-13")

from generate_data import generate_tenant, TODAY, START          # noqa: E402
from seed_tenants import SEED_TENANTS                            # noqa: E402

tdef = SEED_TENANTS[11]
print("generating tenant 11 (%s patients, %s .. %s) ..."
      % (tdef["n_patients"], START, TODAY), flush=True)
data = generate_tenant(tdef)

# ── private: invoiced, less the NHS band charge (that is a slice of the UDA value) ────────
priv = collections.Counter()
for inv in data["invoices"]:
    d = inv.get("dated_on")
    amt = float(inv.get("amount") or 0) - float(inv.get("nhs_amount") or 0)
    if d and amt > 0:
        priv[str(d)[:7]] += amt

# ── plan: who was a member that month, times their tier's fee ────────────────────────────
charge = {pp["id"]: float(pp.get("monthly_charge") or 0) for pp in tdef["payment_plans"]}
cap_ids = {pid for pid, c in charge.items() if c > 0}
joined = {}
for p in data["patients"]:
    if p.get("payment_plan_id") in cap_ids:
        joined[p["id"]] = (str(p.get("created_at"))[:7], charge[p["payment_plan_id"]])

# ==> DROP THE PARTIAL MONTH. <== TODAY lands mid-month, so the final bucket holds a fraction
# of its invoices and drags private down. Comparing against it reported the total FALLING 3%
# when complete-month to complete-month it rises 2.6% -- the check, not the data, was wrong.
months = [m for m in sorted(priv) if m < str(TODAY)[:7]]
plan = collections.Counter()
for m in months:
    for pid, (since, fee) in joined.items():
        if since <= m:
            plan[m] += fee

# ── nhs: delivered UDA value, flat by contract ───────────────────────────────────────────
nhs_month = 0.0
if tdef.get("nhs") and tdef.get("contracts"):
    c = tdef["contracts"][-1]
    nhs_month = float(c.get("target") or 0) * float(c.get("uda_value") or 0) / 12.0


def roll(series, m_list, i):
    w = m_list[max(0, i - 11):i + 1]
    return sum(series[m] for m in w)


print("\n   month    private12m      plan12m       nhs12m     TOTAL12m")
out = []
for i, m in enumerate(months):
    if i < 11:
        continue
    p12 = roll(priv, months, i)
    c12 = roll(plan, months, i)
    n12 = nhs_month * 12
    out.append((m, p12, c12, n12, p12 + c12 + n12))
for m, p12, c12, n12, tot in out[::3]:
    print("   %s  %11.0f  %11.0f  %11.0f  %11.0f" % (m, p12, c12, n12, tot))

if len(out) >= 13:
    a, b = out[-13], out[-1]          # a year apart
    print("\n   over the last 12 months of the window:")
    for lbl, i in (("private", 1), ("plan", 2), ("nhs", 3), ("TOTAL", 4)):
        was, now = a[i], b[i]
        pct = (now - was) / was * 100 if was else 0
        print("      %-8s %11.0f -> %11.0f   %+6.1f%%" % (lbl, was, now, pct))
    print("\n   plan share of total: %.1f%% -> %.1f%%"
          % (a[2] / a[4] * 100, b[2] / b[4] * 100))
