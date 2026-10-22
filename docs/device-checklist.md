# Three checks on your iPhone

About 20 minutes. No Mac needed; Almanac must already be on the phone. For each
check, write **pass** or **fail** and the time, and send a screenshot of anything
that looks wrong. These are the only parts of phases 3, 11 and 12 a simulator
cannot prove.

## 1. Water reaches Apple Health (phase 3)

1. Almanac → **Settings** → **HealthKit** → **Connect to Health**. Allow
   everything iOS asks for, Water included.
2. Open **Quick Log** → **Water** → tap **+250**. Note the time.
3. Open Apple's **Health** app → **Browse** → **Nutrition** → **Water** →
   **Show All Data**.
   **Pass:** a 250 mL entry at that time, with Almanac named as its source.
4. Back in Health, tap **Add Data**, enter 300 mL, **Add**. Open Almanac and
   look at today's water.
   **Pass:** the 300 mL shows once, not twice.
5. Close Almanac fully (swipe it away) and open it again. Do not open Settings.
   Log **+250** once more, then look in Health as in step 3.
   **Pass:** the new 250 mL is there, without tapping Connect again. An entry
   still on its way says "Not yet in Apple Health" under it in Almanac's
   Hydration screen, and the line goes once it arrives.

## 2. A reminder arrives on time (phase 11)

1. Almanac → **Settings** → **Reminders** → turn on **Remind me to drink water**.
   Allow notifications if iOS asks.
2. Set **Every 15 min**, **From** the current hour, **Until** an hour later.
3. **Settings** → **All reminders**. Note the **Queued now** number (it should
   be more than 0).
4. Lock the phone and wait for the next quarter hour (:00, :15, :30, :45).
   **Pass:** a water reminder appears on the lock screen within a minute of it.
5. Turn **Remind me to drink water** off again if you do not want it.

## 3. A backup restores (phase 12)

Use food for this check, not water: water also goes to Apple Health, so it can
come back from there after a restore.

1. Log one food you will recognise in **Quick Log** → **Food**, say "first".
2. Almanac → **Settings** → **Data** → **Backup & restore** → **Create backup**.
   A new line appears under **Backups on this device**.
3. Tap **Share latest backup**. Choose a passphrase of 8 or more characters, type
   it twice, tap **Encrypt**, then **Share encrypted backup** and save the file to
   **Files** (On My iPhone). Remember the passphrase.
4. Log a second, different food ("second").
5. Back in **Backup & restore**, tap **Restore** on the backup from step 2 →
   **Restore and restart**.
   **Pass:** the app restarts; the first food is there and the second is not.
6. Close Almanac fully (swipe it away), open it again, wait a minute, then look
   at today's water.
   **Pass:** each Health entry from check 1 appears once, not twice.

## 4. Encrypted backups, erase, locked-phone intents (added 2026-10-22, audit P0/P1)

These check what only a real phone can: Apple's cryptography on real hardware, the
app quitting, and what iOS allows from a locked screen. Nothing here has been run.

1. **Encrypted import.** In **Files**, open the file saved in check 3. It must not
   open as a database or a zip (it is not readable). In Almanac → **Settings** →
   **Backup & restore** → **Import backup…**, pick that file.
   **Pass:** Almanac asks for a passphrase; a wrong one says "The passphrase is wrong,
   or the backup file is damaged." and imports nothing; the right one adds an
   "imported-…" line under **Backups on this device**.
2. **Plain copies.** Open the **Files** app and look for any `.zip` or unencrypted
   Almanac backup you did not save yourself.
   **Pass:** there is none (Almanac only hands out the encrypted copy).
3. **Export.** **Settings** → **Data** → **Export my data…** → **Share export**,
   save to Files, open it.
   **Pass:** readable JSON that includes your profile and a food or water entry, and
   the screen said the file is not encrypted.
4. **Erase.** Make sure check 3's backup is saved somewhere outside Almanac first.
   **Settings** → **Data** → **Erase all data…** → **Erase everything and restart**.
   **Pass:** the app quits; reopening it is a first launch with none of your
   records; Settings → **Backup & restore** shows no backups; no reminders from
   before arrive. Apple Health still holds what was synced there (expected).
5. **Intents on a locked phone.** Add the Almanac widget (water) to the Lock
   Screen, lock the phone, and tap the +250 button.
   **Record:** whether iOS asks you to unlock first, and whether the glass was added
   without unlocking. This settles audit finding S-16; write what happened.

If a step does not match what you see on screen (a button with another name, a
screen that is not there), stop and send a screenshot: that is a finding too.
