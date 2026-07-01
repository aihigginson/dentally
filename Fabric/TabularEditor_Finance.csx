// Finance / margin measures — Net Profit + EBITDA from the Xero P&L fact.
//
// Reads '_Finance' (Gold.Fact_Finance) classified by GL account P&L group on
// 'List GL Account' (Gold.Dim_GL_Account):
//   PL Group in { Income | Cost of Sales | Operating Expenses | Depreciation | Finance Costs }
//   EBITDA Item = 0 for depreciation/amortisation + interest/finance (excluded from EBITDA).
// PL Amount is the signed P&L contribution (revenue +, expense +), so:
//   Net Profit = Income - all costs;  EBITDA = Income - operating costs (adds back D&A + interest).
//
// Requires the '_Finance' + 'List GL Account' tables in the model (PBI views
// PBI._Finance / PBI.List GL Account). Tabular Editor C#: no string interpolation,
// DAX is verbatim @"..." strings.

var t = Model.Tables["_Measures"];
var g = "Finance KPIs";

foreach (var existing in t.Measures.Where(m => m.DisplayFolder == g).ToList())
    existing.Delete();

Action<string,string,string> add = (name, dax, fmt) => {
    var m = t.AddMeasure(name, dax);
    m.DisplayFolder = g;
    if (fmt != "") m.FormatString = fmt;
};

string CUR = "#,##0;(#,##0)";
string PCT = "0.0%";

// ── Components ────────────────────────────────────────────────────────────────
add("Total Revenue",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] = ""Income"")", CUR);

add("Cost of Sales",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] = ""Cost of Sales"")", CUR);

add("Operating Expenses",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] = ""Operating Expenses"")", CUR);

add("Operating Costs",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] IN {""Cost of Sales"", ""Operating Expenses""})", CUR);

add("Depreciation & Interest",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] IN {""Depreciation"", ""Finance Costs""})", CUR);

add("Total Costs",
    @"CALCULATE(SUM('_Finance'[PL Amount]), 'List GL Account'[PL Group] <> ""Income"")", CUR);

// ── Headline profitability ────────────────────────────────────────────────────
add("EBITDA",     @"[Total Revenue] - [Operating Costs]", CUR);
add("Net Profit", @"[Total Revenue] - [Total Costs]",     CUR);

add("EBITDA Margin %", @"DIVIDE([EBITDA], [Total Revenue])",     PCT);
add("Net Margin %",    @"DIVIDE([Net Profit], [Total Revenue])", PCT);

Info("Finance KPIs created: Total Revenue, Cost of Sales, Operating Expenses, Operating Costs, "
   + "Depreciation & Interest, Total Costs, EBITDA, Net Profit, EBITDA Margin %, Net Margin %.");
