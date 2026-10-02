#!/usr/bin/env bash
# Regression tests for the pinned shared no-mistakes gate action.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ACTION_REF=32d396ac0f29135daf7fcb9964aba9d5f4e796d6
TMP_ROOT=$(fm_test_tmproot fm-no-mistakes-required)
VERIFY="$TMP_ROOT/verify.py"
OLD_SHA=1111111111111111111111111111111111111111
NEW_SHA=2222222222222222222222222222222222222222
SIGNATURE='Updates from [git push no-mistakes](https://github.com/kunchenguid/no-mistakes)'
COMPLETED_STEPS='[{"step":"review","status":"completed"},{"step":"test","status":"completed"},{"step":"document","status":"completed"}]'

fetch_shared_verifier() {
  command -v curl >/dev/null 2>&1 || fail "curl is required to exercise the pinned shared action"
  command -v python3 >/dev/null 2>&1 || fail "python3 is required to exercise the pinned shared action"
  curl --fail --silent --show-error --location \
    "https://raw.githubusercontent.com/kunchenguid/no-mistakes/${ACTION_REF}/.github/actions/require-no-mistakes/verify.py" \
    > "$VERIFY" || fail "could not fetch the pinned shared action verifier"
  [ -s "$VERIFY" ] || fail "the pinned shared action verifier was empty"
}

run_verifier() {
  local body=$1 head=$2
  PR_BODY="$body" PR_HEAD_SHA="$head" PR_AUTHOR=regression PR_NUMBER=3006 \
    python3 "$VERIFY" 2>&1
}

test_matching_head_and_completed_steps_pass() {
  local body output rc
  body="$SIGNATURE
<!-- no-mistakes-pipeline-attestation:v1 {\"head_sha\":\"$NEW_SHA\",\"steps\":$COMPLETED_STEPS} -->"
  rc=0
  output=$(run_verifier "$body" "$NEW_SHA") || rc=$?
  expect_code 0 "$rc" "shared action rejected an attestation bound to the current PR head"
  assert_contains "$output" "Found structurally compliant pipeline step attestation." \
    "shared action did not report the matching attestation as compliant"
  pass "shared action accepts a matching head_sha with completed required steps"
}

test_mismatched_head_fails_with_both_shas() {
  local body output rc
  body="$SIGNATURE
<!-- no-mistakes-pipeline-attestation:v1 {\"head_sha\":\"$OLD_SHA\",\"steps\":$COMPLETED_STEPS} -->"
  rc=0
  output=$(run_verifier "$body" "$NEW_SHA") || rc=$?
  [ "$rc" -ne 0 ] || fail "shared action accepted an attestation from a different PR head"
  assert_contains "$output" "$OLD_SHA" \
    "mismatched-head failure did not name the attestation head SHA"
  assert_contains "$output" "$NEW_SHA" \
    "mismatched-head failure did not name the actual PR head SHA"
  pass "shared action rejects a mismatched head_sha and names both SHAs"
}

test_missing_head_fails() {
  local body output rc
  body="$SIGNATURE
<!-- no-mistakes-pipeline-attestation:v1 {\"steps\":$COMPLETED_STEPS} -->"
  rc=0
  output=$(run_verifier "$body" "$NEW_SHA") || rc=$?
  [ "$rc" -ne 0 ] || fail "shared action accepted an attestation without head_sha"
  assert_contains "$output" "structured pipeline step attestation" \
    "missing-head failure did not explain that the attestation is invalid"
  pass "shared action rejects an attestation with no head_sha"
}

# --- bin/fm-wait-for-pr-attestation.py (the local #12 fix) ---
#
# On `synchronize`/`reopened`, the workflow gives the PR body a short bounded
# window to catch up to the new head's attestation before the shared verifier
# above judges it (regression origin: #12, a stale-head race on every push
# after the first). These tests drive the script against a throwaway local
# HTTP server standing in for the GitHub API, so they exercise the exact code
# the workflow runs rather than a reimplementation of it.
WAIT_SCRIPT="$ROOT/bin/fm-wait-for-pr-attestation.py"

fm_attestation_body() {
  local head=$1
  printf 'Updates from [git push no-mistakes](https://github.com/kunchenguid/no-mistakes)\n<!-- no-mistakes-pipeline-attestation:v1 {"head_sha":"%s","steps":[]} -->' "$head"
}

# fm_start_pr_body_stub <bodies_file> <port_file> <log_file>: launches a
# stdlib-only HTTP server serving $bodies_file's lines (one per request, the
# last repeating past the end) as {"body": ...} JSON, writes its chosen port
# to $port_file once bound, and echoes its PID.
fm_start_pr_body_stub() {
  local bodies_file=$1 port_file=$2 log_file=$3 script_dir script
  script_dir=$(fm_test_tmproot fm-nm-wait-stub)
  script="$script_dir/server.py"
  cat > "$script" <<'PY'
import http.server
import json
import sys

bodies_file, port_file = sys.argv[1], sys.argv[2]
with open(bodies_file, encoding="utf-8") as handle:
    bodies = [line.rstrip("\n") for line in handle]

class Handler(http.server.BaseHTTPRequestHandler):
    count = 0

    def do_GET(self):
        idx = min(Handler.count, len(bodies) - 1)
        Handler.count += 1
        payload = json.dumps({"body": bodies[idx]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass

srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w", encoding="utf-8") as handle:
    handle.write(str(srv.server_port))
srv.serve_forever()
PY
  python3 "$script" "$bodies_file" "$port_file" > "$log_file" 2>&1 &
  echo $!
}

# fm_wait_for_stub_port <port_file>: polls for the stub server's announced
# port (written once its socket is bound) and prints it, empty on timeout.
fm_wait_for_stub_port() {
  local port_file=$1
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if [ -s "$port_file" ]; then
      cat "$port_file"
      return 0
    fi
    sleep 0.1
  done
}

test_wait_script_returns_once_attestation_catches_up() {
  local tmp bodies_file port_file log_file pid port out rc start end elapsed
  tmp=$(fm_test_tmproot fm-nm-wait-catchup)
  bodies_file="$tmp/bodies.txt"
  port_file="$tmp/port"
  log_file="$tmp/server.log"
  {
    fm_attestation_body "$OLD_SHA"
    fm_attestation_body "$OLD_SHA"
    fm_attestation_body "$NEW_SHA"
  } > "$bodies_file"
  pid=$(fm_start_pr_body_stub "$bodies_file" "$port_file" "$log_file")
  port=$(fm_wait_for_stub_port "$port_file")
  [ -n "$port" ] || { kill "$pid" 2>/dev/null; fail "stub server never reported a port"$'\n'"$(cat "$log_file" 2>/dev/null)"; }

  rc=0
  start=$(date +%s)
  out=$(GITHUB_TOKEN=x REPO=owner/repo PR_NUMBER=7 HEAD_SHA="$NEW_SHA" \
    GITHUB_API_URL="http://127.0.0.1:$port" \
    NM_WAIT_MAX_SECONDS=5 NM_WAIT_POLL_SECONDS=0.2 \
    python3 "$WAIT_SCRIPT" 2>&1) || rc=$?
  end=$(date +%s)
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null

  expect_code 0 "$rc" "wait script failed instead of waiting out a transient stale attestation"
  assert_contains "$out" "already names the current head $NEW_SHA" \
    "wait script did not report catching up to the new head"
  elapsed=$((end - start))
  [ "$elapsed" -lt 3 ] || fail "wait script did not return promptly once the body caught up (took ${elapsed}s)"
  pass "wait script returns as soon as the live body names the current head"
}

test_wait_script_times_out_without_failing() {
  local tmp bodies_file port_file log_file pid port out rc
  tmp=$(fm_test_tmproot fm-nm-wait-timeout)
  bodies_file="$tmp/bodies.txt"
  port_file="$tmp/port"
  log_file="$tmp/server.log"
  fm_attestation_body "$OLD_SHA" > "$bodies_file"
  pid=$(fm_start_pr_body_stub "$bodies_file" "$port_file" "$log_file")
  port=$(fm_wait_for_stub_port "$port_file")
  [ -n "$port" ] || { kill "$pid" 2>/dev/null; fail "stub server never reported a port"$'\n'"$(cat "$log_file" 2>/dev/null)"; }

  rc=0
  out=$(GITHUB_TOKEN=x REPO=owner/repo PR_NUMBER=7 HEAD_SHA="$NEW_SHA" \
    GITHUB_API_URL="http://127.0.0.1:$port" \
    NM_WAIT_MAX_SECONDS=0.6 NM_WAIT_POLL_SECONDS=0.2 \
    python3 "$WAIT_SCRIPT" 2>&1) || rc=$?
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null

  expect_code 0 "$rc" "wait script must never fail the job itself on a genuinely stale attestation - the gate action owns that failure"
  assert_contains "$out" "did not catch up to $NEW_SHA within the wait window" \
    "wait script did not report the expired wait window"
  pass "wait script gives up quietly on a genuinely stale attestation and lets the gate judge it"
}

fetch_shared_verifier
test_matching_head_and_completed_steps_pass
test_mismatched_head_fails_with_both_shas
test_missing_head_fails
test_wait_script_returns_once_attestation_catches_up
test_wait_script_times_out_without_failing
