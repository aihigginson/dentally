---
name: pbir-json-must-be-utf8-no-bom
description: PBIR report JSON must be UTF-8 WITHOUT a BOM - a BOM stops Power BI Desktop opening the report.
metadata:
  type: project
---

Every `.json` under a `*.Report/definition/` tree (PBIR) must be **UTF-8 with no
BOM**. A UTF-8 BOM makes Power BI Desktop refuse to open the report - with no
useful error pointing at the file.

**Why:** on 2026-09-08, adding a `mobile.json` with PowerShell 5.1's
`Out-File -Encoding utf8` broke the Finance report. That cmdlet *always* writes a
BOM. The fix is `[System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))`.
Existing files use CRLF and no trailing newline after the final `}`.

**Beware the contrast:** `CLAUDE.md` requires the **SQL** files to be UTF-16 LE
**with** BOM (SSMS default). The two rules are opposite, and the SQL rule is the
one written down - so PBIR encoding is easy to get wrong. `Scripts/Check_Mobile_Layout.ps1`
now fails on a BOM or unparseable JSON in any report definition.
See [[pbir-mobile-layout-model]].
