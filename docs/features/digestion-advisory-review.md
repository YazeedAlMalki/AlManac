# Digestion advisory — clinical review packet

Prepared 2026-11-09. **Status: draft implementation; no clinician has approved
the rules, English wording, or Arabic wording.** BRD §6.3's clinician-review
requirement before App Store release remains open. Checking public references
does not constitute that review.

## Changes in this draft

- Black stool and severe pain now raise the urgent level without requiring a
  second recorded symptom. The logger does not distinguish black from tarry
  stool, or locate the pain, so this is a conservative implementation choice
  for review, not a validated triage algorithm.
- A streak of blood raises the contact-professional level. A missing or
  unrecognised blood amount gets its own reason, never a description of a small
  streak. Neither food nor medicine is presented as ruling out bleeding.
- The alert and advisory card give a next step. The urgent text distinguishes
  urgent help from emergency help for heavy/continuous bleeding, faintness, or
  severe pain with bleeding. It uses a local emergency number, not a UK/US
  number in a worldwide interface.
- Review status remains visible. Levels are calculated when read and are never
  written into `clinicianEscalationLevel`.

## Source mapping

These public references were read on 2026-11-09; the app's sentences are
paraphrases. Local clinical advice and emergency pathways still need review.

| Reference | What informs this draft |
|---|---|
| [NHS: rectal bleeding](https://www.nhs.uk/symptoms/bleeding-from-the-bottom-rectal-bleeding/) | Black/dark-red stool and bloody diarrhoea need urgent assessment; substantial or continuous bleeding needs emergency care. Foods and iron can change colour but do not establish the cause. |
| [MedlinePlus: gastrointestinal bleeding](https://medlineplus.gov/ency/article/003133.htm) | Small amounts of blood warrant professional advice. Black/tarry stool, large amounts, dizziness from bleeding, or severe abdominal pain with bleeding warrant emergency assessment. |
| [NIDDK: GI bleeding symptoms](https://www.niddk.nih.gov/health-information/digestive-diseases/gastrointestinal-bleeding/symptoms-causes) | Acute/severe bleeding needs prompt help; black/tarry stool, blood, dizziness and abdominal pain can be associated signs. |
| [NIDDK: diarrhoea symptoms](https://www.niddk.nih.gov/health-information/digestive-diseases/diarrhea/symptoms-causes) | Severe abdominal/rectal pain, bleeding, dehydration and prolonged/frequent diarrhoea need medical attention. A stool log alone cannot establish these conditions or their absence. |

## Rules requiring a clinician's decision

| Current rule | Review question |
|---|---|
| Urgent: large blood; blood with Bristol 6–7; blood/black stool with dizziness; severe pain; black stool | Are the inputs, urgency and wording sufficient? Should the form distinguish tarry stool, ongoing bleeding, fainting and pain location? |
| Contact professional: small/streak/unspecified blood, repeated bleeding, red stool, dizziness alone | Are the actions and timing appropriate? The app cannot exclude bleeding from colour or medication history. |
| Very loose stool on 3 distinct days in 7 → contact professional | This is an existing product heuristic, not the NIDDK duration/frequency definition. Should elapsed time, number of stools, dehydration, fever and risk factors be collected instead? |
| Pale stool twice in 7 days → contact; once → information | Existing heuristic: no reviewed source validates this exact threshold. Confirm or replace it and its wording. |
| Hard stool on 3 days in 7 → information | Confirm the trigger and self-care wording, including restrictions on fluid/fibre advice. |
| No matched rule → no advisory | This means no rule matched, not that symptoms are safe. This classifier has not been validated for children, pregnancy, immunosuppression or other higher-risk groups. |

Both languages need review in the saved-entry card and urgent alert, including
VoiceOver, large text, right-to-left layout and the local emergency action.

## Approval record

No approval recorded. A reviewer should record their name, clinical role,
date, reviewed commit, population and jurisdiction, exact approved rules and
wording in each language, and any exclusions. After changes, attach the final
test results and review the rendered screens. Do not close the release item
until this record exists.

## Verification

`DigestionAdvisoryTests` covers escalation, unknown amounts, seven-day bounds,
same-day counting, highest-level precedence, and leaving stored levels empty.
`LocalizationTableTests` checks Arabic coverage and formatting.
`DigestionQuickEntryUITests` checks that the urgent alert and card contain the
next step and review note. Passing tests establish implementation behavior,
not clinical validity.
