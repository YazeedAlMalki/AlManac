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

**Still open:** T07/T08, the Diet Profile build, waits on the Diet Profile
Addendum v1.0. It is not in this repository. A file named
`almanac-diet-profile-addendum.md` (v1.0 draft, 2026-09-25, "awaiting owner
approval") is in the owner's Downloads folder; the owner has been told and asked
to confirm it is the one.
