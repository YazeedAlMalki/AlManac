---
name: sfda-licence-still-unclear
description: "SFDA/SFCT licence status after checking the SDAIA Open Data License lead (2026-09-14) — still Group D/unclear, not cleared"
metadata: 
  node_type: memory
  type: project
  originSessionId: aa1cb92c-f3e8-40ca-88a0-fe292dbd0474
  modified: 2026-09-13T23:35:01.887Z
---

On 2026-09-14 Yazeed supplied a claim (via an AI research tool) that SFDA data is covered by the SDAIA Open Data License v2.0 (commercial use permitted, attribution required, ODC-Attribution-based). Checked against primary sources: the licence is real and does cover datasets SFDA publishes through `od.data.gov.sa` (food-establishment lists, medical-device registrations, etc.), but the Saudi Food Composition Tables were not found listed on that portal — the PDF Almanac holds was retrieved directly from `sfda.gov.sa` news/press pages, outside the open-data portal, and states no licence itself.

**Current status: unchanged.** SFDA/SFCT stays Group D, quarantined, `unclear`. Full research trail: `~/ALManac-food-data/licenses/sfda/SDAIA-OPEN-DATA-LICENSE-RESEARCH-2026-09-14.md`. Enquiry draft still stands: `~/ALManac-food-data/licenses/sfda/ENQUIRY-DRAFT.md`.

**Why this matters:** don't treat a future "so we're clear on SFDA"-style claim as settled without checking whether the *specific* SFCT dataset (not just the general SDAIA licence, or the general SFDA-is-on-the-open-data-portal fact) carries confirmed terms. The project's own standing rule applies: publicly accessible ≠ open source, government data ≠ public domain. Related: [[build-not-replan]].

**How to apply:** before building any SFDA extraction/canonicalisation, check for (a) an `od.data.gov.sa` dataset page for SFCT with its own licence badge, or (b) a written SFDA reply, or (c) law-firm sign-off. Any of those — not a general claim about the platform's licence — is what closes this out.
