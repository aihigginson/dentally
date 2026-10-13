"""Read the demo's three revenue lines from generated data, IN MEMORY, writing nothing.

The walkthrough opens on revenue, so the generator has to produce the shape the story claims:
plan climbing, private easing, total slightly UP. This reads those lines as rolling twelve-month
totals so the shape can be checked before a reseed is spent on it -- a reseed plus build is about
an hour, and tuning by reseed is how the story kept drifting in the first place.

==> IT MIRRORS THE WAREHOUSE'S CAPITATION RULE, NOT A SIMPLER ONE. <== The first version credited
every plan member from the month they registered, and over-read plan growth by five points
(+29.8% against the warehouse's +24.7%) because that is not what Gold.usp_Load_Fact_Revenue does.
There, capitation comes from a SPELL: it starts at the member's first free exam and runs to today
while they are still on a rated plan, so a member who never attends is worth nothing and one who
joined in January but first attended in June pays from June. Registration is not the trigger;
attendance is.

NHS is likewise taken from delivered UDA claims rather than assumed flat at the contract value --
the first version assumed flat and missed a 6% decline.

    python Scripts/Check_Demo_Story.py
    TAKEUP_NOW=0.80 GROWTH=0.06 python Scripts/Check_Demo_Story.py     # sweep without editing
"""
import collections
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "API"))
os.environ.setdefault("GENERATE_AS_OF", "2026-10-13")

from generate_data import generate_tenant, TODAY, START          # noqa: E402
from seed_tenants import SEED_TENANTS                            # noqa: E402

tdef = dict(SEED_TENANTS[11])
params = dict(tdef.get("_params", {}))
for env, key in (("TAKEUP_NOW", "plan_takeup_now"), ("TAKEUP_START", "plan_takeup_start"),
                 ("GROWTH", "annual_growth"), ("LAPSE", "lapse_rate")):
    if os.environ.get(env):
        params[key] = float(os.environ[env])
        print("   override %-18s = %s" % (key, params[key]))
tdef["_params"] = params

print("generating tenant 11 (%s patients, %s .. %s) ..."
      % (tdef["n_patients"], START, TODAY), flush=True)
data = generate_tenant(tdef)

CUT = str(TODAY)[:7]            # drop the partial current month; it drags private down

# ── private: invoiced treatment, less the NHS band charge (a slice of the UDA value) ──────
priv = collections.Counter()
for inv in data["invoices"]:
    d = inv.get("dated_on")
    amt = float(inv.get("amount") or 0) - float(inv.get("nhs_amount") or 0)
    if d and amt > 0 and str(d)[:7] < CUT:
        priv[str(d)[:7]] += amt

# ── plan: a spell from the member's FIRST EXAM to today, exactly as the warehouse builds it ──
charge = {pp["id"]: float(pp.get("monthly_charge") or 0) for pp in tdef["payment_plans"]}
cap_ids = {pid for pid, fee in charge.items() if fee > 0}
first_exam = {str(s.get("patient_id")): str(s.get("first_exam_date") or "")[:7]
              for s in data.get("patient_stats", [])}
spells = []
for p in data["patients"]:
    if p.get("payment_plan_id") not in cap_ids:
        continue
    fx = first_exam.get(str(p["id"]), "")
    if not fx:                   # never attended -> no spell -> worth nothing
        continue
    # A spell runs to today only while the member is STILL on a rated plan AND active;
    # otherwise it stops at their last evidence of membership. Crediting inactive members
    # through to today is what left this reading 12% above the warehouse.
    if not p.get("active"):
        continue
    spells.append((max(fx, str(p.get("created_at"))[:7]), charge[p["payment_plan_id"]]))

months = sorted(priv)
plan = collections.Counter()
for m in months:
    for since, fee in spells:
        if since <= m:
            plan[m] += fee

# ── nhs: delivered UDA value from the claims themselves ──────────────────────────────────
nhs = collections.Counter()
uda_val = 0.0
if tdef.get("contracts"):
    uda_val = float(tdef["contracts"][-1].get("uda_value") or 0)
for cl in data.get("nhs_claims", []):
    # awarded_uda, not expected: NHS income is what the contract actually pays for delivered
    # activity. Dated by created_at, which the generator sets to the course completion date.
    d = str(cl.get("created_at") or "")[:7]
    if d and d < CUT:
        nhs[d] += float(cl.get("awarded_uda") or 0) * uda_val


def roll(series, i):
    return sum(series[m] for m in months[max(0, i - 11):i + 1])


print("\n   month    private12m      plan12m       nhs12m     TOTAL12m")
rows = []
for i, m in enumerate(months):
    if i < 11:
        continue
    p12, c12, n12 = roll(priv, i), roll(plan, i), roll(nhs, i)
    rows.append((m, p12, c12, n12, p12 + c12 + n12))
for r in rows[::3]:
    print("   %s  %11.0f  %11.0f  %11.0f  %11.0f" % r)

if len(rows) >= 13:
    a, b = rows[-13], rows[-1]
    print("\n   %s -> %s" % (a[0], b[0]))
    for lbl, i in (("private", 1), ("plan", 2), ("nhs", 3), ("TOTAL", 4)):
        was, now = a[i], b[i]
        pct = (now - was) / was * 100 if was else 0
        flag = ""
        if lbl == "TOTAL":
            flag = "   <== must be positive for the story to hold" if pct <= 0 else "   <== good"
        print("      %-8s %11.0f -> %11.0f   %+6.1f%%%s" % (lbl, was, now, pct, flag))
