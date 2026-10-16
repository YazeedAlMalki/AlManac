# Owner decisions — 2026-10-16

Answered by the owner in the session on 2026-10-16, to questions put with the
options and a recommendation. These are the owner's calls, not the build's, and
they close the gates named below. Where an answer left a detail open, the
detail is a build decision and goes in `CONTEXT.md` with an *Overrule by:* line.

| Item | Asked | Answer | What it means |
|---|---|---|---|
| **T02** fasting schedule setup | Approve the setup as built (Ramadan on automatically; Mondays/Thursdays and White Days off until switched on; any day markable; Eid and Tashreeq never fast days)? | **"Ask me first"** | On first launch the app asks which fasts the person keeps (Ramadan, Mondays and Thursdays, the White Days) instead of assuming. The rest of the setup stands. |
| **T25** recovery-day branch | Keep the recovery-day work in PR #20? | **Keep it in PR #20** | No change. |
| **G1** digestion medical advisory | Remove from v1, or build with draft wording? | **Build with draft wording** | BRD §6.3's three levels are built. Every message is labelled *not clinician-reviewed*, and the BRD's own condition stands: clinician review before App Store release. |
| **G2** digestion ring fill rule | Fills when you log today / remove the ring from v1 / keep as now? | **Remove the ring from v1** | The digestion ring and its Settings switch are taken out of v1. Logging and history are unchanged. |
| **G3** progress photos | Still later? | **Still later** | Deferred, as on 2026-09-16. |
| **G4** failed lab import record | Keep a record of a failed import? | **Yes, keep a record** | Confirms what was built (`d21d9a9`). Nothing changes. |
| **G5** LOINC codes | Add verified LOINC codes, accepting LOINC's licence? | **Yes, add them** | The owner accepts the LOINC licence (free, attribution required). Verified codes are added to the lab catalog and LOINC is credited on the Attributions page. |
| **T04** TheMealDB route | Don't ship / ask them / fetch live? | **"Look for an open-source alternative that I can use commercially"** | None of the three. A recipe dataset whose licence allows commercial use is to be found and reported before anything is built. TheMealDB is not used. **Researched 2026-10-16:** `docs/features/recipe-sources.md`. **Owner's pick, 2026-10-16: Wikibooks Cookbook. Built:** 298 recipes in Kitchen, credited (recipe-sources.md, "Built"). |

## Later the same day: Slice 8

Asked to approve the Slice 8 rubric (D2) and the regional-dish choices logged in
`CONTEXT.md` ("Regional dishes in the nutrition pipeline"), the owner answered
**"Approve all"**.

| Item | Answer | What it means |
|---|---|---|
| **D2** Slice 8 rubric | Approved as written | Slice 8 is scored by it: licensing 20, native pipeline 25, tooling 15, in-app 15, content 25 × min(1, dishes ÷ D_full); at most 50 with no authored dish |
| **D4** native licence group | Group N, as built | No change |
| **D5** calorie factors | General 4/4/9/7, as built | No change |
| **D6**, **D7** | As built | Nine calorie nutrients; branded foods out of v1 |
| **D8** SFDA as a benchmark | Not used | The pipeline refuses it, as built |
| The other regional-dish choices | Approved | Recipes only, 15 % / 20 % report thresholds, `borrowed` portions, transliteration in the English name, `regional-` ids, CSV only, no cross-source carbohydrate |

**Still open from Slice 8:** D3, the number of dishes that counts as full
coverage, and the reference material for the first batch.

**Still open:** T07/T08, the Diet Profile build, waits on the Diet Profile
Addendum v1.0. It is not in this repository. A file named
`almanac-diet-profile-addendum.md` (v1.0 draft, 2026-09-25, "awaiting owner
approval") is in the owner's Downloads folder; the owner has been told and asked
to confirm it is the one.
