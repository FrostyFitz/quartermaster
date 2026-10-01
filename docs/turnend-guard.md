# Primary turn-end supervision guard

This doc explains the check that stops a primary Firstmate session from ending a turn while its work has no live supervision, and how each harness enforces that check at its turn boundary.
It is for operators working out why a turn end was blocked or followed up, and for anyone changing a harness turn-end hook.

This is the authoritative current contract for the "no turn ends blind" primary backstop referenced from AGENTS.md section 8.
The predicate lives in `bin/fm-turnend-guard.sh`.
Primary scope lives in `bin/fm-primary-scope-lib.sh`, shared with the native session-start adapters in [`sessionstart-nudge.md`](sessionstart-nudge.md).
Harness hook files adapt each enabled primary harness integration's turn-end mechanism to that shared predicate.

Related PreToolUse guards deny unsafe commands before execution rather than detecting a blind turn end afterward.
Their separate owners are [`arm-pretool-check.md`](arm-pretool-check.md), [`cd-guard.md`](cd-guard.md), and [`subagent-guard.md`](subagent-guard.md).
Do not infer this guard's scope, loop safety, or compatibility tradeoffs for those guards.

## Find a topic

| Question | Start here |
| --- | --- |
| What the guard enforces | [Current invariant](#current-invariant) |
| Which sessions are in scope and what counts as supervision need | [Primary scope](#primary-scope) and [supervision need](#supervision-need) |
| How the turn-end check and the mid-turn pull warning judge watcher health | [Strict watcher check at the turn boundary](#strict-watcher-check-at-the-turn-boundary) and [pull-warning verdict by supervision model](#pull-warning-verdict-by-supervision-model) |
| Away and quiet mode | [Away and quiet mode daemon ownership](#away-and-quiet-mode-daemon-ownership) |
| How long a beacon stays fresh | [Guard grace and the poll cadence](#guard-grace-and-the-poll-cadence) |
| How Claude blocks or follows up | [Harness integrations](#harness-integrations) |
| Claude's Stop auto-arm cooperation, block budget, and fail-open | [Claude cooperative mode](#claude-cooperative-mode) |
| Known gaps | [Compatibility limits](#compatibility-limits) |
| Tests and live evidence | [Regression coverage](#regression-coverage) |

## Current invariant

`bin/fm-guard.sh` is a pull-based warning that runs only when another supervision command invokes it.
The turn-end guard closes the remaining gap at the primary's own turn boundary.

The guard acts at that boundary when both of these hold:

- Work, a process-event source, a registered custom check, or Relay polling needs supervision.
- No identity-matched watcher has a fresh beacon.

The beacon is `state/.last-watcher-beat`, which `bin/fm-watch.sh` touches every cycle, as [Guard grace and the poll cadence](#guard-grace-and-the-poll-cadence) describes.
When the guard acts, the harness integration must do one of two things:

- Block the turn end.
- Force one bounded follow-up that uses the recovery instruction from the emitted session-start protocol.

The mid-turn pull warning uses the model-aware supervision verdict described below, while the turn-end guard keeps the PID-strict watcher predicate.

Away and quiet mode are the one place the turn-end guard accepts a different supervisor.
While `state/.afk` exists, in either mode (`bin/fm-wake-lib.sh`'s `fm_afk_mode`), the daemon owns supervision.
A live identity-matched daemon with a fresh beacon then satisfies that boundary in place of a watcher process holding the lock.

The guard remains a backstop.
[`watcher-continuity.md`](watcher-continuity.md) owns normal continuity.

## Guard predicates

The turn-end guard checks primary scope first, then supervision need, then watcher health.
The mid-turn pull warning in `bin/fm-guard.sh` judges watcher health differently, as described under [pull-warning verdict by supervision model](#pull-warning-verdict-by-supervision-model).

### Primary scope

The guard first calls the shared primary scope.
A secondmate home runs its own primary Firstmate session, so a genuine `.fm-secondmate-home` marker includes it whether the home is a linked worktree or plain clone.
The marker must meet both of these conditions:

- It is a regular non-symlink file.
- Its whitespace-stripped first line is a non-empty identifier containing only letters, digits, dots, underscores, and dashes.

An unmarked checkout or invalid marker falls through to the git-dir check.
That check keeps crewmate and scout linked worktrees inert because their git dir differs from their git common dir.
It also requires `AGENTS.md`, `bin/`, and the effective state directory.

### Supervision need

For an in-scope primary, the guard counts in-flight work from `state/*.meta`.
These sources also count toward supervision need:

- Registered `state/procevent/*.source` records require supervision even though they have no task metadata.
- Every mode treats `state/x-watch.check.sh` as supervision need, so Relay polling remains guarded without an in-flight task.
- A custom check registered with `bin/fm-check-register.sh` counts the same way, so an operator's home-level poll keeps running after the last task is torn down.

The default cross-harness mode exits silently with no supervision need.

### Strict watcher check at the turn boundary

Otherwise the guard calls `fm_watcher_healthy <state-dir> <watch-path> [grace-seconds] [home]` from `bin/fm-wake-lib.sh`.
It is the same PID-strict identity-matched lock and fresh-beacon check used by `bin/fm-watch-arm.sh`.
Under that check:

- A stale beacon blocks even when a watcher pid is live.
- A fresh leftover beacon blocks when the lock is missing, dead, or identity-mismatched.

The turn-end guard needs that strict check because it fires at the turn boundary.
At that boundary the auto-arm is bringing a fresh watcher up for the upcoming idle period.
The guard cooperates with that arm rather than trusting a beacon left by the cycle that just ended.

### Foreign session-lock owner

When an active home instead has a live session lock held by a verified harness that the current session does not own, the Claude guard emits a read-only ownership diagnostic and allows the turn to end safely.

Ownership is the shared `fm_session_lock_owned_by_self` verdict in `bin/fm-session-lock-lib.sh`.
The current session owns the lock when either of these holds:

- The recorded pid is a member of the current session's contiguous harness ancestry.
- The trusted Claude session id recorded beside the lock in `state/.lock-session` matches this hook's own environment while the recorded pid is still a live harness.

That second signal keeps a background Claude session owning its own lock after the transient helper chain between its hooks and its recorded owner is recycled.
The library's header owns the trust gate (`CLAUDE_PID` must be a Claude-shaped member of the current run).
`bin/fm-lock.sh` owns the sidecar and the line-1 anchor it records for such a session.

A Claude session that does not own the lock cannot arm or repair the home without stealing the live owner's lock, so blocking it would create an unbounded loop.
The lock-owning session remains responsible for restoring supervision.

The exception has these limits:

- Malformed, absent, dead, or ancestry-uncertain lock records do not satisfy this Claude-specific exception and retain the ordinary guard behavior.
- A missing or mismatched sidecar or an untrusted id adds nothing to the verdict, so a live owner outside the ancestry still takes this exit exactly as before.

### Pull-warning verdict by supervision model

`bin/fm-guard.sh`, the pull warning, instead uses the model-aware `fm_watcher_supervision_verdict` from `bin/fm-wake-lib.sh`.
It needs a different verdict because it fires mid-turn, when the auto-arm model runs no watcher at all.
The verdict depends on the supervision model.

#### Claude Stop auto-arm model

Under the Claude Stop auto-arm model a beacon fresh within grace is healthy even with no live watcher process.
A stale beacon is still healthy while `fm_autoarm_midturn_healthy` in `bin/fm-wake-lib.sh` proves a Claude rewake explains the mid-turn gap.
That proof requires both of these:

- The rewake is bound to the current recovery generation and live session-lock owner.
- No later watcher beacon or exhausted-failure marker supersedes it.

The tolerance holds because that session's turn-end will re-arm.
Without that proof a stale or absent beacon is a genuine lapse and alarms.

### Away and quiet mode daemon ownership

While `state/.afk` exists the daemon (`bin/fm-supervise-daemon.sh`) owns supervision and runs the watcher one-shot, in either away or quiet mode.
The watcher exits on every wake and the daemon starts its replacement.
A turn boundary therefore regularly lands in a hand-off where no watcher process holds the lock and nothing is wrong.

The turn-end guard therefore accepts `fm_afk_daemon_owns_supervision` from `bin/fm-wake-lib.sh` as proof of supervision on that path.
The proof requires both of these:

- `state/.afk` must exist; the predicate does not distinguish away from quiet mode.
- This home's `state/.supervise-daemon.lock` must name a live pid whose current process identity still matches the identity the daemon recorded for itself.

That is the same identity discipline the watcher lock uses.
A recycled pid, a lock left behind by a killed daemon, and a daemon that never recorded its identity all fail it.

A daemon that cannot record its own identity at startup logs a warning and keeps running, because a supervisor must not refuse to run over an unreadable `ps`.
That warning is what names the cause when the guard then keeps blocking away/quiet-mode turn boundaries for the rest of that daemon's life.

The proof covers ownership only, never freshness.
The guard still requires a fresh beacon, with these results:

- A daemon that stops restarting its watcher still blocks once the beacon passes grace.
- A home with no daemon and no watcher blocks exactly as it did before.

That beacon check uses the poll-derived grace described below rather than the flat `FM_GUARD_GRACE` default.
It uses that grace because the daemon starts a fresh one-shot watcher only after it finishes handling the previous wake.
That handling can legitimately outrun a fixed 300-second window under load (a slow registered check, a busy supervisor pane) with the daemon perfectly healthy throughout.

With `state/.afk` absent the daemon lock proves nothing and the strict watcher predicate is unchanged.

### State directory, grace, and missing input

- `FM_STATE_OVERRIDE` wins over `FM_HOME/state`, and `FM_HOME` wins over repository-root `state/`.
- `FM_GUARD_GRACE` controls beacon freshness and defaults to 300 seconds.
- If `jq` is missing or hook stdin is empty, the guard exits 0 because it cannot safely read loop-guard fields.

### Guard grace and the poll cadence

`bin/fm-watch.sh` touches `state/.last-watcher-beat` once per cycle, immediately before its terminal wait (`event_wait_or_sleep`) as well as at the top of the next cycle.
A healthy watcher's beacon can therefore legitimately age up to `FM_POLL` seconds between touches.

A fixed 300-second grace default stops correctly bounding staleness once a home's `FM_POLL` reaches or exceeds it.
A perfectly healthy watcher mid-wait would then read stale at the edge of every full poll cycle by definition.
That is exactly what a long-poll home (`FM_POLL=300`) hit against the Claude Stop-hook auto-arm (`bin/fm-claude-stop-autoarm.sh`).

Two readers derive their default grace from the configured poll instead of a bare constant:

- That hook.
- `bin/fm-watch.sh`'s own pre-acquisition staleness check (the "lock held by live pid but heartbeat is stale" refusal).

Both use `max(300, FM_POLL + 60)`.
The default never drops below the historical 300-second floor for the common short-poll case, but grows with the poll cadence once that cadence would otherwise outrun it.
`fm_poll_derived_grace` in `bin/fm-wake-lib.sh` is the single owner of that formula.

That refusal has a ceiling.
Once the live holder's beacon is stale past `FM_WATCHER_STALL_BOUND` (default three times the grace), the re-arm takes these steps:

1. It re-verifies the holder against the lock's recorded identity.
2. It retires the holder with TERM.
3. It starts in the holder's place.

A watcher wedged mid-cycle can therefore no longer refuse every replacement indefinitely.
`bin/fm-watch.sh`'s header owns the exact wording and the survives-TERM fallback.
Below that bound a stale beacon alone does not end an attached arm's watch of a live, identity-matched holder; a changed lock can end it sooner.
At the bound the arm reports a typed stalled-holder failure so its owner's retry can replace the holder.
`fm_watcher_stall_bound` in `bin/fm-wake-lib.sh` owns the shared derivation; `bin/fm-watch-arm.sh`'s header owns the exact attached-arm close behavior.

The auto-arm hook additionally exports its resolved `FM_GUARD_GRACE` when it forks `bin/fm-watch-arm.sh`.
The arm wrapper and the watcher it may start then judge staleness with the exact same value the hook just judged it with, whether that value came from an operator override or the poll-derived default.

`bin/fm-turnend-guard.sh`'s daemon-ownership branch (`fm_afk_daemon_owns_supervision`, above, covering both away and quiet mode) also derives its beacon grace from `fm_poll_derived_grace` rather than falling back to the bare 300-second default.
The reason is the same.
The daemon's watcher-restart cadence there is not a fixed poll loop, so a flat grace misreads a daemon that is genuinely still cycling as down.

Every other direct `FM_GUARD_GRACE` reader still falls back to the bare 300-second default unless `FM_GUARD_GRACE` is set explicitly in the environment.
Those readers are:

- `bin/fm-guard.sh`.
- The strict-watcher checks in `bin/fm-turnend-guard.sh` and its harness-specific wrappers.
- `bin/fm-wake-lib.sh`.

## Harness integrations

Each enabled primary harness adapts its own turn-end mechanism to the shared guard.

| Harness | Turn-end hook | How it enforces the guard |
| --- | --- | --- |
| Claude | Two `Stop` hooks in `.claude/settings.json` | Blocks with exit status 2, cooperating with the Stop auto-arm |

The registration in detail:

- Claude registers two `Stop` hooks in `.claude/settings.json`, both anchored through `CLAUDE_PROJECT_DIR`: `bin/fm-turnend-guard.sh --claude`, and `bin/fm-claude-stop-autoarm.sh` with `asyncRewake: true` and `timeout: 28800`.

### Claude blocking

Claude can block a Stop directly with exit status 2 and stderr.

### Claude cooperative mode

Claude runs the guard with `--claude`, which ignores `stop_hook_active` and cooperates with the Stop-owned auto-arm.
Claude Code sets `stop_hook_active=true` on every stop after any stop-hook continuation, including `asyncRewake` rewakes.
Under the default one-shot behavior, that re-opened the 2026-07-21 blind window.

Before the Claude cooperative budget can re-block a Stop, the guard checks for a live foreign session-lock owner and takes the same safe diagnostic exit described under "Guard predicates" ([foreign session-lock owner](#foreign-session-lock-owner)).

The Claude mode waits up to `FM_CLAUDE_AUTOARM_SYNC_WAIT_MS` (default 800 milliseconds).
It allows the stop when any of these holds:

- The watcher is healthy.
- The auto-arm's generation claim is open.
- `state/.claude-autoarm-epoch` contains a fresh actionable rewake owned by this event epoch.

#### Auto-arm generation claim

The claim is the ledger entry itself.
The ledger is `state/.claude-autoarm-epoch`:

- Its epoch sequence is a monotonic claim generation.
- Line 1 records the claim and terminal outcome.
- Line 2 records the claiming process's mandatory pid-identity.

`fm_autoarm_claim_open` and `fm_autoarm_claim_next` in `bin/fm-wake-lib.sh` own the format contract.

A claim is open while all of these hold:

- Its outcome is `arming`.
- Its owner pid is alive.
- Its recorded identity successfully recomputes and matches that pid.
- It is not stuck.

Stuck means the entry and the watcher beacon are both older than the guard grace, which proves the owner hung mid-arm.
A healthy hours-long foregrounded cycle keeps the beacon beating, and every arming phase with no watcher is bounded in seconds.

Anything else lets the next Stop-owned firing take the next generation and arm.
That covers a finished outcome, a dead or identity-mismatched owner, a stuck owner, an identityless entry, or no entry.
Taking a newer generation is the reclaim, and a steady-state predecessor is never signalled or revoked.

No mutex is held across arming or output.
`state/.claude-autoarm.lock` survives only as a micro-mutex serializing individual ledger writes.
A superseded owner goes completely silent.
Ownership is re-verified before every arm invocation, episode-state mutation, ledger write, and continuation.

#### Exit status as the commit point

The irrevocable commit point of a translation is the exit status, because the harness delivers the collected stderr banner only on exit 2.
An owned terminal commit therefore decides the exit:

- Markerless outcomes commit with the ledger write.
- The once-per-episode failure notice commits only when its marker is created after the winning failed write in the same critical section.

A generation whose required marker cannot be created is refused and exits 0 silently even after printing.
Its terminal ledger entry is superseded by a later firing, which retries the notice.

#### Why the claim boundaries exist

Without those boundaries, two failures occurred:

- A cycle that armed, delivered one rewake, and exited left both Stop participants deferring to its leftover lock indefinitely.
  On 2026-08-14 two tasks were in flight, a beacon was 40 minutes cold, and every turn was blind until an operator intervened.
- A hook that hung mid-arm kept a live pid on the lock, so the watcher was never auto-re-armed again (2026-08-26).

Two bounded residuals are accepted intent, each costing at most one extra continuation turn absorbed by the durable idempotent wake queue:

- An owner that dies between its owned terminal write and its own process exit.
- A hung old-build owner that resumes during the one legacy upgrade window.

A legacy build's lock-holding claim (recognizable by its `autoarm` role file) still defers or reclaims under the legacy abandonment proof.
A live identity-verified stuck legacy owner is retired via TERM before its lock is removed, and an unverified pid is never signalled.
An upgrade mid-session can therefore neither double-arm nor deadlock, and a failed reclaim re-blocks rather than allowing a blind stop.

#### Failure progression and block budget

Fresh `failed` and `failed-suppressed` outcomes enter or advance the failure progression instead of acting as unconditional recovery proof.
The auto-arm itself rechecks the healthy watcher predicate and retries a bounded number of times before reporting a genuine failure.

The foreground arm legitimately follows a healthy watcher until its next wake.
The hook therefore catches HUP, TERM, and INT from host timeout or teardown and commits the ordinary durable failed outcome and failure-notice marker before exiting 2 for a recovery turn.
Claude drops that exit 2 when it terminated the hook at the configured timeout itself, so a park that outlives the timeout ends without a rewake (`bin/fm-claude-stop-autoarm.sh` header).

The first fresh exhausted-failure epoch preserves its handoff without consuming a blocked-stop count.
Later fresh failed epochs advance the same monotonic progression instead of resetting it.
When none of those proofs appears, the guard re-blocks up to `FM_CLAUDE_TURNEND_BLOCK_BUDGET` times (default 3, below Claude's 8-block override).
In Claude mode, positive watcher recovery clears the block budget, failure notice, and attended alarm together under the existing budget lock before either hook reports ordinary recovery.

The block budget is charged by two rules:

- Each epoch identity is charged at most once per Stop under the budget lock.
- A re-block against an epoch the auto-arm did not advance past the previous re-block is charged as well.

That second rule still bounds an inert auto-arm when a hook never fires or fails before its generation claim and therefore leaves the ledger frozen at its last outcome.
Charging only epoch changes let the count freeze with that ledger, so the remaining inert-hook cases could re-block without limit and make the attended fail-open unreachable.
`budget_account_current_epoch` in `bin/fm-turnend-guard.sh` owns the rule.
A verified live foreign session-lock owner takes the earlier diagnostic safe exit instead and never reaches this budget path.
Whenever both coordination locks are needed, positive auto-arm recovery and the terminal check acquire the auto-arm owner lock before the budget lock.

#### Attended fail-open

The one loud attended fail-open is available only when all of these hold:

- The auto-arm has recorded an exhausted failure.
- Its one notice is already consumed.
- The block budget is exhausted.
- A final check finds neither a healthy watcher nor an automatic continuation.

After that alarm, the Stop auto-arm suppresses further exit-2 continuations until positive watcher recovery, so the final fail-open remains reachable.
The alarm cannot repeat during that failure episode, and a later unhealthy stop blocks again.
A positively verified healthy watcher clears the failure notice, alarm, and block budget for a future independent episode.
A Claude failure notice describes the automatic mechanism as broken and does not direct a routine manual background arm.

## Compatibility limits

- Child crewmate and scout worktrees are outside scope.
- A valid secondmate home is in scope.
  An idle secondmate endpoint with no Relay poll remains healthy because it has no supervision need.
- The blocking mechanism is limited to the primary Claude integration described above.
- Unreadable hook input remains fail-open.
- No harness adapter uses a shell ampersand to manufacture supervision.

## Regression coverage

`tests/fm-turnend-guard.test.sh` covers:

- The predicate.
- Main and secondmate primary scope.
- Child-worktree exclusion.
- `FM_HOME` and `FM_STATE_OVERRIDE` precedence.
- The live-lock and fresh-beacon guard predicate.
- The cooperative `--claude` open-generation claim wait.
- Monotonic failed-epoch progression.
- Bounded attended fail-open.
- The same bound against a ledger frozen by an inert auto-arm with and without a verified failure episode.
- Post-alarm continuation suppression.
- Positive recovery reset.
- Generation and legacy claim cases that must block or clear instead of allowing a blind stop.
- Away-mode daemon ownership between watcher cycles and over a watcher lock left behind by an exited watcher, plus its dead, pid-reused, absent, stale-beacon, and away-mode-off negatives.
- The away-mode beacon's poll-derived grace widening for a live daemon still mid-cycle and its bound against a dead daemon, a beacon older than that wider grace, and FM_POLL's inapplicability with away mode off.
- Missing-`jq` behavior.
- Malformed input.
- Exactly-one-path safety.

`tests/fm-turnend-foreign-owner-arm-fix.test.sh` runs the extracted isolated executable reproduction against real auto-arm and turn-end guard scripts.
It proves that a live foreign owner still prevents arming while repeated non-owner Stops receive a diagnostic and exit safely.

`tests/fm-guard-stale-banner.test.sh` covers the pull-guard predicate for the Claude auto-arm supervision model: the healthy fresh-beacon-without-a-watcher case, session-and-recovery-bound long-turn rewake tolerance, independently broken tolerance signals, open-claim negative control, stale-beacon alarm, and isolation from other models.

It also covers true-reason banner wording and reason-keyed episode dedup surviving a beacon mtime change.

[`verification/supervision.md`](verification/supervision.md#turn-end-guard) records the active empirical evidence, including the current Claude `asyncRewake` revalidation.
