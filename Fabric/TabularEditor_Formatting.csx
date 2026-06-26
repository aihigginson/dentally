// =============================================================================
// Bulk column formatting -- run in Tabular Editor against the model (C# 6).
// Idempotent: re-run any time. Sets FormatString on every NUMERIC COLUMN by
// classifying it from its name + data type. Does NOT touch measures (they carry
// their own formats from the KPI builder scripts) or text/date/boolean columns.
//
// Rules:
//   * IDs / keys / years / sequence numbers -> "0"          (NO thousands separator)
//   * Percentage columns                     -> "#,##0.0%"      (percent, 1dp)
//   * Monetary columns                       -> "GBP #,##0.00"  (currency, commas)
//   * Other integers                         -> "#,##0"          (commas)
//   * Other decimals                         -> "#,##0.00"       (commas, 2dp)
//
// Currency is detected by name token (Amount, Price, Charge, Fee, Cost, Revenue,
// Balance, Outstanding, Paid, Deposit, Discount, Payment, Refund, Value) MINUS
// clinical/target units (UDA, UOA, Target) which are counts, not money. Percentages
// by token (Rate, Ratio, Percent, Pct, Compliance, Utilisation, Occupancy). Tune the
// token lists below if a column is mis-classified, then re-run.
// NOTE: the "%" format multiplies by 100, so it assumes percentage columns are stored
// as a FRACTION (0.95 -> 95.0%). If any store a whole number (95), drop it from the
// percent set or it will read 9500%.
// =============================================================================

string FMT_PCT = "#,##0.0%";          // percent, 1 decimal place
string FMT_CCY = "£#,##0.00";    // GBP pound sign + thousands + 2dp
string FMT_ID  = "0";                 // no thousands separator
string FMT_INT = "#,##0";             // integer with thousands
string FMT_DEC = "#,##0.00";          // decimal with thousands + 2dp

// Percentage name tokens (checked before currency)
string[] pctTokens = { "rate","ratio","percent","pct","compliance","utilisation","occupancy" };
// Money name tokens (lower case, substring match)
string[] ccyTokens = { "amount","price","charge","fee","cost","revenue","balance",
    "outstanding","paid","deposit","discount","payment","refund","value","sundry" };
// ...but NOT these (clinical units / generic targets that happen to contain "value")
string[] ccyExclude = { "uda","uoa","target" };

int idN = 0, pctN = 0, ccyN = 0, intN = 0, decN = 0, skipN = 0;
var ccyList = new System.Collections.Generic.List<string>();

foreach (var tbl in Model.Tables)
{
    foreach (var col in tbl.Columns)
    {
        var dt = col.DataType;
        bool numeric = (dt == DataType.Int64 || dt == DataType.Decimal || dt == DataType.Double);
        if (!numeric) { skipN++; continue; }

        string n = col.Name.ToLower();

        // 1) IDs / keys / years / sequence numbers -> no separator
        bool noSep = n.StartsWith("pk ") || n.StartsWith("fk ") || n.StartsWith("bk ")
            || n == "id" || n.EndsWith(" id") || n.EndsWith(" key")
            || n.Contains("year") || n.EndsWith(" number");
        if (noSep) { col.FormatString = FMT_ID; idN++; continue; }

        // 2) Percentage? (before currency: "rate"/"ratio" win)
        bool isPct = false;
        foreach (var t in pctTokens) if (n.Contains(t)) isPct = true;
        if (isPct) { col.FormatString = FMT_PCT; pctN++; continue; }

        // 3) Currency?
        bool isCcy = false;
        foreach (var t in ccyTokens) if (n.Contains(t)) isCcy = true;
        foreach (var x in ccyExclude) if (n.Contains(x)) isCcy = false;
        if (isCcy) { col.FormatString = FMT_CCY; ccyN++; ccyList.Add(tbl.Name + "[" + col.Name + "]"); continue; }

        // 4) Other numeric -> commas; keep 2dp for decimals
        if (dt == DataType.Int64) { col.FormatString = FMT_INT; intN++; }
        else                      { col.FormatString = FMT_DEC; decN++; }
    }
}

// Print the currency-classified columns so you can eyeball the heuristic.
ccyList.Sort();
Info(string.Format("Formatted -> IDs/keys/years: {0} | Percent: {1} | Currency: {2} | Int: {3} | Decimal: {4} | (non-numeric skipped: {5})",
    idN, pctN, ccyN, intN, decN, skipN));
Output(string.Join("\r\n", ccyList.ToArray()));   // review these are really money
