---
# config/agent.md - written by the onboarding skill, edited directly to change
# a setting later. Re-running onboarding edits this file in place rather than
# starting over. Frontmatter is machine-read; everything below the closing
# --- is free persona prose.

# The agent's name, e.g. Porygon.
name: ""

# What the agent calls the user, e.g. "sir or boss".
address: ""

# The user's actual name, e.g. "Fitz". Used to mark queue items in the vault's
# open-work queue as the user's own (a line starting "<user_name>:" routes to
# Captain's Call in /bearings); distinct from `address`, which is what the
# agent calls the user in conversation.
user_name: ""

# One of: professional | friendly | salty-butler | custom.
# professional/friendly/salty-butler pull their text from
# templates/persona/tones/<tone>.md at onboarding time and copy it into the
# Persona section below. custom skips the preset and stores the user's own
# words in Persona directly.
tone: professional

# Per-user behavior toggles, both default false. A toggle set true has its
# text (templates/persona/toggles/<name>.md) copied into the Persona section
# below; false means the text is omitted entirely, not included-and-ignored.
toggles:
  never_suggest_stopping: false
  one_question_then_stop: false

# The memory vault this agent reads and writes every session.
vault:
  # Absolute path to the vault root.
  root: ""
  # Entry note read at session start: who the user is, current projects, and
  # the vault map. Relative to vault root.
  entry: "Home.md"
  # The single open-work queue note. Relative to vault root.
  queue: "Open Work.md"
  # Folder holding daily notes. Relative to vault root.
  daily_dir: "Daily"
  # Template new daily notes are created from. Relative to vault root.
  daily_template: "Daily/Daily Template.md"
  # Daily note layout: "flat" (all notes directly in daily_dir) or "monthly"
  # (a subfolder per month inside daily_dir).
  daily_layout: flat
---

# Persona

<!-- The chosen tone preset's text (copied in verbatim), or the user's own
words verbatim when tone is custom. This is what makes the agent sound like
itself instead of a generic assistant. -->

[FILL: persona description]

# Personal rules

<!-- The user's own standing rules, in their own words: things this agent
should always or never do for them specifically, beyond the universal core
rules in AGENTS.md. -->

[FILL: personal standing rules]
