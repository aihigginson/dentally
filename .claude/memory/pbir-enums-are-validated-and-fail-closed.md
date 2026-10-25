---
name: pbir-enums-are-validated-and-fail-closed
description: "A wrong enum value or stray property in a PBIR json stops the WHOLE report opening -- the page schemas set additionalProperties:false and nothing on screen names the file."
metadata:
  type: project
---

Setting a cross-filter interaction by hand, `"type": "Filter"` looked obviously right. The
page schema's enum is `Default` / `DataFilter` / `HighlightFilter` / `NoFilter`, and
`additionalProperties` is `false`, so the page failed validation and the Clinical report
would not load at all. The error is not "bad value in page.json" -- it is the report
refusing to open, which looks like any of a dozen other faults.

**Check the schema, don't infer the value.** Every PBIR file names its own schema in
`$schema`; they are public and fetchable, e.g.
`https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json`.
One fetch settles the allowed properties and every enum.

**Why:** hand-authored PBIR is the normal way things get built here, and the cost of a guess
is a dead report rather than a feature that quietly does nothing. The same applies to
visual, bookmark and pages schemas.

**How to apply:** before inventing a property or a string constant in any PBIR json, fetch
the schema the file points at. Related: [[pbir-json-must-be-utf8-no-bom]],
[[pbir-mobile-layout-model]], [[a-table-projection-takes-no-displayname]].
