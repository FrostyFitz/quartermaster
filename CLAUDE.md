<!-- Boot imports: AGENTS.md (orchestrator contract), templates/core-rules.md
     (universal memory rules), and config/agent.md (this agent's name, persona,
     and vault). config/agent.md is gitignored and written by the onboarding
     skill (.agents/skills/onboarding/SKILL.md) - a missing import is silently
     skipped, so this loads fine before onboarding has run. Edit AGENTS.md or
     templates/core-rules.md directly; edit config/agent.md directly to change
     a setting, or re-run onboarding. -->
@AGENTS.md
@templates/core-rules.md
@config/agent.md
