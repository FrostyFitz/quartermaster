<!-- Boot imports: AGENTS.md (orchestrator contract), templates/core-rules.md
     (universal memory rules), config/agent.md (this agent's name, persona,
     and vault), and team/rules.md (optional tracked team rules). config/agent.md
     is gitignored and written by the onboarding skill
     (.agents/skills/onboarding/SKILL.md). team/rules.md does not exist in this
     repo; a private team copy adds it to roll out team-wide instructions - see
     README.md's "Rolling out to a team". A missing import is silently
     skipped, so this loads fine before onboarding has run and in repos with no
     team copy. Edit AGENTS.md or templates/core-rules.md directly; edit
     config/agent.md directly to change a setting, or re-run onboarding. -->
@AGENTS.md
@templates/core-rules.md
@config/agent.md
@team/rules.md
