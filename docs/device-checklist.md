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
3. Tap **Share latest backup** and save it to **Files** (On My iPhone).
4. Log a second, different food ("second").
5. Back in **Backup & restore**, tap **Restore** on the backup from step 2 →
   **Restore and restart**.
   **Pass:** the app restarts; the first food is there and the second is not.
6. Close Almanac fully (swipe it away), open it again, wait a minute, then look
   at today's water.
   **Pass:** each Health entry from check 1 appears once, not twice.

If a step does not match what you see on screen (a button with another name, a
screen that is not there), stop and send a screenshot: that is a finding too.
