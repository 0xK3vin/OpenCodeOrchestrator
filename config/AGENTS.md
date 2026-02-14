# Agent Instructions

## Orchestration Model

- `orchestrator` is the primary coordinator.
- `plan`, `build`, `debug`, `devops`, `explore`, and `review` are specialist agents.
- Tool-specific behavior is managed by global tool/skill prompts; do not duplicate tool tutorials in agent prompts.

## Routing Guide

- Use `plan` for architecture, scoping, and implementation plans.
- Use `build` for coding, refactors, and tests.
- Use `debug` for root-cause analysis and execution tracing.
- Use `devops` for git, Docker, CI/CD, deployments, and shell-heavy work.
- Use `explore` for read-only codebase questions.
- Use `review` after `build` to verify quality before reporting completion.

## Delegation Rules

- **Default pipeline: `plan → build → review`.** All code-changing requests follow this unless a documented shortcut exception is met.
- The orchestrator must state which step is being skipped and why when deviating from the full pipeline.
- Shortcuts: skip `plan` only for single-file, <20-line, unambiguous changes. Skip `review` only for purely cosmetic changes (typos, comments, formatting).
- For unclear failures, run `debug` first, then feed findings into the standard pipeline.
- Use `devops` whenever operational or deployment risk is involved.
- Use `explore` for quick discovery and factual codebase answers.
- If `review` finds critical or warning issues, loop back to `build` with findings, then `review` again. Repeat until PASS.

## Execution Patterns

- **Default:** `plan → build → review` (all code changes unless shortcut exception applies).
- **Debug-first:** `debug → plan → build → review` (unclear failures).
- **Review loop:** `build → review → build → review` (repeat until PASS on issues found).
- **Shortcut (justified):** `build → review` (single-file, <20 lines, unambiguous) — must state justification.
- **Cosmetic only:** `build` alone (typos, comments, formatting only) — must state justification.
- **Parallel context:** Multiple `explore` or `debug` tasks with no dependency between them → fire simultaneously, merge results (e.g., gathering context from three modules before `plan`).
- **Parallel pipelines:** Independent code changes → run full `plan → build → review` pipelines simultaneously when the workstreams share no files, types, or interfaces.
- **Parallel + sequential:** Parallel context gathering → feed merged results into a single `plan` → sequential `build → review`.
- Avoid recursive delegation from specialists; keep `orchestrator` as the control plane.

## Memory Workflow

- Start sessions with project memory overview.
- Query memory before major tasks.
- Record decisions and new architecture after task completion.

## Output Expectations

- Keep responses concise and decision-oriented.
- Include exact file references when summarizing changes.
- Flag risks, assumptions, and unresolved questions clearly.

## Project Knowledge Graph

You have access to a project knowledge graph via the `megamemory` MCP server and skill tool. This is your persistent memory of the codebase — concepts, architecture, decisions, and how things connect. You write it. You read it. The graph is your memory across sessions.

**Workflow: understand → work → update**

1. **Session start:** Call `megamemory` tool with action `overview` (or `megamemory:list_roots` directly) to orient yourself.
2. **Before each task:** Call `megamemory` tool with action `query` (or `megamemory:understand` directly) to load relevant context.
3. **After each task:** Call `megamemory` tool with action `record` to create/update/link concepts for what you built.

Be specific in summaries: include parameter names, defaults, file locations, and rationale. Keep concepts max 3 levels deep.
