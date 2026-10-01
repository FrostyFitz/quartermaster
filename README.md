<h1 align="center">firstmate</h1>
<p align="center">
  <a
    href="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue?style=flat-square"
    ><img
      alt="Platform"
      src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue?style=flat-square"
  /></a>
  <a href="https://x.com/kunchenguid"
    ><img
      alt="X"
      src="https://img.shields.io/badge/X-@kunchenguid-black?style=flat-square"
  /></a>
  <a href="https://discord.gg/Wsy2NpnZDu"
    ><img
      alt="Discord"
      src="https://img.shields.io/discord/1439901831038763092?style=flat-square&label=discord"
  /></a>
</p>

<h3 align="center">Talk to one agent. Ship with a crew.</h3>

<p align="center">
  <img alt="firstmate - talk to one agent, ship with a crew" src="assets/banner.png" width="100%" />
</p>

## What it is

You can run one coding agent easily.
But the moment you want three project tasks done in parallel - fixes, investigations, plans, audits - you become a tab-juggler: babysitting sessions, copy-pasting context between repos, forgetting which terminal had the failing test.

firstmate flips the model.
You talk to a single agent - the first mate - and it runs the crew for you: spawning autonomous agents in a visible session backend, giving each a clean git worktree, supervising them to completion, and handing you finished PRs, approved local merges, or standalone investigation reports.
For larger fleets, you can opt in to persistent secondmates: second mates that are still ordinary direct reports, but run from their own isolated firstmate homes on this machine.

firstmate is not a model, not a harness, not a skill, not an MCP server, and not a CLI.
firstmate is an agent distro for running a crew of agents.
An agent distro is a portable directory of instructions, skills, tooling, policies, and state conventions that turns a general-purpose agent into a specialized one.
There is no app to install: the cloned repo is the distro - `AGENTS.md`, bundled firstmate skills, and helper scripts that Claude Code can follow.
Launching Claude Code inside it for your primary session instantiates your first mate - and makes you the captain.

## Features

- **One liaison** - you talk only to the first mate; it dispatches, supervises, escalates only real decisions, and reports plain outcomes.
- **A visible crew** - every crewmate works in its own tmux window, or an experimental cmux workspace, that you can watch or type into; the first mate reconciles.
- **Disposable worktrees** - each task runs in a clean [treehouse](https://github.com/kunchenguid/treehouse) git worktree, so parallel work on one repo never collides.
- **Two task shapes** - ship tasks deliver authorized changes; scout tasks leave standalone investigation reports when the intake contract warrants separate research.
- **Explicit project modes** - each project ships via `no-mistakes`, `direct-PR`, or `local-only`, with an optional `+yolo` merge-autonomy flag, an optional `branch=<prefix>` override for the default `fm/` ship-branch prefix, and an optional `forge=gerrit` binding under which the worker publishes a Gerrit change instead of opening a pull request.
- **Optional secondmates** - opt in to persistent second mates that run from isolated firstmate homes with their own `FM_HOME`, state, projects, and session lock.
- **Event-driven, zero-token supervision** - a bash watcher sleeps on the fleet and wakes the first mate only when something needs you; the primary harness also gets a turn-end backstop that blocks or follows up on a blind stop when work is under way and supervision is not live.
- **Strict project boundary** - the first mate is read-only over your projects except for the narrow guarded and captain-approved operations authorized by [hard rule 1](AGENTS.md#1-identity-and-prime-directives), including fleet sync's guarded safe branch pruning; crewmates make every other project change behind the configured merge authority.
- **Restart-proof** - all state lives on disk and in the active session backend (tmux by hard default, cmux when selected or auto-detected); the next session reconciles after a restart, while ordinary supervision recovers confirmed-dead secondmate agents without waiting for one.

Full detail on every feature lives in [docs/architecture.md](docs/architecture.md).

## Quick Start

### Requirements

- [Claude Code](https://claude.com/product/claude-code), the primary agent harness.
- Git and the GitHub CLI, authenticated through `gh auth login`.
- The CLI and dependencies for your selected runtime backend; tmux is the reference default.

The first mate detects and offers to install supported missing tools after you approve.
Backend-specific setup is linked in [Documentation](#documentation).

### Install and launch

```sh
gh auth login
git clone https://github.com/kunchenguid/firstmate
cd firstmate
claude
```

AGENTS.md takes over from there.
Claude Code uses a tracked Stop hook for tokenless watcher re-arm and rewake, and has a verified turn-end guard path when launched with its documented setup.

### First run

On a fresh clone there is no `config/agent.md` yet, so the session-start digest reports `ONBOARDING REQUIRED` and the agent runs the onboarding skill: what to call it, what it should call you, a tone (with a sample line for each preset), two optional behavior toggles, and a memory vault - new or an existing one to import.
Onboarding writes `config/agent.md` and grants it access to the vault, then asks you to restart, since `CLAUDE.md`'s imports (including `config/agent.md`) only load at launch; once restarted, it greets you in character.
Re-running `/onboarding` later edits the existing config in place instead of starting over.

**Recommended plugins:** onboarding also offers to install [ponytail](https://github.com/DietrichGebert/ponytail) - a lazy-senior-dev coding discipline for Claude Code ("ship the simplest thing that actually works") - at user scope, so it covers both the first mate and every crewmate it spawns.
Install or update it yourself anytime with:

```sh
claude plugin marketplace add DietrichGebert/ponytail
claude plugin install ponytail@ponytail --scope user
```

### Talk to it

```sh
> ahoy! look at my github project xyz, then fix the flaky login test and add dark mode

# firstmate checks its toolchain (asking your consent before installing anything),
# clones the project under projects/ and spawns two isolated workers in the active backend.
# Minutes later:

  PR ready for review, captain: https://github.com/you/xyz/pull/42
  (fix flaky login test - risk: low - CI green)

> alright merge it
```

### More backends

Setup guides for tmux (the default) and the experimental cmux backend are linked in [Documentation](#documentation) below.

## How It Works

```
            you (the captain)
                  │  chat: requests, decisions, "merge it"
                  ▼
 ┌─────────────────────────────────────┐
 │ firstmate            (this repo)    │
 │ reads projects/ + firstmate routes  │
 │ writes guarded backlog/briefs/state │
 └──┬──────────────┬───────────────┬───┘
    │ backend sends / status files │
    ▼              ▼               ▼
 ┌────────┐   ┌────────┐      ┌────────┐
 │fm-task1│   │fm-task2│  ... │fm-taskN│   tmux windows, or cmux workspaces
 │crewmate│   │crewmate│      │crewmate│   one autonomous agent each
 └───┬────┘   └───┬────┘      └───┬────┘
     ▼            ▼               ▼
  treehouse worktree, or isolated secondmate home
     │
     ├─ ship: project mode ► PR/local merge ► teardown
     │
     └─ scout: report at data/<id>/report.md ► decision inventory ► relay findings ► teardown
```

You chat with the first mate.
It routes each request to a crewmate in its own session endpoint and git worktree, supervises the fleet with a zero-token event-driven watcher, and brings you finished PRs, approved local merges, or investigation reports.
Optional secondmates extend this to persistent second mates, and dispatch profiles let you steer which model and effort handles which task.

Full architecture - the supervision engine, worktree isolation, secondmates, dispatch profiles, project modes, fleet sync, and self-update - is in [docs/architecture.md](docs/architecture.md).

## Built-in skills

Firstmate ships these user-invocable built-in skills, invoked with the slash form shown here.

| Skill              | What it does                                                                                                                                  |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `/afk`             | Enter away-mode supervision: a [supervision host](docs/configuration.md#supervision-host-configsupervision-host) (on by default for Claude), or the daemon handles wakes while you step away; see the [away procedure](.agents/skills/afk/SKILL.md) for the posture and return contract |
| `/quiet`           | Keep routine wakes off main while staying and chatting; requested actions proceed now rather than waiting for your return. Where an [attended supervision host](docs/supervision-host.md#quiet-mode) already does this, it only says so; otherwise it starts the quiet daemon, which stays active through ordinary chat until `/quiet off` |
| `/ahoy`            | Recap visible session events since the prior real captain message plus visibly unanswered captain decisions, then guide the captain through any open decisions one at a time in agent-judged impact order; fall back to Bearings when invoked as the session's first real captain message |
| `/bearings`        | Generate a concise four-section chat digest from bounded fleet state, including registered remote-home ledgers and measured follow-up for owned contributions; use `/bearings file` to also replace today's dated report in `data/`, and add `include PRs` for live GitHub enrichment |
| `/updatefirstmate` | Guardedly update the running firstmate and its secondmates - fast-forward, or reconcile a redundant post-squash-merge divergence - then persist and restart every live mate successfully left on the target commit - including already-current homes - with an honest re-read nudge only when restart cannot be proven |
| `/stow`            | Sweep the session for uncaptured durable knowledge, persist the open work records this session knows are unfiled or now wrong, curate tiered startup memory with decay and cold archival, enforce each home's budget or surface the required decision, cascade to registered second mates, and report what is safe to reset |
| `/onboarding`      | First-run setup: the agent's name and persona, the two behavior toggles, and a memory vault (new or imported), written to `config/agent.md`; also runs automatically whenever the session-start digest reports `ONBOARDING REQUIRED`. Re-running it edits the existing config instead of starting over |

Bearings invocation examples:

- `/bearings` returns the fresh four-section digest in chat only.
- Owned-contribution follow-up comes from the cached coverage projection; `include PRs` remains the opt-in for repository-wide live PR enrichment.
- `/bearings include PRs` keeps chat-only mode and opts into live PR enrichment.
- `/bearings file` replaces today's `data/status-report-<YYYY-MM-DD>.md` from scratch and links it from the four-section chat digest.
- `/bearings file include PRs` combines the dated report with live PR enrichment.

Agent-only reference skills live under `.agents/skills/` and are loaded by firstmate at the trigger points named in [`AGENTS.md`](AGENTS.md).

### Two-tier skill layout

Firstmate's skills live in two separate places with different audiences:

- `.agents/skills/` - agent-loaded skills (this section's table, plus firstmate's agent-only reference skills). Every one of these assumes a live firstmate home and is meaningless, or actively misleading, installed anywhere else, so each carries `metadata.internal: true` in its frontmatter. That flag hides them from installer discovery (tools like the [skills.sh](https://skills.sh) `npx skills add` installer) without affecting how firstmate itself loads them - frontmatter metadata is inert to the agent's own skill loader.
- `skills/` - public, installer-facing skills meant to be installed standalone into any project, independent of firstmate.
  Each one is a self-contained skill with no dependency on firstmate's paths, tools, or vocabulary.
  Today that is `skills/stow`, a generic session-knowledge-sweep skill that routes findings by explicit instruction first, then existing local conventions, then a private `.stow-notes.md` fallback, and curates tiered entries through decay, local archival, and user-approved on-demand offload proposals.
  It intentionally shares no code with the firstmate-internal `.agents/skills/stow` it is named after, so the two can evolve independently.

## Documentation

- [docs/architecture.md](docs/architecture.md) - maintainer architecture for the crew, supervision, worktrees, secondmates, and project modes.
- [docs/configuration.md](docs/configuration.md) - environment variables, `FM_HOME`, runtime backend selection, trusted external process-event adapter setup, the files you set, and harness support.
- [docs/extension-bindings.md](docs/extension-bindings.md) - maintainer architecture for the narrow trusted external `process-event-adapter/1` package, binding, handshake, and evidence boundary.
- [docs/fleet-ledger.md](docs/fleet-ledger.md) - the opt-in activity ledger outside tools can read to follow a home's tasks, and its record contract.
- [docs/wedge-alarm.md](docs/wedge-alarm.md) - configure the active alert for an away-mode escalation delivery that gets stuck.
- [docs/tmux-backend.md](docs/tmux-backend.md) - current setup and limits for the tmux reference backend.
- [docs/cmux-backend.md](docs/cmux-backend.md) - current setup, socket security, and limits for the experimental cmux backend.
- [docs/verification/runtime-backends.md](docs/verification/runtime-backends.md) - active maintainer verification for runtime backend guarantees.
- [docs/gerrit-forge-integration.md](docs/gerrit-forge-integration.md) - maintainer architecture for the forge axis: why change-shaped review is not a forge variant, the mode/forge/shape composition test, and where responsibility for forge mechanics sits.
- [docs/gitlab-merge-watch.md](docs/gitlab-merge-watch.md) - maintainer verification for watching and merging GitLab merge requests on arbitrary instances.
- [docs/gerrit-change-watch.md](docs/gerrit-change-watch.md) - maintainer verification for watching Gerrit changes read-only, and why the merge path refuses one.
- [docs/turnend-guard.md](docs/turnend-guard.md) - the primary session's current "no turn ends blind" backstop, scope, loop safety, and compatibility limits.
- [docs/verification/supervision.md](docs/verification/supervision.md) - active maintainer verification for session-start, guard, continuity, and wedge integrations.
- [docs/supervision-protocols/](docs/supervision-protocols/) - rendered primary-harness watcher protocol for Claude, and the unknown-harness fallback.
- [docs/scripts.md](docs/scripts.md) - the `bin/` toolbelt reference.
- [docs/documentation-audiences.md](docs/documentation-audiences.md) - documentation audiences and the machine-checked placement boundary.
- [`AGENTS.md`](AGENTS.md) - the supervisor contract, role boundary, and routing index for conditional procedures.
- [CONTRIBUTING.md](CONTRIBUTING.md) - how to contribute, including the dev/test commands.

## Contributing

Contributions are welcome - see [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow, repo conventions, and how to run the tests.

## License

MIT - see [LICENSE](LICENSE).

## Star History

<a href="https://www.star-history.com/?repos=kunchenguid%2Ffirstmate&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=kunchenguid/firstmate&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=kunchenguid/firstmate&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=kunchenguid/firstmate&type=date&legend=top-left" />
 </picture>
</a>
