"""The synthetic generator must emit every column a Bronze loader selects from Stage.

==> ON DEV, THE GENERATOR'S COLUMN SET *IS* THE STAGE SCHEMA. <== seed_onelake.write_stage
writes each Delta table with mode="overwrite", schema_mode="overwrite", taking the schema from
the frame it is handed (V011 data minimisation -- dropped columns are meant to disappear rather
than linger as nulls). So a column that no synthetic tenant produces does not exist in DEV Stage
at all, however faithfully Bronze asks for it.

Two things then go wrong at once, and neither names the real cause:

  * the Stage views are `SELECT * FROM LH_Dentally.dbo.stage_*`, and SQL Server binds that
    column list at CREATE time. Lose a base column and every read of the view fails with
    "View or function 'Stage.X' has more column names specified than columns defined" --
    which sounds like a hand-written column list is wrong, and there isn't one.
  * the Bronze loader that selects the missing column fails on an invalid column name.

That is exactly what happened: `practitioner_site_id` / `updated_at` (appointments) and
`reminders` (recalls) had only ever reached DEV Stage via the REAL API ingest of the
live-shaped tenant. One synthetic-only reseed dropped all three and took out five Stage views
and two Bronze loaders. Re-seeding could not restore them, because the generator had never
produced them.

This test lives in Web/tests because that is the only test directory wired into the suite; it
tests API/generate_data.py against Fabric/Bronze.usp_Load_*.sql and touches nothing in Web/.
"""
import glob
import os
import re
import sys

import pytest

_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_API = os.path.join(_ROOT, 'API')
_FABRIC = os.path.join(_ROOT, 'Fabric')
if _API not in sys.path:
    sys.path.insert(0, _API)


# Stage view name -> generate_tenant() output key. A view absent from here is not checked,
# which is deliberate: Stage also carries Xero and Input tables that no tenant generator feeds.
VIEW_TO_GENERATOR_KEY = {
    'Practice': 'practice', 'Sites': 'sites', 'Rooms': 'rooms', 'Users': 'users',
    'Practitioners': 'practitioners', 'Payment_Plans': 'payment_plans', 'Fees': 'fees',
    'Treatments': 'treatments', 'Treatment_Categories': 'treatment_categories',
    'Contracts': 'contracts', 'Acquisition_Sources': 'acquisition_sources',
    'Cancellation_Reasons': 'cancellation_reasons', 'Sundries': 'sundries',
    'Waiting_Lists': 'waiting_lists', 'Practitioner_Diary_Entries': 'diary_entries',
    'Practitioner_Diary_Breaks': 'diary_breaks', 'Patients': 'patients',
    'Appointments': 'appointments', 'Treatment_Appointments': 'treatment_appts',
    'Treatment_Plans': 'treatment_plans', 'Treatment_Plan_Items': 'treatment_plan_items',
    'Invoices': 'invoices', 'Invoice_Items': 'invoice_items', 'Payments': 'payments',
    'Payment_Explanations': 'payment_explanations',
    'Payment_Allocations': 'payment_allocations', 'NHS_Claims': 'nhs_claims',
    'Patient_Stats': 'patient_stats', 'Recalls': 'recalls',
    'Patient_Referrals': 'patient_referrals',
}

# T-SQL that appears where a column name would. Without this the scan reports CAST and COALESCE
# as missing columns; with it, a genuinely absent column is the only thing left.
_SQL_WORDS = {
    'select', 'distinct', 'top', 'as', 'from', 'where', 'and', 'or', 'not', 'null', 'into',
    'case', 'when', 'then', 'else', 'end', 'is', 'in', 'like', 'between', 'exists', 'all',
    'cast', 'try_cast', 'convert', 'try_convert', 'coalesce', 'isnull', 'nullif', 'left',
    'right', 'ltrim', 'rtrim', 'trim', 'len', 'upper', 'lower', 'replace', 'substring',
    'concat', 'iif', 'abs', 'round', 'floor', 'ceiling', 'getdate', 'sysutcdatetime',
    'sysdatetime', 'json_value', 'json_query', 'openjson', 'hashbytes', 'newid', 'max', 'min',
    'sum', 'count', 'avg', 'row_number', 'over', 'partition', 'by', 'order', 'asc', 'desc',
    'int', 'bigint', 'smallint', 'tinyint', 'bit', 'decimal', 'numeric', 'float', 'real',
    'money', 'date', 'time', 'datetime', 'datetime2', 'datetimeoffset', 'varchar', 'nvarchar',
    'char', 'nchar', 'uniqueidentifier', 'varbinary', 'collate', 'with', 'join', 'on',
    'tenant_id', 'dw_stage_loaded_at',
}


def _read_sql(path):
    """Fabric/*.sql is a mix of UTF-8 and UTF-16. Decode by BOM, never by trial.

    ==> TRYING UTF-16 FIRST SILENTLY MANGLES EVERY UTF-8 FILE. <== ASCII bytes pair up into
    valid CJK code points containing no NUL, so raw.decode('utf-16') SUCCEEDS on a UTF-8 file
    and returns mojibake. A trial loop that only checks for NUL therefore accepts it, the word
    SELECT is nowhere in the result, and the loader is skipped rather than failed -- which is
    how Bronze.usp_Load_Appointments vanished from this scan while being the very file the
    test exists to cover. The assert at the end is what turns that into a failure.
    """
    raw = open(path, 'rb').read()
    if raw.startswith(b'\xff\xfe') or raw.startswith(b'\xfe\xff'):
        text = raw.decode('utf-16')
    elif raw.startswith(b'\xef\xbb\xbf'):
        text = raw.decode('utf-8-sig')
    else:
        text = raw.decode('utf-8', errors='replace')
    assert 'SELECT' in text.upper(), 'decoded %s but found no SQL in it' % path
    return text


def _strip_noise(sql):
    sql = re.sub(r'/\*.*?\*/', ' ', sql, flags=re.S)
    sql = re.sub(r'--[^\n]*', ' ', sql)
    sql = re.sub(r"'[^']*'", " '' ", sql)          # literals, incl. JSON paths like '$.type'
    return sql


def _split_top_level(select_list):
    """Split a SELECT list on commas that are not inside parentheses."""
    items, depth, start = [], 0, 0
    for i, ch in enumerate(select_list):
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif ch == ',' and depth == 0:
            items.append(select_list[start:i])
            start = i + 1
    items.append(select_list[start:])
    return [it for it in (s.strip() for s in items) if it]


def _selected_columns(block):
    """Source columns in a SELECT list: the expression side of each item, aliases excluded.

    ==> DO NOT JUST SUBTRACT THE ALIAS NAMES. <== Bronze aliases almost every column to its own
    name in Title_Case (`LEFT(reminders, 8000) AS Reminders`), and the comparison is
    case-insensitive, so subtracting aliases deletes the very source columns this test is for.
    The first version of this test did exactly that: it passed, and went on passing with
    `reminders` and `practitioner_site_id` deliberately removed from the generator.

    So each item is split at its trailing `AS <alias>` and only the left-hand expression is
    scanned.
    """
    block = _strip_noise(block)
    block = re.sub(r'^\s*SELECT\s+(DISTINCT\s+)?', '', block, flags=re.I)
    columns = set()
    for item in _split_top_level(block):
        expression = re.split(r'\bAS\b', item, maxsplit=1, flags=re.I)[0]
        # \b before the lookahead matters: without it \w* backtracks to satisfy (?!\s*\() and
        # TRY_CAST( is reported as a column named "try_cas".
        for word in re.findall(r'(?<![\w.@#])([A-Za-z_]\w*)\b(?!\s*\()', expression):
            if word.lower() not in _SQL_WORDS:
                columns.add(word.lower())
    return columns


def _generator_columns():
    """Every column any registered synthetic tenant can emit, per generate_tenant key."""
    from generate_data import generate_tenant
    from seed_tenants import SEED_TENANTS
    from skeleton_tenants import SKELETON_TENANTS

    produced = {}
    for registry in (SEED_TENANTS, SKELETON_TENANTS):
        for profile in registry.values():
            for key, value in generate_tenant(profile).items():
                rows = [value] if isinstance(value, dict) else value
                for row in rows:
                    if isinstance(row, dict):
                        produced.setdefault(key, set()).update(row)
    return produced


def _bronze_stage_reads():
    """[(loader, view, {columns})] for every `FROM Stage.<view>` in a Bronze loader."""
    reads = []
    for path in sorted(glob.glob(os.path.join(_FABRIC, 'Bronze.usp_Load_*.sql'))):
        sql = _read_sql(path)
        for match in re.finditer(r'FROM\s+\[?Stage\]?\.\[?(\w+)\]?', sql, re.I):
            view = match.group(1)
            start = sql.rfind('SELECT', 0, match.start())
            if start == -1:
                continue
            reads.append((os.path.basename(path), view,
                          _selected_columns(sql[start:match.start()])))
    return reads


def test_bronze_stage_reads_were_found():
    """Guard the guard: a regex that silently matched nothing would pass every assertion."""
    reads = _bronze_stage_reads()
    assert len(reads) >= 20, 'only found %d Stage reads -- the scan is broken' % len(reads)
    assert any(view == 'Appointments' for _, view, _ in reads)


def test_generator_emits_every_column_bronze_selects():
    produced = _generator_columns()
    missing = []
    for loader, view, columns in _bronze_stage_reads():
        key = VIEW_TO_GENERATOR_KEY.get(view)
        if key is None or key not in produced:
            continue
        for column in sorted(columns - produced[key]):
            missing.append('%s selects Stage.%s.%s, which no tenant produces'
                           % (loader, view, column))
    assert not missing, (
        'Bronze reads columns the generator never emits. Each one will vanish from DEV Stage '
        'on the next seed_onelake run, breaking both the Stage view and the loader:\n  %s'
        % '\n  '.join(missing))


@pytest.mark.parametrize('key,column', [
    ('appointments', 'practitioner_site_id'),
    ('appointments', 'updated_at'),
    ('diary_entries', 'day'),
    ('diary_entries', 'unavailable'),
    ('recalls', 'reminders'),
])
def test_the_columns_that_were_lost_are_emitted(key, column):
    """Named explicitly so a refactor that drops them again fails loudly, not subtly."""
    produced = _generator_columns()
    assert column in produced[key]


@pytest.mark.parametrize('key,column', [
    ('appointments', 'practitioner_site_id'),
    ('diary_entries', 'day'),
    ('recalls', 'reminders'),
])
def test_the_restored_columns_are_null_not_invented(key, column):
    """They must be present and EMPTY.

    Each one has a loader-side fallback keyed on emptiness -- COALESCE([day],[date]),
    COALESCE(NULLIF(TRIM(Practitioner_Site_ID),''), dpr.Site_ID), Silver's LEN(Reminders) > 2.
    Filling them in would silently bypass that fallback and move numbers that this change is
    only meant to stop breaking.
    """
    from generate_data import generate_tenant
    from seed_tenants import SEED_TENANTS

    rows = generate_tenant(SEED_TENANTS[11])[key]
    assert rows, 'no %s generated -- the assertion would prove nothing' % key
    assert all(row.get(column) is None for row in rows)
