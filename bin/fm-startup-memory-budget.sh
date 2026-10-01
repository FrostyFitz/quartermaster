#!/usr/bin/env bash
# Read and account for the local startup-memory budget.
# Usage:
#   fm-startup-memory-budget.sh read
#   fm-startup-memory-budget.sh report
#
# `read` prints the one validated effective budget from
# config/startup-memory-budget.  `report` prints the stable local estimate for
# the memory vault (config/agent.md's vault entry note and open-work queue)
# and data/learnings.md together - the two sources bin/fm-session-start.sh's
# digest actually inlines every session (captain.md and captain-shared.md
# stopped being injected when the vault took over user-preference memory;
# see AGENTS.md's Memory section).
# Bootstrap owns default materialization; this command never creates or repairs
# configuration, so an absent, malformed, symlinked, hardlinked, or otherwise
# unsafe value is a concrete error rather than an inferred default.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"

# shellcheck source=bin/fm-startup-memory-budget-lib.sh
. "$SCRIPT_DIR/fm-startup-memory-budget-lib.sh"
# shellcheck source=bin/fm-agent-config-lib.sh
. "$SCRIPT_DIR/fm-agent-config-lib.sh"

usage() {
  sed -n '2,11{s/^# \{0,1\}//;p;}' "$0"
}

print_error() {
  printf 'startup-memory-budget: %s\n' "$1" >&2
}

read_budget() {
  if ! fm_startup_memory_budget_read "$CONFIG" >/dev/null; then
    print_error "invalid config/$FM_STARTUP_MEMORY_BUDGET_FILE - $FM_STARTUP_MEMORY_BUDGET_ERROR"
    return 1
  fi
  printf '%s\n' "$FM_STARTUP_MEMORY_BUDGET_VALUE"
}

report() {
  local budget bytes tokens presence total=0 role=primary vault_root=""
  local vault_file vault_label vault_rel

  if ! budget=$(read_budget); then
    return 2
  fi

  if [ -e "$FM_HOME/.fm-secondmate-home" ] || [ -L "$FM_HOME/.fm-secondmate-home" ]; then
    role=secondmate
  fi

  printf 'estimator=ceil(UTF-8 bytes / 3) conservative-local-estimate\n'
  printf 'role=%s\n' "$role"
  printf 'effective_budget_tokens=%s\n' "$budget"

  if fm_agent_config_read "$CONFIG"; then
    vault_root=$FM_AGENT_CONFIG_VAULT_ROOT
  fi
  if [ -n "$vault_root" ]; then
    for vault_file in "entry:$FM_AGENT_CONFIG_VAULT_ENTRY" "queue:$FM_AGENT_CONFIG_VAULT_QUEUE"; do
      vault_label=${vault_file%%:*}
      vault_rel=${vault_file#*:}
      if ! fm_startup_memory_measure_file "$vault_root/$vault_rel" >/dev/null; then
        print_error "$FM_STARTUP_MEMORY_BUDGET_ERROR"
        return 2
      fi
      bytes=$FM_STARTUP_MEMORY_MEASURE_BYTES
      tokens=$FM_STARTUP_MEMORY_MEASURE_TOKENS
      presence=$FM_STARTUP_MEMORY_MEASURE_PRESENCE
      total=$((total + tokens))
      printf 'file=vault/%s(%s) bytes=%s estimated_tokens=%s status=%s\n' \
        "$vault_label" "$vault_rel" "$bytes" "$tokens" "$presence"
    done
  else
    printf 'vault=unconfigured (config/agent.md missing or has no vault.root)\n'
  fi

  if ! fm_startup_memory_measure_file "$DATA/learnings.md" >/dev/null; then
    print_error "$FM_STARTUP_MEMORY_BUDGET_ERROR"
    return 2
  fi
  bytes=$FM_STARTUP_MEMORY_MEASURE_BYTES
  tokens=$FM_STARTUP_MEMORY_MEASURE_TOKENS
  presence=$FM_STARTUP_MEMORY_MEASURE_PRESENCE
  total=$((total + tokens))
  printf 'file=data/learnings.md bytes=%s estimated_tokens=%s status=%s\n' \
    "$bytes" "$tokens" "$presence"

  printf 'total_estimated_tokens=%s\n' "$total"
  if fm_startup_memory_decimal_le "$total" "$budget"; then
    printf 'budget_status=within-budget\n'
  else
    printf 'budget_status=over-budget\n'
  fi
}

case "${1:-}" in
  read)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    read_budget
    ;;
  report)
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    report
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
