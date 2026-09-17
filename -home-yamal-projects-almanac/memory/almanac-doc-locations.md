---
name: almanac-doc-locations
description: "Where the \"almanac/*.md\" documents cited in Almanac handoffs actually live on disk"
metadata: 
  node_type: memory
  type: reference
  originSessionId: aa1cb92c-f3e8-40ca-88a0-fe292dbd0474
  modified: 2026-09-13T20:24:07.334Z
---

Handoffs cite `almanac/processing-design-v0.1.md`, `almanac/health-data-foundation-v0.2.md`, `almanac/implementation-status-slice-2026-09-08.md`, `almanac/nutrition-data-collection-report-2026-09-01.md` and `almanac/food-lake-addendum-2026-09-12.md`. None exists under that name. The equivalents:

- processing design v0.1 → `~/ALManac-food-data/PROCESSING_DESIGN.md`
- health-data foundation v0.2 → `~/projects/almanac/docs/architecture/health-data-foundation.md`
- implementation status → `~/projects/almanac/docs/implementation-status.md` (older slice copies in `~/claudealmanacsep8*/`)
- collection report → `~/ALManac-food-data/COLLECTION_REPORT.md`; addendum → `~/ALManac-food-data/ADDENDUM-2026-09-12.md`
- `calorie-database-build-prep-2026-09-13.md` is not on disk at all.

Nutrition work from 2026-09-13 onward is documented in `docs/features/nutrition.md`, `tools/nutrition/README.md` and `~/ALManac-food-data/PROCESSING-LOG-2026-09-13.md`. Related: [[build-not-replan]].
