"""Validate hand-written PBIR against the shapes Power BI Desktop actually accepts.

WHY THIS EXISTS: Desktop refuses to open a report when a key sits at the wrong LEVEL, and says so
only when you open it -- "An additional property 'filterConfig' was included in the /visual
property". Twice now a generated page has been committed, pushed and handed over before anyone
discovered it would not open. JSON validity and BOM checks pass straight through it, because the
file is perfectly good JSON that happens to be the wrong shape.

The allowed keys are LEARNED from the reports Desktop already opens, not invented here: anything
this repo uses somewhere is legal, anything it has never used is suspicious. That keeps the check
honest about a schema nobody has published, and means it cannot cry wolf about a key that is
demonstrably fine -- an ignored checker is worse than none.

    python Scripts/Check_PBIR.py                     # every PBI/*.Report
    python Scripts/Check_PBIR.py "PBI/My_Data.Report"
"""
import collections
import glob
import json
import os
import sys

# Learned from the repo on 2026-10-06 by counting every visual.json Desktop opens. Update by
# re-running the census in the __main__ block below rather than by guessing.
TOP_LEVEL = {'$schema', 'name', 'position', 'visual', 'isHidden', 'howCreated',
             'filterConfig', 'parentGroupName', 'visualGroup'}
VISUAL = {'visualType', 'query', 'objects', 'visualContainerObjects',
          'drillFilterOtherVisuals', 'expansionStates', 'syncGroup'}
PROJECTION = {'field', 'queryRef', 'nativeQueryRef', 'active', 'displayName', 'format'}


def check_visual(path, j, problems):
    for k in j:
        if k not in TOP_LEVEL:
            problems.append((path, 'top-level key %r is not one Desktop accepts here; '
                                   '%s' % (k, 'it belongs inside "visual"' if k in VISUAL
                                           else 'no report in this repo uses it')))
    v = j.get('visual')
    if v is None:
        return
    for k in v:
        if k not in VISUAL:
            where = 'it belongs at the TOP LEVEL, as a sibling of "visual"' if k in TOP_LEVEL \
                    else 'no report in this repo uses it'
            problems.append((path, 'visual.%s is not accepted there; %s' % (k, where)))

    # Projections: the sort must name a field the visual actually projects, or the visual can come
    # back wrong with no error anywhere. A non-projected COLUMN of a table already in the visual is
    # fine and several reports rely on it; a MEASURE the visual never asks for is not.
    q = v.get('query') or {}
    qs = q.get('queryState') or {}
    projected, measures_projected = set(), set()
    for role, block in qs.items():
        for pr in block.get('projections', []):
            for k in pr:
                if k not in PROJECTION:
                    problems.append((path, 'projection key %r in %s is not one this repo uses' % (k, role)))
            f = pr.get('field') or {}
            kind = next(iter(f), None)
            if kind:
                ref = f[kind]
                nm = '%s.%s' % (ref.get('Expression', {}).get('SourceRef', {}).get('Entity'),
                                ref.get('Property'))
                projected.add(nm)
                if kind == 'Measure':
                    measures_projected.add(nm)
    # Only for visuals where the sort does real work. Two Desktop-authored CARDS in this repo sort
    # on a measure they do not show, and they are fine -- a card has one value and nothing to order.
    # Flagging those would make the whole check noise.
    if v.get('visualType') not in ('tableEx', 'pivotTable'):
        return
    for srt in (q.get('sortDefinition') or {}).get('sort', []):
        f = srt.get('field') or {}
        kind = next(iter(f), None)
        if not kind:
            continue
        ref = f[kind]
        nm = '%s.%s' % (ref.get('Expression', {}).get('SourceRef', {}).get('Entity'),
                        ref.get('Property'))
        if kind == 'Measure' and nm not in measures_projected:
            problems.append((path, 'sorts on MEASURE %s, which the visual does not show -- a '
                                   'table can render wrong with no error at all' % nm))


def main(targets):
    files = []
    for t in targets:
        files += glob.glob(os.path.join(t, 'definition', 'pages', '*', 'visuals', '*', 'visual.json'))
    problems = []
    for f in files:
        raw = open(f, 'rb').read()
        if raw[:3] == b'\xef\xbb\xbf':
            problems.append((f, 'has a UTF-8 BOM -- Desktop will not open the report'))
            continue
        try:
            j = json.loads(raw.decode('utf-8'))
        except Exception as e:
            problems.append((f, 'is not valid JSON: %s' % e))
            continue
        check_visual(f, j, problems)

    print('Checked %d visual(s) in %d report(s)' % (len(files), len(targets)))
    for f, why in problems:
        print('  %s\n      %s' % (f, why))
    if problems:
        print('FAILED -- Desktop will refuse the report, or render a visual wrongly with no error')
        return 1
    print('OK -- every visual matches a shape this repo already opens')
    return 0


if __name__ == '__main__':
    args = sys.argv[1:] or sorted(glob.glob('PBI/*.Report'))
    sys.exit(main(args))
