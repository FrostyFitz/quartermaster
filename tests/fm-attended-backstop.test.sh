#!/usr/bin/env bash
# tests/fm-attended-backstop.test.sh - the tier B outside-the-Claude-process
# backstop: the no-op matrix, repair-only re-arm, the alert floor's once-per-
# episode/re-fires-on-a-new-episode contract, and a healthy cycle's zero
# writes. The pane-nudge tier (2c) is not implemented, so it is not tested here.
set -u

# shellcheck source=tests/wake-helpers.sh
. "$(dirname "${BASH_SOURCE[0]}")/wake-helpers.sh"

BACKSTOP="$ROOT/bin/fm-attended-backstop.sh"
TMP_ROOT=$(fm_test_tmproot fm-attended-backstop)

# Pin the autoarm model (the Claude Stop-hook model this backstop targets): a
# fresh beacon alone is healthy with no live watcher process, so these cases
# need no real watcher process to prove re-arm "worked" - a touched beacon is
# enough, matching the real re-arm's own effect under this model.
make_case() {  # <name> -> echoes home dir with state/ and config/
  local name=$1 home
  home="$TMP_ROOT/$name/home"
  mkdir -p "$home/state" "$home/config"
  printf '%s\n' "$home"
}

enable_backstop() {  # <home>
  : > "$1/config/attended-backstop"
}

write_in_flight_task() {  # <home>
  fm_write_meta "$1/state/task.meta" "window=firstmate:fm-task" "kind=ship"
}

# count_rearm <file> -> number of invocation lines (0 if absent)
count_rearm() {
  [ -e "$1" ] && wc -l < "$1" | tr -d '[:space:]' || printf '0'
}

# A re-arm stub: records one invocation line, and (if FM_TEST_REARM_FIX_HOME is
# set) touches that home's beacon, modeling a re-arm that actually produced a
# fresh beacon under the autoarm model.
write_rearm_stub() {  # <path>
  cat > "$1" <<'SH'
#!/usr/bin/env bash
echo invoked >> "${FM_TEST_REARM_COUNTER:?}"
if [ -n "${FM_TEST_REARM_FIX_HOME:-}" ]; then
  mkdir -p "$FM_TEST_REARM_FIX_HOME/state"
  touch "$FM_TEST_REARM_FIX_HOME/state/.last-watcher-beat"
fi
SH
  chmod +x "$1"
}

run_backstop() {  # <home> [extra env assignments as NAME=val ...]
  local home=$1
  shift
  env FM_HOME="$home" FM_ROOT_OVERRIDE="$home" FM_STATE_OVERRIDE="$home/state" \
    FM_CONFIG_OVERRIDE="$home/config" FM_SUPERVISION_MODEL=autoarm \
    FM_WEDGE_ALARM_CHANNEL=osascript \
    "$@" "$BACKSTOP"
}

# wait_for_lines <file> <n>: bounded poll for a backgrounded re-arm's counter to
# reach <n> lines (the re-arm runs detached, so its write can trail this
# script's own exit by a beat).
wait_for_lines() {
  local file=$1 want=$2 i=0
  while [ "$i" -lt 100 ]; do
    [ "$(count_rearm "$file")" = "$want" ] && return 0
    sleep 0.05
    i=$((i + 1))
  done
  return 1
}

# --- no-op matrix ------------------------------------------------------------

test_noop_backstop_not_enabled() {
  local home
  home=$(make_case not-enabled)
  write_in_flight_task "$home"
  run_backstop "$home"
  assert_absent "$home/state/.attended-backstop-episode" "a disabled backstop must not open an episode"
  pass "fm-attended-backstop: no-op when config/attended-backstop is absent"
}

test_noop_away_mode() {
  local home
  home=$(make_case away-mode)
  enable_backstop "$home"
  write_in_flight_task "$home"
  printf 'away\n%s\n' "$(date +%s)" > "$home/state/.afk"
  run_backstop "$home"
  assert_absent "$home/state/.attended-backstop-episode" "away mode must gate the backstop off"
  pass "fm-attended-backstop: no-op while state/.afk exists"
}

test_noop_afk_contract() {
  local home
  home=$(make_case afk-contract)
  enable_backstop "$home"
  write_in_flight_task "$home"
  : > "$home/state/.afk-contract"
  run_backstop "$home"
  assert_absent "$home/state/.attended-backstop-episode" "an afk-contract record must gate the backstop off"
  pass "fm-attended-backstop: no-op while state/.afk-contract exists"
}

test_noop_nothing_in_flight() {
  local home marker
  home=$(make_case nothing-in-flight)
  enable_backstop "$home"
  marker="$home/state/.attended-backstop-episode"
  printf 'leftover-episode\n' > "$marker"
  run_backstop "$home"
  assert_absent "$marker" "a home needing no supervision must clear any leftover episode marker"
  pass "fm-attended-backstop: no-op (and clears a leftover marker) when nothing is in flight"
}

test_noop_watcher_healthy() {
  local home marker
  home=$(make_case watcher-healthy)
  enable_backstop "$home"
  write_in_flight_task "$home"
  touch "$home/state/.last-watcher-beat"
  marker="$home/state/.attended-backstop-episode"
  printf 'leftover-episode\n' > "$marker"
  run_backstop "$home"
  assert_absent "$marker" "a healthy watcher must clear any leftover episode marker"
  pass "fm-attended-backstop: no-op (and clears a leftover marker) when the watcher is healthy"
}

test_noop_under_threshold() {
  local home counter rearm
  home=$(make_case under-threshold)
  enable_backstop "$home"
  write_in_flight_task "$home"
  counter="$TMP_ROOT/under-threshold/counter"
  rearm="$TMP_ROOT/under-threshold/rearm.sh"
  write_rearm_stub "$rearm"
  run_backstop "$home" env FM_ATTENDED_BACKSTOP_THRESHOLD_SECS=999999 \
    FM_ATTENDED_BACKSTOP_REARM_CMD="$rearm" FM_TEST_REARM_COUNTER="$counter"
  assert_absent "$home/state/.attended-backstop-episode" "unhealthy-under-threshold must not open an episode"
  [ "$(count_rearm "$counter")" = 0 ] || fail "unhealthy-under-threshold must not invoke the re-arm"
  pass "fm-attended-backstop: no-op when unhealthy but under the threshold"
}

# --- repair-only --------------------------------------------------------------

test_repair_only_rearm_once_then_recovery_is_silent() {
  local home counter rearm
  home=$(make_case repair-only)
  enable_backstop "$home"
  write_in_flight_task "$home"
  counter="$TMP_ROOT/repair-only/counter"
  rearm="$TMP_ROOT/repair-only/rearm.sh"
  write_rearm_stub "$rearm"

  run_backstop "$home" env FM_ATTENDED_BACKSTOP_THRESHOLD_SECS=0 \
    FM_ATTENDED_BACKSTOP_REARM_CMD="$rearm" FM_TEST_REARM_COUNTER="$counter" \
    FM_TEST_REARM_FIX_HOME="$home"
  wait_for_lines "$counter" 1 || fail "re-arm was not invoked on the first unhealthy tick"
  assert_present "$home/state/.attended-backstop-episode" "the first unhealthy tick must open an episode"

  # Second tick: the stub's fix already landed (fresh beacon), so this tick
  # must observe recovery and do nothing further.
  run_backstop "$home" env FM_ATTENDED_BACKSTOP_THRESHOLD_SECS=0 \
    FM_ATTENDED_BACKSTOP_REARM_CMD="$rearm" FM_TEST_REARM_COUNTER="$counter" \
    FM_TEST_REARM_FIX_HOME="$home"
  sleep 0.2
  [ "$(count_rearm "$counter")" = 1 ] || fail "re-arm was invoked again after recovery (expected exactly once)"
  assert_absent "$home/state/.attended-backstop-episode" "recovery must clear the episode marker"
  pass "fm-attended-backstop: repair-only re-arm fires exactly once; recovery is silent and clears the episode"
}

# --- alert floor ---------------------------------------------------------

test_alert_fires_once_per_episode_and_again_on_a_new_episode() {
  local home counter rearm alert_log
  home=$(make_case alert-floor)
  enable_backstop "$home"
  write_in_flight_task "$home"
  counter="$TMP_ROOT/alert-floor/counter"
  rearm="$TMP_ROOT/alert-floor/rearm.sh"
  alert_log="$TMP_ROOT/alert-floor/alert.log"
  write_rearm_stub "$rearm"

  # Tick 1: unhealthy past threshold, no fix - the episode stays open.
  FM_WEDGE_ALARM_LOG="$alert_log" run_backstop "$home" \
    env FM_ATTENDED_BACKSTOP_THRESHOLD_SECS=0 \
    FM_ATTENDED_BACKSTOP_REARM_CMD="$rearm" FM_TEST_REARM_COUNTER="$counter" \
    FM_WEDGE_ALARM_LOG="$alert_log"
  wait_for_lines "$counter" 1 || fail "re-arm was not invoked on the first tick"
  [ "$(wc -l < "$alert_log" | tr -d '[:space:]')" = 1 ] \
    || fail "the alert floor did not fire exactly once on the first tick: $(cat "$alert_log")"
  grep -F 'attended supervision stopped responding' "$alert_log" >/dev/null \
    || fail "the alert summary did not carry the attended-specific wording: $(cat "$alert_log")"

  # Tick 2: same unhandled episode (still no beacon) - must stay silent.
  FM_WEDGE_ALARM_LOG="$alert_log" run_backstop "$home" \
    env FM_ATTENDED_BACKSTOP_THRESHOLD_SECS=0 \
    FM_ATTENDED_BACKSTOP_REARM_CMD="$rearm" FM_TEST_REARM_COUNTER="$counter" \
    FM_WEDGE_ALARM_LOG="$alert_log"
  sleep 0.2
  [ "$(count_rearm "$counter")" = 1 ] || fail "re-arm fired again within the same unhandled episode"
  [ "$(wc -l < "$alert_log" | tr -d '[:space:]')" = 1 ] \
    || fail "the alert floor re-fired within the same unhandled episode: $(cat "$alert_log")"

  # Recovery: touch the beacon directly, then let it go stale again - a new
  # episode under the same reason must re-claim and re-alert.
  touch "$home/state/.last-watcher-beat"
  FM_WEDGE_ALARM_LOG="$alert_log" run_backstop "$home" \
    env FM_ATTENDED_BACKSTOP_THRESHOLD_SECS=0 \
    FM_ATTENDED_BACKSTOP_REARM_CMD="$rearm" FM_TEST_REARM_COUNTER="$counter" \
    FM_WEDGE_ALARM_LOG="$alert_log"
  assert_absent "$home/state/.attended-backstop-episode" "the recovery tick must clear the episode marker"
  rm -f "$home/state/.last-watcher-beat"
  FM_WEDGE_ALARM_LOG="$alert_log" run_backstop "$home" \
    env FM_ATTENDED_BACKSTOP_THRESHOLD_SECS=0 \
    FM_ATTENDED_BACKSTOP_REARM_CMD="$rearm" FM_TEST_REARM_COUNTER="$counter" \
    FM_WEDGE_ALARM_LOG="$alert_log"
  wait_for_lines "$counter" 2 || fail "re-arm did not fire again on the new episode"
  [ "$(wc -l < "$alert_log" | tr -d '[:space:]')" = 2 ] \
    || fail "the alert floor did not re-fire on a new episode: $(cat "$alert_log")"
  pass "fm-attended-backstop: the alert floor fires once per episode and again on a new episode"
}

# --- healthy cycle writes nothing --------------------------------------------

test_healthy_cycle_writes_nothing() {
  local home before after
  home=$(make_case healthy-no-writes)
  enable_backstop "$home"
  write_in_flight_task "$home"
  touch "$home/state/.last-watcher-beat"
  before=$(find "$home/state" -maxdepth 1 -mindepth 1 -printf '%p %T@\n' | sort)
  run_backstop "$home"
  after=$(find "$home/state" -maxdepth 1 -mindepth 1 -printf '%p %T@\n' | sort)
  [ "$after" = "$before" ] || fail "a healthy cycle wrote to state/"$'\n'"before: $before"$'\n'"after: $after"
  pass "fm-attended-backstop: a healthy cycle writes nothing to state/"
}

test_noop_backstop_not_enabled
test_noop_away_mode
test_noop_afk_contract
test_noop_nothing_in_flight
test_noop_watcher_healthy
test_noop_under_threshold
test_repair_only_rearm_once_then_recovery_is_silent
test_alert_fires_once_per_episode_and_again_on_a_new_episode
test_healthy_cycle_writes_nothing
