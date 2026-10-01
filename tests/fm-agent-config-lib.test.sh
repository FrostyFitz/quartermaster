#!/usr/bin/env bash
# Behavior tests for bin/fm-agent-config-lib.sh and its bin/fm-agent-config-read.py
# frontmatter scanner - the one config/agent.md reader shared by
# bin/fm-session-start.sh's VAULT section, bin/fm-startup-memory-budget.sh's
# vault accounting, and bin/fm-bearings-snapshot.sh's vault_queue projection.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-agent-config-lib.sh
. "$ROOT/bin/fm-agent-config-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-agent-config-lib)

assert_field() {  # <actual> <expected> <field-name>
  [ "$1" = "$2" ] || fail "$3 expected '$2', got '$1'"
}

test_parses_full_frontmatter() {
  local config
  config="$TMP_ROOT/full/config"
  mkdir -p "$config"
  cat > "$config/agent.md" <<'EOF'
---
name: "Porygon"
address: "sir or boss"
tone: salty-butler
user_name: "Fitz"
toggles:
  never_suggest_stopping: true
  one_question_then_stop: true
vault:
  root: "/home/fitz/Porygon Vault"
  entry: "VAULT-INDEX.md"
  queue: "Active Priorities.md"
  daily_dir: "01 - Daily Notes"
---

# Persona
EOF
  fm_agent_config_read "$config" || fail "read failed for a complete config"
  assert_field "$FM_AGENT_CONFIG_NAME" "Porygon" "name"
  assert_field "$FM_AGENT_CONFIG_USER_NAME" "Fitz" "user_name"
  assert_field "$FM_AGENT_CONFIG_ADDRESS" "sir or boss" "address"
  assert_field "$FM_AGENT_CONFIG_VAULT_ROOT" "/home/fitz/Porygon Vault" "vault_root"
  assert_field "$FM_AGENT_CONFIG_VAULT_ENTRY" "VAULT-INDEX.md" "vault_entry"
  assert_field "$FM_AGENT_CONFIG_VAULT_QUEUE" "Active Priorities.md" "vault_queue"
  pass "fm_agent_config_read parses a complete frontmatter, including a quoted vault root with spaces"
}

test_parses_the_shipped_template() {
  # templates/agent.md is at templates/agent.md, not templates/config/agent.md,
  # so point the reader straight at the template file via a throwaway config dir.
  local config
  config="$TMP_ROOT/template/config"
  mkdir -p "$config"
  cp "$ROOT/templates/agent.md" "$config/agent.md"
  fm_agent_config_read "$config" || fail "read failed for the shipped template"
  assert_field "$FM_AGENT_CONFIG_NAME" "" "name (unfilled template)"
  assert_field "$FM_AGENT_CONFIG_VAULT_ENTRY" "Home.md" "vault_entry (template default)"
  assert_field "$FM_AGENT_CONFIG_VAULT_QUEUE" "Open Work.md" "vault_queue (template default)"
  pass "fm_agent_config_read parses the shipped templates/agent.md without error"
}

test_defaults_entry_and_queue_when_vault_omits_them() {
  local config
  config="$TMP_ROOT/defaults/config"
  mkdir -p "$config"
  cat > "$config/agent.md" <<'EOF'
---
name: "Tester"
vault:
  root: "/vault"
---
EOF
  fm_agent_config_read "$config" || fail "read failed"
  assert_field "$FM_AGENT_CONFIG_VAULT_ROOT" "/vault" "vault_root"
  assert_field "$FM_AGENT_CONFIG_VAULT_ENTRY" "Home.md" "vault_entry default"
  assert_field "$FM_AGENT_CONFIG_VAULT_QUEUE" "Open Work.md" "vault_queue default"
  pass "fm_agent_config_read defaults entry and queue when the vault block omits them"
}

test_single_quoted_and_unquoted_scalars() {
  local config
  config="$TMP_ROOT/quoting/config"
  mkdir -p "$config"
  cat > "$config/agent.md" <<'EOF'
---
name: 'Porygon'
address: sir or boss
vault:
  root: /home/x/vault
---
EOF
  fm_agent_config_read "$config" || fail "read failed"
  assert_field "$FM_AGENT_CONFIG_NAME" "Porygon" "single-quoted name"
  assert_field "$FM_AGENT_CONFIG_ADDRESS" "sir or boss" "unquoted address with spaces"
  assert_field "$FM_AGENT_CONFIG_VAULT_ROOT" "/home/x/vault" "unquoted vault root"
  pass "fm_agent_config_read accepts single-quoted and bare unquoted scalars"
}

test_stale_fields_reset_between_reads() {
  local config
  config="$TMP_ROOT/reset/config"
  mkdir -p "$config"
  cat > "$config/agent.md" <<'EOF'
---
name: "First"
vault:
  root: "/first-vault"
  entry: "First.md"
---
EOF
  fm_agent_config_read "$config" || fail "first read failed"
  assert_field "$FM_AGENT_CONFIG_NAME" "First" "first read name"

  cat > "$config/agent.md" <<'EOF'
---
vault:
  root: "/second-vault"
---
EOF
  fm_agent_config_read "$config" || fail "second read failed"
  assert_field "$FM_AGENT_CONFIG_NAME" "" "second read must not carry over the first name"
  assert_field "$FM_AGENT_CONFIG_VAULT_ROOT" "/second-vault" "second read vault_root"
  assert_field "$FM_AGENT_CONFIG_VAULT_ENTRY" "Home.md" "second read must not carry over the first entry"
  pass "fm_agent_config_read resets every field on each call instead of leaking a prior read"
}

test_absent_file_returns_1_with_reset_fields() {
  local config
  config="$TMP_ROOT/absent/config"
  mkdir -p "$config"
  FM_AGENT_CONFIG_NAME=stale
  if fm_agent_config_read "$config"; then
    fail "read unexpectedly succeeded for an absent agent.md"
  fi
  assert_field "$FM_AGENT_CONFIG_NAME" "" "name after a failed read"
  assert_field "$FM_AGENT_CONFIG_VAULT_ROOT" "" "vault_root after a failed read"
  pass "fm_agent_config_read returns 1 and resets every field when config/agent.md is absent"
}

test_symlinked_file_is_refused() {
  local config outside
  config="$TMP_ROOT/symlink/config"
  mkdir -p "$config"
  outside="$TMP_ROOT/symlink/outside-agent.md"
  printf '%s\n' '---' 'name: "Outside"' '---' > "$outside"
  ln -s "$outside" "$config/agent.md"
  if fm_agent_config_read "$config"; then
    fail "read unexpectedly succeeded for a symlinked agent.md"
  fi
  pass "fm_agent_config_read refuses a symlinked config/agent.md"
}

test_missing_frontmatter_delimiters_yields_empty_fields() {
  local config
  config="$TMP_ROOT/no-frontmatter/config"
  mkdir -p "$config"
  printf '%s\n' '# Just a Markdown file' 'name: "not frontmatter"' > "$config/agent.md"
  fm_agent_config_read "$config" || fail "read failed for a present but frontmatter-less file"
  assert_field "$FM_AGENT_CONFIG_NAME" "" "name must stay empty with no --- delimiters"
  assert_field "$FM_AGENT_CONFIG_VAULT_ENTRY" "Home.md" "vault_entry default still applies"
  pass "fm_agent_config_read returns 0 with empty fields when the file has no frontmatter block"
}

test_parses_full_frontmatter
test_parses_the_shipped_template
test_defaults_entry_and_queue_when_vault_omits_them
test_single_quoted_and_unquoted_scalars
test_stale_fields_reset_between_reads
test_absent_file_returns_1_with_reset_fields
test_symlinked_file_is_refused
test_missing_frontmatter_delimiters_yields_empty_fields

echo '# all fm-agent-config-lib tests passed'
