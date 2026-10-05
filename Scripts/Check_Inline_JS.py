"""Catch string and regex literals broken across a line in the inline <script> of Web/*.html.

WHY THIS EXISTS: on 2026-10-05 a generated edit put a literal newline inside a regex literal --
`.replace(/<newline>/g, ...)` -- because a Python string turned "\\n" into a real newline. In
JavaScript that is a SYNTAX error, so the entire inline script failed to parse and nothing in it
ran. The visible symptom was the app stuck on the sign-in screen: startApp() is called at the
bottom of that script and never executed.

Nothing else caught it. The HTML tags balanced, the page served 200, the container was healthy,
and the Python that generated the edit was itself valid. A tag-balance check cannot see this and
neither can a smoke test that only looks at status codes.

WHY A LEXER AND NOT A PARSER: there is no JavaScript engine on this machine, and the pure-Python
parsers available predate ES2020 -- esprima rejects `redirectResult?.account`, which is valid and
used here. A checker that cries wolf gets ignored, and an ignored checker is worse than none. A
lexer does not care about language version: it only tracks whether a quote or regex that opened on
a line also closed on it. That is exactly the bug, with no opinion about syntax it cannot know.

Template literals (backticks) legitimately span lines and are tracked across them.

    python Scripts/Check_Inline_JS.py            # all Web/*.html
    python Scripts/Check_Inline_JS.py Web/index.html
"""
import glob
import re
import sys

SCRIPT = re.compile(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', re.S | re.I)

# A `/` begins a REGEX (not a division) when the last meaningful thing before it is an operator,
# an opening bracket, or a keyword -- the standard heuristic. After an identifier, a number or a
# closing bracket it is division.
_REGEX_OK_AFTER = set('(,=:[!&|?{};+-*%~^<>') | {''}
_REGEX_OK_WORDS = {'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void',
                   'case', 'do', 'else', 'yield', 'await'}


def scan(js, first_line):
    """Yield (line_number, problem) for every literal opened and not closed on its own line."""
    problems = []
    in_template = False          # backticks may span lines
    in_block_comment = False
    for rel, line in enumerate(js.splitlines()):
        lineno = first_line + rel
        i, n = 0, len(line)
        prev = ''                # last meaningful char, for the regex-vs-divide decision
        word = ''
        while i < n:
            c = line[i]
            if in_block_comment:
                if c == '*' and i + 1 < n and line[i + 1] == '/':
                    in_block_comment = False; i += 2
                else:
                    i += 1
                continue
            if in_template:
                if c == '\\':
                    i += 2; continue
                if c == '`':
                    in_template = False; prev = '`'
                i += 1
                continue
            if c == '/' and i + 1 < n and line[i + 1] == '/':
                break                                    # line comment
            if c == '/' and i + 1 < n and line[i + 1] == '*':
                in_block_comment = True; i += 2; continue
            if c == '`':
                in_template = True; i += 1; continue
            if c in '"\'':
                j, closed = i + 1, False
                while j < n:
                    if line[j] == '\\':
                        j += 2; continue
                    if line[j] == c:
                        closed = True; break
                    j += 1
                if not closed:
                    problems.append((lineno, 'unterminated %s string' % ('single-quoted' if c == "'" else 'double-quoted')))
                    break
                i = j + 1; prev = c; word = ''
                continue
            if c == '/' and (prev in _REGEX_OK_AFTER or word in _REGEX_OK_WORDS):
                j, closed, in_class = i + 1, False, False
                while j < n:
                    if line[j] == '\\':
                        j += 2; continue
                    if line[j] == '[':
                        in_class = True
                    elif line[j] == ']':
                        in_class = False
                    elif line[j] == '/' and not in_class:
                        closed = True; break
                    j += 1
                if not closed:
                    problems.append((lineno, 'unterminated regex literal -- a newline inside /.../ '
                                             'is a syntax error and stops the WHOLE script running'))
                    break
                i = j + 1; prev = '/'; word = ''
                continue
            if not c.isspace():
                prev = c
                word = word + c if (c.isalpha() or c == '_') else ''
            i += 1
    return problems


def check(path):
    src = open(path, encoding='utf-8').read()
    lines = src.splitlines()
    ok = True
    for m in SCRIPT.finditer(src):
        js = m.group(1)
        first = src[:m.start(1)].count('\n') + 1
        found = scan(js, first)
        if not found:
            print('  %-26s inline script at line %-5d clean (%d lines)' % (path, first, js.count('\n') + 1))
            continue
        ok = False
        for lineno, why in found:
            print('  %-26s LINE %d: %s' % (path, lineno, why))
            for k in range(max(0, lineno - 2), min(len(lines), lineno + 1)):
                mark = '>>' if k == lineno - 1 else '  '
                print('      %s %5d| %s' % (mark, k + 1, lines[k][:105]))
    return ok


if __name__ == '__main__':
    targets = sys.argv[1:] or sorted(glob.glob('Web/*.html'))
    print('Checking inline JavaScript in %d file(s)' % len(targets))
    if all(check(t) for t in targets):
        print('OK -- no literal is left open at a line end')
    else:
        print('FAILED -- a script that does not parse does not run AT ALL; the page will look '
              'like it is stuck, not like it has an error')
        sys.exit(1)
