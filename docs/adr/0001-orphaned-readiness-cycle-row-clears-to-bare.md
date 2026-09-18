# Orphaned readiness_cycle row clears to bare, not deleted

When a correction moves a primary episode's wake across an anchor-date
boundary, the `readiness_cycle` row for its *previous* anchor date no
longer has a real primary episode behind it. We reconcile it by clearing
`primarySleepEpisodeId`/`primaryWakeTimestamp`/`cycleStartTimestamp`/
`cycleEndTimestamp`/`circadianContextId` back to null — the same shape
`ensureCycle` produces before classification ever runs — rather than
deleting the row outright.

We picked clear-over-delete because the row's `id` may already be
referenced elsewhere (an existing `readinessCycleId` FK on a wellness log
that hasn't been re-linked yet, or a future feature that keeps a cycle id
around for its own record-keeping), and because "a day with no known
primary episode yet" is already a first-class, well-understood state in
this codebase (`ensureCycle`'s bare cycle) — reverting to it is not a new
concept. Deleting would need answering "cascade to what, and is it ever
safe" on top of the reconciliation itself, for questionable benefit — the
row is inert and correctly excluded from neighbor-finding either way
(`allCycles()`'s nil-`cycleStartTimestamp` handling already treats it as
positionless).
