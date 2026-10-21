---
name: maple-prices-a-course-on-one-line
description: Course component steps invoice at 0.00; all the money sits on one priced line.
metadata:
  type: reference
---

Maple puts a course's whole value on a **single** invoice item and bills the component
steps at £0.00. For David Mason, May-Sep 2026, every one of the 64 lines invoiced a month
or more after its treatment completed was £0.00 -- View (20), Small Radiograph (13), Crown
Preparation (7), Radiographs, Exam, Intraoral scan, Core Build up, denture impressions,
RCT additional visit. 944 lines worth £66,587.20 were invoiced in the same month the work
completed.

**Why:** it is the reason `Gold.usp_Load_Fact_Revenue` dating private lines by the invoice
header (`inv.Dated_On`) rather than `Treatment_Plan_Items.Completed_At` moves no money --
restating on the completion date gives byte-identical monthly totals. The basis is safe
because of how this practice prices, not because courses never straddle a month end.

**How to apply:** do not generalise the "invoice date is fine" finding to another tenant.
A practice that priced each step would shift real value between months, and the warehouse
would follow the invoice while a pay sheet followed the work. Re-run the comparison per
tenant before relying on it.
