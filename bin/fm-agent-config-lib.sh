# shellcheck shell=bash
# Shared config/agent.md reader.
# Usage: . bin/fm-agent-config-lib.sh; fm_agent_config_read <config-dir>
#
# config/agent.md's frontmatter is machine-read by three callers -
# bin/fm-session-start.sh's VAULT section, bin/fm-startup-memory-budget.sh's
# vault accounting, and bin/fm-bearings-snapshot.sh's vault_queue projection -
# so this is the one owner of that read rather than three copies of the same
# parse. The actual frontmatter scan lives in bin/fm-agent-config-read.py
# (python3, already used elsewhere in bin/, kept out of this bash file because
# robust quoted-value parsing is miserable in awk).
#
# fm_agent_config_read <config-dir> sets, always resetting every var first so
# a caller never sees a stale value from a prior read:
#   FM_AGENT_CONFIG_NAME         ""  when unset
#   FM_AGENT_CONFIG_USER_NAME    ""  when unset
#   FM_AGENT_CONFIG_ADDRESS      ""  when unset
#   FM_AGENT_CONFIG_VAULT_ROOT   ""  when unset (no vault configured)
#   FM_AGENT_CONFIG_VAULT_ENTRY  "Home.md" default
#   FM_AGENT_CONFIG_VAULT_QUEUE  "Open Work.md" default
# Returns 1 when <config-dir>/agent.md is absent, not a regular file, or a
# symlink - that absence is itself meaningful (AGENTS.md: load the onboarding
# skill), so callers branch on the return code rather than inferring it from
# empty fields. Returns 1 also when python3 is unavailable, so a caller always
# gets an explicit "could not read" signal rather than silently-empty fields.

FM_AGENT_CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fm_agent_config_read() {
  local config_dir=$1 path key value
  FM_AGENT_CONFIG_NAME=""
  FM_AGENT_CONFIG_USER_NAME=""
  FM_AGENT_CONFIG_ADDRESS=""
  FM_AGENT_CONFIG_VAULT_ROOT=""
  FM_AGENT_CONFIG_VAULT_ENTRY="Home.md"
  FM_AGENT_CONFIG_VAULT_QUEUE="Open Work.md"
  path="$config_dir/agent.md"
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  while IFS=$'\t' read -r key value; do
    case "$key" in
      name) FM_AGENT_CONFIG_NAME=$value ;;
      user_name) FM_AGENT_CONFIG_USER_NAME=$value ;;
      address) FM_AGENT_CONFIG_ADDRESS=$value ;;
      vault_root) FM_AGENT_CONFIG_VAULT_ROOT=$value ;;
      vault_entry) FM_AGENT_CONFIG_VAULT_ENTRY=$value ;;
      vault_queue) FM_AGENT_CONFIG_VAULT_QUEUE=$value ;;
    esac
  done < <(python3 "$FM_AGENT_CONFIG_LIB_DIR/fm-agent-config-read.py" "$path" 2>/dev/null)
  return 0
}
