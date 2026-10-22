# Almanac privacy notice (draft)

> **Draft for legal review.** This describes what the app does today. It is not
> legal advice, has not been reviewed by a lawyer, and does not by itself make the
> app compliant with the Saudi PDPL, the GDPR or Apple's rules. Items in
> [square brackets] must be completed by the publisher before release. The short
> in-app version is Settings → About → Privacy (`Native/Almanac/PrivacyViews.swift`);
> keep the two, and `Native/Almanac/PrivacyInfo.xcprivacy`, in step.

**Publisher / contact:** [name, address and contact for privacy questions]
**Last updated:** 2026-10-22

## In one paragraph

Almanac keeps everything you record on your phone. It has no account, no server,
no analytics, no advertising and no third-party SDK, and it makes no network
requests of its own. Nothing is sent to the publisher or to anyone else unless you
choose to share a backup or an export.

## What is stored, and why

All of it is stored in a database on your phone. Each item is stored because a
feature you use needs it.

| Data | Why it is needed |
|---|---|
| Meals, water, caffeine, supplements | Nutrition, hydration and reminders |
| Training sessions, programs, body measurements | Training and body tracking |
| Sleep, heart rate, heart-rate variability, steps, energy, workouts, weight, body fat, lean mass, waist (from Apple Health, if you connect it) | Readiness, trends and the history screens |
| Laboratory reports and results | The laboratory feature |
| Mood, soreness, digestion and urination logs | Wellness tracking and advisories |
| Fasting sessions, religious-fast schedule, prayer settings and completion | Fasting and prayer features. This can reveal religious practice; it never leaves the phone |
| Location (latitude and longitude) | Prayer times and qibla direction. Taken only when you tap "Use current location" or, once you have allowed it, when you open the app in automatic mode. It is kept on the phone until you change the city or erase your data |
| Profile: name, date of birth, biological sex, height, blood type, allergens, sports, optional email | Calorie targets, allergen filtering and greetings. The email is **optional, is not used by the app and is not sent anywhere** |
| Shift schedules | Readiness and reminders around shift work |

Health and religious-practice data are sensitive categories under the GDPR
(Art. 9) and the PDPL. Almanac processes them only on your phone.

## Permissions

- **Apple Health** — read and write only the types you allow. Almanac writes
  water, waist circumference, weight, body fat and lean mass you log in Almanac.
  It does not use Health data for advertising or sell it.
- **Location (when in use)** — prayer times and qibla only.
- **Notifications** — reminders are scheduled on the phone. Their text can name
  prayers, fasts and supplements and may appear on the lock screen.

## What leaves your phone, and when

| Action | What leaves | Protection |
|---|---|---|
| You share a backup | An **encrypted** copy of the whole database and documents | AES-256-GCM; key from a passphrase you choose (PBKDF2-HMAC-SHA256, 600,000 rounds). Almanac cannot recover a lost passphrase |
| You export your data | A readable JSON copy of your own records | **Not encrypted.** Share it only with people and apps you trust |
| You tap a source or licence link | Your browser opens that website | The website's own policy applies |
| iCloud or computer backups of the phone | Almanac's data folder, but **not** its Backups folder | Apple's device-backup protections |

Backups kept in Almanac's own Backups folder are not encrypted by the app. They
are inside the app's private storage and are left out of iCloud and computer
backups.

## Your choices

- **Access and portability:** Settings → Data → *Export my data*.
- **Deletion:** Settings → Data → *Erase all data* deletes the database, backups,
  documents, settings and scheduled reminders on the phone and restarts the app.
  Deleting the app does the same. Data already in Apple Health stays in Apple
  Health until you remove it there. A backup or export you already gave to someone
  else is theirs.
- **Permissions:** change or withdraw them in iOS Settings → Almanac.
- **Correction:** edit any record in the app.

## Retention

Records stay until you delete them. There is no server-side copy to delete.

## Children

[Decide the minimum age and state it. The app has no age gate.]

## Third-party content

Food, exercise and laboratory reference data comes from public datasets and
projects credited, with their licences, under Settings → About → Attributions
(`Sources/AlmanacCore/Provenance/Attribution.swift`).

## Changes

[State how users are told when this notice changes.] Any change that adds a server,
an SDK, analytics or a new data flow must update this notice, the in-app screen and
the privacy manifest before it ships.

## Known limits (honest list)

- No app lock: anyone who can unlock the phone can open Almanac.
- The database is protected by iOS's default file protection, not an app-specific
  key.
- Stored coordinates are not rounded.
- Notification text can show on a locked screen.
- Almanac is not a medical device and its advisories are not clinician-reviewed.

See `SECURITY_PRIVACY_AUDIT.md` for the security and privacy audit behind this
notice.
