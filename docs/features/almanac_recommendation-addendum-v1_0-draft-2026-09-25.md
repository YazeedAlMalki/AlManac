# Almanac — Diet & Goal Recommendation Addendum

**Product:** Almanac (body-monitor app)
**Addendum to:** BRD v1.6 §6.6 Body Composition, §6.10 Goals & Targets, §6.14 Smart Notifications
**Depends on:** Diet Profile Addendum v1.0 (draft), Body Measurements v0.1 (revised)
**Version:** 1.0 (draft) | **Date:** 2026-09-25 | **Owner:** Yazeed | **Status:** Draft, awaiting owner approval
**Scope source:** Structured interview with Yazeed, 2026-09-25 (decisions R1–R15)

---

## 1. Purpose

A new user doesn't know which of the 12 diets or which Goal fits them, and doesn't know where their body stands. A returning user may want to change diet or physique. This addendum defines one feature that serves both: the user states what they're aiming for, Almanac shows them a **body-type label** they can recognise themselves in, and hands back a **Goal** and a **ranked shortlist of 2–3 diets**, with reasons. It can be run any time, and Almanac nudges the user to re-run it when something meaningful changes.

It does **not** commit anything. Committing a Goal still goes through §6.10; committing a diet still goes through the Diet addendum's FAQ → commit flow (§7 there).

## 2. Decision record (interview 2026-09-25)

| # | Decision | Answer |
|---|---|---|
| R1 | Output | **Body type + Goal + Diet.** |
| R2 | What "body type" means | **Two separate labels:** shape (where fat sits) and composition (how much fat vs. muscle). |
| R3 | Composition source | **Smart-scale body-fat %, in a later update.** First release shows the shape label only. |
| R4 | Who sets the aim | **The user states it.** The app never proposes an aim. |
| R5 | Recomposition | **"Reshape" is an aim, mapped to Maintain** calories with High-Protein first in the shortlist. §6.10 is unchanged. |
| R6 | Role of the shape label | **Both:** shown for self-recognition, and combined with the aim to rank the diets. |
| R7 | Diet output | **Ranked shortlist of 2–3**, each with a one-line reason. |
| R8 | Shape label set | **Sex-specific lists**, chosen by `ProfileStore.sex`. |
| R9 | Re-running | **On request + nudges.** Never switches Goal or diet by itself. |
| R10 | Nudge triggers | **Goal weight reached, shape label changed, progress stalled, long time on one diet.** |
| R11 | Shoulder data | **Shoulders added** as an 8th Body Measurements point. |
| R12 | Missing measurements | **Ask for them first.** No result is shown until the shape inputs exist. |
| R13 | Entry points | **Offered at first run with "Later"**, always reachable in-app. |
| R14 | History | **Latest run only**, overwritten each time. |
| R15 | Safety | **Short health questions filter risky diets out of the shortlist.** Answers are **stored on the profile.** |

## 3. Flow

```
Entry (first run, Diet/Goals area, or a nudge)
  │
  ├─▶ 1. Aim ──────────── "What are you aiming for?"  (R4)
  │                         lose fat · build muscle · maintain · perform · reshape
  │
  ├─▶ 2. Health questions  shown if never answered; otherwise "Still accurate?" with Edit  (R15)
  │
  ├─▶ 3. Measurements ──── ask for any missing shape input  (R12, §5.2)
  │
  └─▶ 4. Result
         ├─ Shape label + one-line plain description        (R6, R8)
         ├─ Composition label  — later update               (R3)
         ├─ Goal  (from the aim, §4)
         └─ Diet shortlist 1–3, each with a reason          (R7)
                 └─ tap a diet ─▶ Diet addendum detail → FAQ → Commit
```

- The user can leave at any step. Nothing is stored until the result screen is reached (§7).
- At first run, "Later" skips the whole flow; the user lands in the No-diet state (Diet addendum §6).
- The full, unranked diet list (Diet addendum §7) is unchanged and stays reachable. The shortlist is a separate screen; it doesn't add rankings or badges to that list.

## 4. Aim → Goal

| Aim (user-facing) | Goal (§6.10) | Note |
|---|---|---|
| Lose fat | Cut | |
| Build muscle | Bulk | |
| Maintain | Maintain | |
| Perform | Performance | |
| Reshape (lose fat and build muscle) | Maintain | High-Protein is ranked first when it passes the safety filter (R5). |

The Goal is shown as a suggestion with a **Set this goal** action. Setting it follows §6.10 as usual (new target snapshot).

## 5. Shape label

### 5.1 Label sets (R8)

| `ProfileStore.sex` | Labels |
|---|---|
| Female | hourglass · pear · apple · rectangle · inverted triangle |
| Male | rectangle · triangle · inverted triangle · oval · trapezoid |
| Not set | The flow asks for it before step 3 (it also drives the Body Measurements outline, OI-8 there). |

Each label carries a one-line, neutral description of proportions (e.g. "Hips wider than shoulders"). Wording rules in §9.

### 5.2 Inputs

- Shoulders, chest, waist, hips, from the latest `body_measurement` row of each type. Shoulders is the 8th point added by R11.
- **Staleness:** a value older than a set age counts as missing and is asked for again (OI-9).

### 5.3 Rules

The classification thresholds (ratios between shoulders, chest, waist and hips per label) are **not set in this draft**. Common systems come from clothing-fit research and are not health-validated; only waist-to-hip ratio is (WHO cut-offs 0.90 men / 0.85 women). Thresholds must be sourced and cited before build (OI-1). Every rule set carries a `shape_rule_version`.

### 5.4 Composition label (R3 — later update)

Fed by body-fat % from a smart scale. Most smart scales write body-fat % and lean mass into Apple Health, so this is likely a HealthKit read into BRD §6.6's body-fat record. Label set, thresholds, and how it affects the shortlist are deferred to that update (OI-2). Until then the result screen shows no composition label and no placeholder.

## 6. Diet shortlist

### 6.1 Order of operations

1. **Candidate set:** all 12 diets.
2. **Safety filter (R15, §6.3):** remove every diet excluded by the user's health answers.
3. **Base rank by aim (§6.2).**
4. **Shape modifier (R6):** reorder within the remaining candidates using the shape × aim table (OI-3).
5. **Eligibility:** Carb-Periodized stays in only when the user trains about an hour or more most days (its own "Who it suits" line). The data source for that check is OI-7.
6. **Take the top 3.** If fewer than 3 survive, show what survives. If none survive, show Balanced if it survives, otherwise no shortlist and a note to talk to a doctor.

### 6.2 Base rank by aim — proposed default

Derived from each diet's "Who it suits" line in the Diet addendum §5. **Proposed, not confirmed (OI-4).**

| Aim | 1st | 2nd | 3rd |
|---|---|---|---|
| Lose fat | High-Protein | Mediterranean | Low-Carb |
| Build muscle | High-Protein | Balanced | Zone |
| Maintain | Balanced | Mediterranean | Plant-based |
| Perform | Carb-Periodized | Balanced | High-Protein |
| Reshape | High-Protein | Balanced | Zone |

Keto, Carnivore, DASH, Paleo and Low-Fat are not in any default top 3. They enter only through the shape modifier or when higher-ranked diets are filtered out. All 12 remain available from the full list.

### 6.3 Health questions and the safety filter (R15)

Each question comes from a "talk to your doctor first" item already in the Diet addendum FAQ. Answers: **Yes / No / Prefer not to say.** Treatment of "Prefer not to say" is OI-5.

| # | Question | Excluded from shortlist | Source |
|---|---|---|---|
| H1 | Are you pregnant or breastfeeding? | Keto, Carnivore | Diet addendum §5.6 FAQ 3, §5.7 FAQ 3 |
| H2 | Do you take insulin, a sulfonylurea, or an SGLT2 inhibitor? | Keto, Low-Carb | §5.5 FAQ 4, §5.6 FAQ 3 |
| H3 | Do you have kidney disease or reduced kidney function? | Keto, Carnivore, High-Protein | §5.2 FAQ 2, §5.6, §5.7 |
| H4 | Do you have high LDL cholesterol or heart disease? | Carnivore | §5.7 FAQ 3 |
| H5 | Do you have gout? | Carnivore | §5.7 FAQ 3 |
| H6 | Do you have pancreatitis, liver disease, kidney stones, or a fat-metabolism disorder? | Keto | §5.6 FAQ 3 |
| H7 | Do you have very high triglycerides? | Low-Fat | §5.11 FAQ 3 |
| H8 | Do you take blood-pressure medication? | None. DASH gets a "tell your doctor" note in its reason line. | §5.4 FAQ 3 |
| H9 | Have you had an eating disorder? | Keto — and see OI-6 | §5.6 FAQ 3 |

- The filter only removes diets from the **shortlist**. An excluded diet stays in the full list, with its FAQ, and the user can commit to it knowingly. This keeps Diet addendum D10 (no gating) intact.
- The result screen says how many diets were left out for safety and lets the user see which ("2 diets hidden based on your health answers").
- Answers are editable any time from Profile.

## 7. Data model

### 7.1 `profile_health_answer` (R15)

| Column | Type | Notes |
|---|---|---|
| `question_id` | text, PK | `H1`…`H9` |
| `answer` | enum | `yes`, `no`, `prefer_not` |
| `answered_at` | timestamp | |
| `question_set_version` | text | Changes when wording or the list changes; a changed question is asked again |

Singleton-profile pattern (no user column), matching `hydration_profile`.

### 7.2 `diet_recommendation` (R14 — latest only)

One row, `id = 'latest'`, replaced on each completed run.

| Column | Type | Notes |
|---|---|---|
| `run_at` | timestamp | |
| `aim` | enum | `lose_fat`, `build_muscle`, `maintain`, `perform`, `reshape` |
| `suggested_goal` | enum | §4 |
| `shape_label` | enum | §5.1 |
| `composition_label` | enum, nullable | Null until the R3 update |
| `shortlist` | JSON | `[{diet_id, rank, reason}]`, 1–3 items |
| `excluded_diets` | JSON | `[{diet_id, question_id}]` |
| `inputs` | JSON | Measurement row ids and values, weight, sex, height used |
| `shape_rule_version`, `ranking_rule_version`, `question_set_version` | text | So a nudge can tell a real label change from a rule change |

- Only the result screen writes this row. Abandoned runs leave the previous row in place.
- Rule changes re-label on the **next** run only; the stored row is never rewritten silently (BRD §6.9 historical-integrity principle).

## 8. Nudges (R9, R10)

| Trigger | Fires when | Proposed default (OI-10) |
|---|---|---|
| Goal weight reached | 7-day average weight crosses the goal weight (Diet addendum §4.3) in the aim's direction | — |
| Shape label changed | New measurements classify into a different label than `diet_recommendation.shape_label`, under the same `shape_rule_version` | — |
| Progress stalled | Aim is lose fat, build muscle or reshape, and neither 7-day average weight nor waist has moved meaningfully | 3 weeks, ±0.5 kg / ±1 cm |
| Long time on one diet | Current diet snapshot (Diet addendum §8) is older than a set period | 12 weeks |

- Nudges are notifications under §6.14: individually toggleable, and suppressed by its rules (confirmed fast, dry fast, post-shift sleep, etc.).
- **Discretion default (§6.14):** nudge text never names the shape label, body values or health answers. E.g. "Time for a check-in on your plan?"
- One nudge per trigger event; a dismissed nudge doesn't repeat until the trigger fires again (OI-11 for any global cap).
- Nudges open the flow at step 1. They never change anything by themselves.

## 9. Wording principles

- **Descriptive, not judging.** Labels describe proportions ("shoulders wider than hips"), never "problem areas", never good/bad.
- **No weight or appearance targets** tied to a shape. The app doesn't suggest changing shape to a different label.
- **Reasons cite the rule, not the user's body worth.** "High-Protein: helps keep muscle while losing fat."
- All label descriptions and reason lines go through the same clinician review as the Diet addendum (OI-8).

## 10. Knock-on changes to other documents

| Document | Change |
|---|---|
| Diet Profile Addendum | **D9 reversed:** screening questions now exist and answers are stored (§6.3, §7.1). **D10 unchanged:** the filter hides diets from the shortlist only; nothing is gated. §7's full list stays unranked. |
| Body Measurements v0.1 | M1 → **eight points** (shoulders added); outline gets a shoulder zone; validation range added. Done in the revised doc. |
| BRD §6.6 | Composition label will read body-fat % (R3). The "user-definable circumference" conflict (Body Measurements OI-7) is unaffected but still open. |
| BRD §6.10 | None. Reshape maps to Maintain (R5). |
| BRD §6.14 | Four new notification types (§8), each toggleable. |
| BRD §6.18 / §6.19 | Health answers are in the profile, so they are in the backup ZIP. Export encryption is deferred to Pre-App Store Hardening (OI-12). |

## 11. Acceptance criteria

- [ ] Choosing an aim maps to the Goal in §4. "Reshape" maps to Maintain.
- [ ] With any of shoulders/chest/waist/hips missing or stale, the flow asks for them and shows no result until they're entered.
- [ ] A female profile only ever gets a label from the female set; a male profile only from the male set.
- [ ] Answering Yes to H3 removes Keto, Carnivore and High-Protein from the shortlist; all three still appear in the full diet list and can be committed.
- [ ] The result screen states how many diets were hidden for safety, and which, on tap.
- [ ] The shortlist has at most 3 diets, ranked, each with a reason.
- [ ] Carb-Periodized never appears for a user who doesn't meet its training eligibility.
- [ ] Nothing is committed from the result screen without going through the Diet addendum commit flow or §6.10.
- [ ] Completing a run replaces `diet_recommendation`; abandoning a run leaves the previous row untouched.
- [ ] A shape-rule version change does not fire the "shape label changed" nudge.
- [ ] No nudge text contains a shape label, a body value or a health answer.
- [ ] Nudges respect every §6.14 suppression rule.
- [ ] "Later" at first run leaves the user in the No-diet state, with the flow reachable from the Diet/Goals area.

## 12. Open items

| # | Item | Owner |
|---|---|---|
| OI-1 | Source and cite shape thresholds per sex (§5.3). | Claude (research) → Yazeed (confirm) |
| OI-2 | Composition label: label set, thresholds, effect on shortlist (R3, later update). | Yazeed (decide, at that update) |
| OI-3 | Shape × aim modifier table (§6.1 step 4). Needs sources; evidence that shape should change diet choice is weak outside central-fat/metabolic risk. | Claude (research) → Yazeed (decide) |
| OI-4 | Confirm or amend the base ranking (§6.2). | Yazeed (confirm) |
| OI-5 | "Prefer not to say": treat as Yes (exclude) or No (keep)? | Yazeed (decide) |
| OI-6 | H9 (eating-disorder history): should a Yes also soften or skip the shape label and measurement steps, not just filter Keto? A shape-focused flow may not be appropriate for that user. | Yazeed (decide) + clinician |
| OI-7 | Carb-Periodized eligibility source: planned sessions, logged sessions, or ask the user. | Yazeed (decide) |
| OI-8 | Clinician review: health questions, exclusion map, label descriptions, reason lines. Same gate as Diet addendum OI-1. | Yazeed (arrange) |
| OI-9 | Staleness age for shape inputs (e.g. 30 days?). | Yazeed (decide) |
| OI-10 | Confirm nudge defaults (§8). | Yazeed (confirm) |
| OI-11 | Global nudge cap (e.g. at most one recommendation nudge per week)? | Yazeed (decide) |
| OI-12 | Health answers in unencrypted backups until Pre-App Store Hardening: accept, or exclude them from export until encryption lands? | Yazeed (decide) |

## 13. Next steps

**Yazeed (personal):**

- Approve or amend this addendum.
- Decide OI-5, OI-6, OI-7, OI-9, OI-11, OI-12; confirm OI-4 and OI-10.
- OI-6 and OI-12 first — both are about who could be harmed, not about behaviour.
- Arrange clinician review (OI-8), bundled with the Diet addendum's OI-1.

**AI-delegatable:**

- Research and cite shape thresholds (OI-1) and the shape × aim evidence (OI-3).
- Amend the Diet Profile addendum for D9 (§10).
- Migrations: `profile_health_answer`, `diet_recommendation`; `shoulders` added to `body_measurement.measurement_type`.
- Recommendation engine (pure function: aim + measurements + profile + answers + rule versions → result) with tests against §11.
- Nudge rules into the existing §6.14 suppression matrix (Slice 11).
- Flow UI: aim, health questions, missing-measurement prompt, result.

## 14. Suggested skills

Skills available in Claude sessions that fit this work. In Claude Code on `yamal`/iMac they only apply if installed there.

| Step | Skill | Why |
|---|---|---|
| Pin terms before code | `mattpocock-skills:domain-modeling` | *Aim*, *Goal*, *Diet*, *shape label*, *composition label*, *shortlist* are easy to blur; a glossary keeps code names aligned with this doc. |
| Source OI-1 and OI-3 | `mattpocock-skills:research` | Primary-source lookup for shape thresholds and shape/diet evidence, saved as a cited file. |
| Clinician review (OI-8) | `mattpocock-skills:to-questionnaire` | Turns the review into a questionnaire a clinician can fill in without reading three addenda. |
| Break the build into commits | `mattpocock-skills:to-tickets` | Migrations → engine → safety filter → nudges → UI, with blocking edges. |
| Engine + filter | `mattpocock-skills:tdd` | §11 converts directly to failing tests; the engine is a pure function, ideal for test-first. |
| Flow UI | `mattpocock-skills:prototype` | Try the four-step flow and the result screen before committing SwiftUI. |
| Before merge | `mattpocock-skills:code-review` | Reviews against this doc and repo standards. |

## 15. Sources

- Diet Profile Addendum v1.0 (draft, 2026-09-25) — diet catalog, "Who it suits" lines, safety FAQ items, commit flow.
- BRD v1.6 §6.6, §6.9, §6.10, §6.14, §6.18, §6.19.
- WHO (2008). *Waist circumference and waist–hip ratio: report of a WHO expert consultation* — WHR cut-offs 0.90 (men), 0.85 (women).
