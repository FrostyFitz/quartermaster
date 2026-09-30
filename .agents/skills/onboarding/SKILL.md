---
name: onboarding
description: >-
  First-run setup: the agent's name and persona, the two behavior toggles, and a memory vault, written to config/agent.md.
  Use when the user asks to set up, configure, or onboard this agent, on an explicit "/onboarding" or "run onboarding" request, or when the session-start digest reports ONBOARDING REQUIRED because config/agent.md is missing.
  Re-running this skill edits the existing config/agent.md instead of starting over.
user-invocable: true
metadata:
  internal: true
---

# Onboarding

Set up `config/agent.md` - the name, address, tone, toggles, and vault this agent runs with - then point it at a memory vault, new or existing.
If `config/agent.md` already exists, treat this as an edit pass: read it first, ask only what the user wants to change, and preserve every field they don't touch.

## 1. Prereqs

Run [`bin/fm-bootstrap.sh`](../../../bin/fm-bootstrap.sh); it is the single owner of the toolchain check (gh auth, tmux or cmux, treehouse, no-mistakes, the axi tools).
Do not reimplement its checks here.
For any printed diagnostic line, follow [`bootstrap-diagnostics`](../bootstrap-diagnostics/SKILL.md) and [`session-start-recovery`](../session-start-recovery/SKILL.md): detect, get the user's consent, then install - never install anything they haven't approved in this session.
If this session is running on native Windows rather than WSL2, stop here and tell the user to re-run onboarding from inside WSL2; do not continue the rest of this flow on native Windows.

## 2. Questions, one at a time

Ask each question on its own, wait for the answer, then move to the next.
Never ask two of these in the same message.

1. What should the agent be called?
2. What should the agent call the user?
3. Which tone? Read the three preset files and show each one's sample line before asking the user to pick:
   [`templates/persona/tones/professional.md`](../../../templates/persona/tones/professional.md),
   [`templates/persona/tones/friendly.md`](../../../templates/persona/tones/friendly.md),
   [`templates/persona/tones/salty-butler.md`](../../../templates/persona/tones/salty-butler.md).
   A fourth option, custom, skips the preset; ask the user to describe the persona in their own words instead, and store that verbatim.
4. Offer both toggles, with the exact text from
   [`templates/persona/toggles/never_suggest_stopping.md`](../../../templates/persona/toggles/never_suggest_stopping.md) and
   [`templates/persona/toggles/one_question_then_stop.md`](../../../templates/persona/toggles/one_question_then_stop.md), and ask which (if either) to turn on. Both default off.
5. New vault or import an existing one?

## 3. New vault

Ask for the vault's path, the user's role, and their current projects.

1. Copy [`templates/vault/`](../../../templates/vault/) to that path, preserving its structure exactly.
2. Seed `Home.md`'s `[FILL: ...]` sections from the answers: who they are, one line per project under Projects, and anything they said about how they like to work.
3. For each project named, copy `Projects/_Project Template/` to `Projects/<Project Name>/`, rename the file to `<Project Name>.md`, and fill its frontmatter and placeholders from what the user said.
4. Delete the now-unneeded `Projects/_Project Template/` copy in the new vault; the template stays only in this repo's `templates/vault/`.

## 4. Import an existing vault

Ask for the vault's path, then inspect it read-only to propose a mapping:

- an entry note candidate (a root-level note that looks like a map of the vault - frequent internal links, a "map" or "index" heading, or the most-linked-to root note)
- an open-work queue candidate (a note that reads as a running task or backlog list)
- a daily-notes folder, and whether its layout is flat (`YYYY-MM-DD.md` directly inside it) or monthly (dated subfolders)
- a daily template candidate, if one exists

State the proposed mapping plainly and get the user's confirmation or correction before writing anything.
Generate only what's genuinely missing (for example a daily template, if none exists, modeled on [`templates/vault/Daily/Daily Template.md`](../../../templates/vault/Daily/Daily%20Template.md)), placed alongside the existing notes.
Never rewrite, move, or reformat a note the import found; existing content is untouched.

## 5. Write config/agent.md

Start from [`templates/agent.md`](../../../templates/agent.md) (or the existing `config/agent.md` on a re-run) and fill it in:

- `name`, `address`, `tone`, and `vault.root` from the answers above.
- `vault.entry`, `vault.queue`, `vault.daily_dir`, `vault.daily_template`, and `vault.daily_layout` from the new-vault defaults or the confirmed import mapping.
- `toggles.never_suggest_stopping` and `toggles.one_question_then_stop` from the answers.
- The Persona body: the chosen tone preset's locked text copied in verbatim (the preset file's text above its `---` sample divider, never the sample line itself), or the user's own words verbatim for `custom`, followed by the text of each toggle the user turned on.
- The Personal rules body: left as `[FILL: personal standing rules]` unless the user volunteered standing rules during onboarding, in which case record those instead.

Write the result to `config/agent.md` (create the `config/` directory if needed; it is already gitignored).

## 6. Grant vault access

Add the vault root to `.claude/settings.local.json`: `permissions.additionalDirectories` gets the vault root path as a normal absolute path, and `permissions.allow` gets a `Read` and an `Edit` rule scoped to that path. Permission rules need an extra leading slash for an absolute path - a single leading slash resolves relative to the settings file - so the rule is the vault root with `//` in front (e.g. a vault root of `/home/fitz/Porygon Vault` becomes `Read(//home/fitz/Porygon Vault/**)`, `Edit(//home/fitz/Porygon Vault/**)`); only the permission rule gets the extra slash, not `additionalDirectories` or `vault.root` in `config/agent.md`.
Read the file first if it exists and merge these into its existing JSON; do not clobber any other keys or rules already there.
If the file doesn't exist yet, create it with just these permissions.

## 7. Finish

Tell the user to restart the session - `CLAUDE.md`'s imports, including `config/agent.md`, only load at launch - then, once restarted, greet them in character using the persona and address just configured.
