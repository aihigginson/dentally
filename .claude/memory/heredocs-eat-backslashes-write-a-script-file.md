---
name: heredocs-eat-backslashes-write-a-script-file
description: Python passed through a Bash heredoc on this machine loses backslash escapes - write the script to a file with the Write tool instead.
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 421e1bb0-9c87-4cc3-8b8f-dd6c97f09bdd
  modified: 2026-09-28T08:40:49.907Z
---

Python sent through a `<<'EOF'` heredoc in the Bash tool here **loses backslash escapes**, even
though a quoted heredoc should pass them through untouched. `'\\r\\n'` arrives as a real
newline; `'\\.'` arrives as `\.`; `'\n'` inside a generated string arrives as a line break.

**Why:** on 2026-09-27/28 this broke four separate edit scripts. Twice it produced a
`SyntaxError` immediately (harmless), but once it wrote a **literal newline into a C# string
literal** in `Fabric/PBI_Dentally.csx`, which only surfaced when Tabular Editor refused to
compile it — "newline in constant", two errors from one fault, hours after the edit.

**==> BROKEN THREE MORE TIMES ON 2026-10-06, SO THE RULE IS ABSOLUTE. <==** Each time the thought
was "this one is small enough to inline": a `\n` to `\r\n` translation, a `.replace()` pattern,
and a line-ending constant. All three arrived mangled. One of them silently produced a JavaScript
regex containing a real newline and took the DEV APP DOWN for twenty minutes
([[a-newline-in-a-regex-literal-stops-the-whole-script]] if that gets its own note).

There is no size threshold. If the script text contains a backslash ANYWHERE -- in a pattern, an
escape, a Windows path, or a string being generated -- it goes in a file via Write and is run by
path. Checking the output afterwards is not a substitute: two of the three failures produced valid
Python that did the wrong thing.

**How to apply:** for any script that contains a backslash — regex, escape sequences, Windows
paths, generated code — **write it to the scratchpad with the Write tool and run it by path**,
rather than piping it through a heredoc. For short inline work, build the character with
`chr(92)` and `chr(10)` instead of typing an escape. After editing generated code, lint it:
`scratchpad/csx_lint.py` walks `PBI_Dentally.csx` as a lexer, separating verbatim `@"..."`
strings (newlines legal) from regular ones (newlines are a compile error) — a brace or quote
count cannot see that class of fault. Related:
[[read-the-schema-before-querying-it]].
