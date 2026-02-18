<div align="center">

<img src="assets/banner.svg" alt="OpenCode Orchestrator" width="900">

<p><strong>Route every task to a specialist instead of forcing one assistant to do everything.</strong></p>

![Views](https://hitscounter.dev/api/hit?url=https%3A%2F%2Fgithub.com%2F0xK3vin%2FOpenCodeOrchestrator&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=views&edge_flat=false)

<p>
  <a href="#quick-start">Install</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#workflow-examples">Workflows</a> •
  <a href="#model-configuration">Configure</a> •
  <a href="docs/agents.md">Docs</a>
</p>

</div>

---

### Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/0xK3vin/OpenCodeOrchestrator/main/install.sh | bash
```

Configure models (optional):

```bash
curl -fsSL https://raw.githubusercontent.com/0xK3vin/OpenCodeOrchestrator/main/configure.sh | bash
```

---

## The Problem

A single general-purpose agent can handle many tasks, but it rarely excels at all of them.

- Planning, implementation, debugging, operations, and review need different constraints.
- Those tasks also need different strengths and model behavior.
- One shared prompt and one shared permission profile creates inconsistent quality.
- That setup also increases operational risk.

## The Solution

OpenCode Orchestrator uses role-specialized agents with focused prompts, scoped permissions, and model tiering.

- The orchestrator routes work to the right specialist.
- It supports sequential and parallel delegation.
- It chains workflows automatically and keeps persistent context with megamemory.
- Free MCP servers add web search, GitHub code search, and project memory with no API keys.
- The result is better output quality, lower risk, and less prompt micromanagement.

## Architecture

<div align="center">
<img src="assets/architecture.svg" alt="Architecture" width="900">
</div>

## Key Benefits

- **Specialized agents**: One job per agent, with scoped permissions and model fit.
- **Intelligent routing**: The orchestrator selects the right path, such as `plan -> build` or `debug -> build`.
- **Review loop**: Non-trivial work goes through `review` until the quality gate passes.
- **Parallel delegation**: Independent tracks run together, then results are synthesized.
- **Free MCP servers**: `exa`, `grep_app`, and `megamemory` work out of the box with no API keys.
- **Persistent memory**: Megamemory keeps architecture and decisions across sessions.

## Workflow Examples

<div align="center">
<img src="assets/workflow.svg" alt="Workflow" width="900">
</div>

**Simple code change**

```text
You: "Add a loading spinner to the dashboard"
  -> orchestrator -> build -> done
```

**Complex feature (plan -> build -> review)**

```text
You: "Add real-time notifications with WebSocket support"
  -> orchestrator -> plan   (architecture spec)
                 -> build  (implements following plan)
                 -> review (verifies correctness)
                 -> PASS ✓
```

**Bug with unclear cause (debug -> build -> review)**

```text
You: "The checkout flow returns 500 errors intermittently"
  -> orchestrator -> debug  (traces execution, finds race condition)
                 -> build  (implements fix)
                 -> review -> PASS ✓
```

**Review loop (issues found)**

```text
  -> review finds missing null check
  -> build fixes it
  -> review again -> PASS ✓
```

**Codebase question**

```text
You: "How does the auth middleware work?"
  -> orchestrator -> explore (read-only analysis with file:line refs)
```

**Deployment**

```text
You: "Deploy to staging"
  -> orchestrator -> devops (verifies build, deploys, reports rollback procedure)
```

**Parallel research**

```text
You: "Compare our auth implementation against industry best practices"
  -> orchestrator -> explore (reads local auth code)   } parallel
                 -> explore (searches web via exa)     }
                 -> synthesizes findings into recommendation
```

## Megamemory Integration

`megamemory` is a persistent knowledge graph for your project: features, architecture, patterns, and decisions. It gives your agents memory across sessions.

**Workflow: understand -> work -> update**

- Session start: orchestrator loads project context with memory overview.
- Before tasks: orchestrator queries relevant architecture, patterns, and prior decisions.
- After tasks: orchestrator records new features, decisions, and patterns.

Custom commands included in this repo:

- `/user:bootstrap-memory` - index and bootstrap knowledge for a new project.
- `/user:save-memory` - record what was learned or changed in the current session.

Why it matters: you stop re-explaining your codebase every new session.

## Agent Reference

| Agent | Role | Model | Can Edit | Can Bash | Delegation |
|------|------|-------|----------|----------|------------|
| `orchestrator` | Primary router and synthesis layer | `anthropic/claude-opus-4-6` | No | Yes (deny list) | Specialists |
| `plan` | Architecture/spec planning | `anthropic/claude-opus-4-6` | No | No | No |
| `build` | Implementation and tests | `openai/gpt-5.3-codex` | Yes | Yes | No |
| `debug` | Root-cause analysis | `anthropic/claude-opus-4-6` | No | Yes (deny list) | No |
| `devops` | Git, CI/CD, deployments | `anthropic/claude-sonnet-4-20250514` | Yes | Yes (deny list) | No |
| `explore` | Read-only codebase analysis | `anthropic/claude-sonnet-4-20250514` | No | No | No |
| `review` | Validation and quality gate | `anthropic/claude-opus-4-6` | No | Yes (deny list) | No |

## Model Configuration

Use the interactive configurator:

```bash
curl -fsSL https://raw.githubusercontent.com/0xK3vin/OpenCodeOrchestrator/main/configure.sh | bash
```

Presets available:

- `Recommended`: Opus reasoning, Sonnet execution, Codex coding (default profile).
- `All Claude`: Opus reasoning and Sonnet for execution/coding.
- `All OpenAI`: o3 reasoning, GPT-4.1 execution, Codex coding.
- `All Google`: Gemini Pro reasoning/coding with Gemini Flash execution.
- `Budget`: Sonnet everywhere.
- `Custom`: choose models interactively.

Custom mode supports both:

- Per-tier model selection (Reasoning, Execution, Coding).
- Per-agent model selection across all 7 agents.

## File Structure

```text
OpenCodeOrchestrator/
├── README.md
├── install.sh
├── configure.sh
├── LICENSE
├── assets/
│   ├── banner.svg
│   ├── architecture.svg
│   └── workflow.svg
├── config/
│   ├── opencode.json
│   ├── AGENTS.md
│   └── package.json
├── agents/
│   ├── orchestrator.md
│   ├── build.md
│   ├── plan.md
│   ├── debug.md
│   ├── devops.md
│   ├── explore.md
│   └── review.md
├── commands/
│   ├── bootstrap-memory.md
│   └── save-memory.md
└── docs/
    ├── agents.md
    ├── configuration.md
    └── workflows.md
```

Installed layout in `~/.config/opencode/`:

- `opencode.json`, `AGENTS.md`, `package.json`
- `agents/*.md`
- `commands/*.md`
- `docs/*.md`

## Installation

Updating is safe by default when you re-run the installer:

- Existing agent `model:` values are preserved automatically.
- If prompt body text was customized, you are prompted per conflict (overwrite, skip, or view diff).
- In non-interactive environments (for example `curl ... | bash` in CI), conflicts default to upstream prompt bodies while preserving `model:` values and keeping backups.

Use `--force` for a clean overwrite of all installed files:

```bash
curl -fsSL https://raw.githubusercontent.com/0xK3vin/OpenCodeOrchestrator/main/install.sh | bash -s -- --force
```

Install from a local clone (uses local files, including unpushed changes):

```bash
git clone https://github.com/0xK3vin/OpenCodeOrchestrator.git
cd OpenCodeOrchestrator
./install.sh --local
```

<details>
<summary>Manual Install</summary>

1. Clone this repo.
2. Copy `config/opencode.json` to `~/.config/opencode/opencode.json`.
3. Copy `config/AGENTS.md` to `~/.config/opencode/AGENTS.md`.
4. Copy all `agents/*.md` to `~/.config/opencode/agents/`.
5. Copy all `commands/*.md` to `~/.config/opencode/commands/`.
6. Optionally copy `docs/*.md` to `~/.config/opencode/docs/`.
7. Copy `config/package.json` to `~/.config/opencode/package.json` and run `npm install`.

</details>

Post-install:

- Edit `~/.config/opencode/opencode.json` with your real API keys.
- Optionally run the interactive configurator from [Model Configuration](#model-configuration).
- Configure/enable MCP servers you want to use.
- Restart OpenCode.

## Configuration

For full configuration details, see `docs/configuration.md`. It covers default launch agent behavior, model/permission tuning, agent set changes, and MCP setup.

## Design Decisions

- **Model tiering**: Opus for deep reasoning/review, Sonnet for operational/read-only tasks, and Codex for implementation.
- **DRY tool docs**: Tool behavior lives in global skill/tool prompts, not inside every agent prompt.
- **Bash deny list over allowlist**: Broad utility with guardrails against destructive commands.
- **Orchestrator cannot edit**: Enforces delegation discipline and clear ownership boundaries.
- **Review loop quality gate**: Non-trivial changes are verified before completion.
- **Parallel dispatch**: Independent workstreams run simultaneously, then the orchestrator synthesizes results.

## MCP Servers

- `megamemory`: persistent project knowledge graph.
- `exa`: free web search, code docs lookup, and URL crawling via Exa AI. No API key required.
- `grep_app`: free GitHub code search across millions of public repos via grep.app. No API key required.

## License

MIT. See `LICENSE`.
