#!/usr/bin/env bash
# fm-attended-backstop.sh - outside-the-Claude-process backstop for the
# ATTENDED posture (no state/.afk or state/.afk-contract). Tier B: detect,
# repair (re-arm), and alert. No pane nudge - see data/attended-backstop/report.md
# section 2 for the full tiered design and why this stays outside the Claude
# process tree entirely.
#
# The Claude Stop hook's own continuity path (bin/fm-claude-stop-autoarm.sh)
# can die with the rest of its process tree (a timed-out hook Claude itself
# kills, SIGKILL, a closed pane) with nothing left alive to retry, because
# retrying depends on the next Stop event and there is no next Stop event
# without a new prompt. This script is meant to run from an independent
# scheduler (a systemd user timer; see systemd/firstmate-attended-backstop@.timer)
# so it survives exactly that failure mode.
#
# Usage: fm-attended-backstop.sh
#   Run once per poll; always exits 0 (a timer script, never a gate). Opt-in:
#   a home runs this only while config/attended-backstop exists (presence-only,
#   mirroring config/supervision-host's gate; docs/configuration.md owns it).
#   No-op whenever any of these holds:
#     - config/attended-backstop is absent.
#     - state/.afk or state/.afk-contract exists (away/quiet mode already owns
#       continuity; never double-handle).
#     - supervision is not needed (bin/fm-supervision-lib.sh).
#     - the watcher is healthy (bin/fm-wake-lib.sh's model-aware
#       fm_watcher_supervision_verdict).
#     - supervision is unhealthy but under FM_ATTENDED_BACKSTOP_THRESHOLD_SECS.
#     - the current down-episode was already handled (state/.attended-backstop-episode).
#   Otherwise: starts/attaches the watcher in the background
#   (bin/fm-watch-arm.sh) and fires the wedge-alarm notifier
#   (bin/fm-supervise-daemon.sh's wedge_alarm_notify), unconditionally and
#   regardless of whether the re-arm succeeds - the alert is the one step a
#   dead process can never prevent. Never touches state/.lock: a dead
#   session-lock owner is bin/fm-lock.sh's job, a different and bigger
#   authority than this script's.
#   Env knobs:
#     FM_ATTENDED_BACKSTOP_THRESHOLD_SECS  seconds supervision must have been
#                                          unhealthy before this backstop acts
#                                          (default 1800 - 2x the arm layer's
#                                          own stall bound, so ordinary
#                                          self-healing has already had every
#                                          chance to work)
#     FM_ATTENDED_BACKSTOP_REARM_CMD       override the re-arm command (tests)
#     FM_GUARD_GRACE                       beacon freshness grace, shared with
#                                          fm-guard.sh/fm-watch-arm.sh (default 300)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
WATCH="$SCRIPT_DIR/fm-watch.sh"
GRACE=${FM_GUARD_GRACE:-300}
THRESHOLD=${FM_ATTENDED_BACKSTOP_THRESHOLD_SECS:-1800}
case "$THRESHOLD" in ''|*[!0-9]*) THRESHOLD=1800 ;; esac
EPISODE_MARKER="$STATE/.attended-backstop-episode"

# Opt-in gate and away/quiet exits, checked before sourcing anything, so a home
# that never enabled this backstop (or is already covered by away/quiet mode)
# never even touches the supervision libraries.
[ -e "$CONFIG/attended-backstop" ] || exit 0
[ -e "$STATE/.afk" ] && exit 0
[ -e "$STATE/.afk-contract" ] && exit 0

# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-supervision-lib.sh
. "$SCRIPT_DIR/fm-supervision-lib.sh"

# Record whether the caller already set the wedge-alarm notifier seam BEFORE
# sourcing the daemon below, so the restore after sourcing (see there) knows
# whether to leave it alone.
_fm_backstop_wedge_exec_was_set=${FM_WEDGE_ALARM_EXEC+1}
# shellcheck source=bin/fm-supervise-daemon.sh
. "$SCRIPT_DIR/fm-supervise-daemon.sh"
# The daemon's own library-mode guard at its foot defaults FM_WEDGE_ALARM_EXEC
# to "discard" whenever sourcing it is not the daemon's own execution - which
# is always true here, since THIS script is what was executed, not the
# daemon. That guard exists so no TEST can fire a real notification by
# accident, but it cannot tell a sourcing test apart from this script's own
# genuine production run. Restore production's real channels unless a test
# deliberately set the seam itself (tests/wake-helpers.sh's recorder, or a
# literal override), exactly as it would for the daemon's own tests.
[ -n "$_fm_backstop_wedge_exec_was_set" ] || unset FM_WEDGE_ALARM_EXEC

fm_attended_backstop_clear_episode() {
  rm -f "$EPISODE_MARKER" 2>/dev/null || true
}

# One line = the current down-episode's key (the failing condition - same
# pattern as bin/fm-guard.sh's stale-banner marker, new file). No locking: this
# script is invoked by a single serial timer for one home, never concurrently.
fm_attended_backstop_claim_episode() {
  local key=$1 seen
  seen=$(cat "$EPISODE_MARKER" 2>/dev/null || true)
  seen=${seen%$'\n'}
  [ "$seen" = "$key" ] && return 1
  printf '%s\n' "$key" > "$EPISODE_MARKER" 2>/dev/null || true
  return 0
}

# The beacon's age, or - if no beacon ever existed - the oldest in-flight
# task's age, so a home that has never once had a watcher still measures how
# long something has waited unsupervised (report section 2a).
fm_attended_backstop_down_age() {
  local state=$1 oldest age meta
  if [ -e "$state/.last-watcher-beat" ]; then
    fm_path_age "$state/.last-watcher-beat"
    return
  fi
  oldest=
  for meta in "$state"/*.meta; do
    [ -e "$meta" ] || continue
    age=$(fm_path_age "$meta")
    if [ -z "$oldest" ] || [ "$age" -gt "$oldest" ]; then
      oldest=$age
    fi
  done
  printf '%s\n' "${oldest:-999999}"
}

fm_supervision_status "$STATE" "$GRACE"
if [ "$FM_SUP_NEEDED" = false ]; then
  fm_attended_backstop_clear_episode
  exit 0
fi

fm_watcher_supervision_verdict "$STATE" "$WATCH" "$GRACE" "$FM_HOME" "$FM_ROOT"
if [ "$FM_WATCHER_VERDICT_OK" = true ]; then
  fm_attended_backstop_clear_episode
  exit 0
fi

down_age=$(fm_attended_backstop_down_age "$STATE")
case "$down_age" in ''|*[!0-9]*) down_age=999999 ;; esac
[ "$down_age" -ge "$THRESHOLD" ] || exit 0

fm_attended_backstop_claim_episode "$FM_WATCHER_VERDICT_REASON" || exit 0

# --- repair: re-arm. Cheapest possible action: restores the watcher so FUTURE
# events are not silently dropped; does not by itself wake an idle primary.
# This script is a short-lived timer run, so it backgrounds the arm exactly as
# every other arm owner must (bin/fm-watch-arm.sh's own header): started/
# attached, the arm stays live for the watcher's whole cycle, which would
# otherwise block this script until the next wake.
rearm_cmd=${FM_ATTENDED_BACKSTOP_REARM_CMD:-$SCRIPT_DIR/fm-watch-arm.sh}
rearm_log="$STATE/.attended-backstop-arm.log"
nohup setsid "$rearm_cmd" >>"$rearm_log" 2>&1 < /dev/null &
disown 2>/dev/null || true

# --- alert: the unconditional floor. Always attempted regardless of whether
# repair succeeds, with attended-specific wording so it reads differently from
# an away-mode wedge (nobody declared themselves away; something just died).
summary=$(printf 'attended supervision stopped responding (%s, down %ss) - the watcher was re-armed; see state/.attended-backstop-episode' \
  "$FM_WATCHER_VERDICT_REASON" "$down_age")
wedge_alarm_notify "$summary" "$EPISODE_MARKER"

exit 0
