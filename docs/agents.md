# Agents Reference

Detailed breakdown of each agent's purpose, model, permissions, and prompt behavior.

---

## orchestrator

**File**: `agents/orchestrator.md`
**Model**: `anthropic/claude-opus-4-6`
**Mode**: `primary` (cannot be delegated to, always the entry point)

### Role

Central coordinator. Interprets user intent, picks the right specialist, constructs self-contained delegation prompts, and synthesizes results back to the user. Does not implement, debug, or deploy anything itself.

### Permissions

| Permission | Value |
|-----------|-------|
| read | allow |
| grep | allow |
| glob | allow |
| edit | **deny** |
| write | **deny** |
| bash | allow (deny: rm, rmdir, mkfs, dd, shutdown, reboot, halt, poweroff) |
| task | allow: plan, build, debug, devops, explore, review |

### Key Behaviors

- **Delegation prompt construction**: Every delegation includes context, goal, scope boundaries, constraints, expected output, and completion criteria. Specialists have no memory of prior conversation — the orchestrator is their only source of context.
- **Routing explanation**: Before each delegation, tells the user what it's doing and why in one sentence.
- **Ambiguity handling**: If the request is ambiguous and routing depends on clarification, asks one question. If routing is clear regardless, proceeds and states the assumption.
- **Result synthesis**: Summarizes specialist output concisely. For sequential chains (plan -> build -> review), gives one unified summary, not separate reports per agent.
- **Mandatory pipeline**: All code-changing requests follow `plan → build → review` by default. Steps may only be skipped when documented shortcut criteria are met (single-file <20-line for skipping plan; cosmetic-only for skipping review), and the orchestrator must state the justification to the user. Review loops (`build → review → build`) continue until review passes.
- **Memory protocol**: Queries megamemory at session start and before major tasks. Records architecture decisions after significant work.

---

## plan

**File**: `agents/plan.md`
**Model**: `anthropic/claude-opus-4-6`
**Mode**: `all` (Tab-switchable + delegatable)

### Role

Produces implementation plans concrete enough that the `build` agent can execute them without clarifying questions. Reads the codebase to ground plans in reality.

### Permissions

| Permission | Value |
|-----------|-------|
| read | allow |
| grep | allow |
| glob | allow |
| edit | **deny** |
| write | **deny** |
| bash | **deny** |
| task | **deny** |

### Key Behaviors

- **Granularity**: Plans include exact file paths, function/method signatures, pseudocode for complex logic, expected inputs/outputs/error conditions, and migration steps.
- **Trade-off presentation**: When multiple approaches exist, presents 2-3 options with pros/cons and advocates for one.
- **Scope pushback**: If a request is too large for one pass, proposes phased delivery with milestones and identifies the minimum viable first phase.
- **Decision surfacing**: Calls out design choices that could go either way and have significant downstream impact, rather than choosing silently.

### Output Format

1. Goal and assumptions
2. Affected areas (files, modules, interfaces)
3. Decisions needed (if any)
4. Step-by-step implementation plan with file paths and signatures
5. Risks and edge cases
6. Verification checklist

---

## build

**File**: `agents/build.md`
**Model**: `openai/gpt-5.3-codex`
**Mode**: `all` (Tab-switchable + delegatable)

### Role

Implements code changes, refactors, and tests. Follows plans from the `plan` agent or works from direct user requests. Delivers working, validated changes.

### Permissions

| Permission | Value |
|-----------|-------|
| read | allow |
| grep | allow |
| glob | allow |
| edit | **allow** |
| write | **allow** |
| bash | **allow** |
| task | **deny** |

### Key Behaviors

- **Plan-following protocol**: If a plan was provided, follows it step-by-step. On concrete blockers, stops and reports — does not attempt workarounds.
- **Scope discipline**: Executes only what the orchestrator assigned. May fix breakages caused by its own changes, but stops and reports blockers for anything outside scope (pre-existing bugs, unrelated failures, issues in out-of-scope files). Does not attempt workarounds.
- **Incremental verification**: Runs build/typecheck/lint after each logical unit of change, not just at the end.
- **Diff discipline**: Keeps changes scoped to the request. No "while I'm here" refactors or unrelated improvements.
- **Code style matching**: Follows existing codebase conventions, naming, and formatting. Doesn't introduce new patterns unless the task requires it.
- **Blocker reporting**: If blocked, stops immediately, delivers what's done, describes the blocker with file:line details, and waits for orchestrator to decide the next step.
- **Ambiguity threshold**: If requirements are ambiguous and materially impact design, stops and asks rather than guessing.

### Delivery Format

- List of files changed with descriptions
- Validation results (tests, types, lint, build)
- Follow-up items if work is deferred

---

## debug

**File**: `agents/debug.md`
**Model**: `anthropic/claude-opus-4-6`
**Mode**: `all` (Tab-switchable + delegatable)

### Role

Root-cause analysis and execution tracing. Finds why things break with evidence, not guesses. Diagnostic only — does not modify files.

### Permissions

| Permission | Value |
|-----------|-------|
| read | allow |
| grep | allow |
| glob | allow |
| edit | **deny** |
| write | **deny** |
| bash | allow (deny: rm, rmdir, mkfs, dd, shutdown, reboot, halt, poweroff) |
| task | **deny** |

### Key Behaviors

- **Execution timeline**: Presents findings as a traced timeline from entry point through to failure, with concrete values at each step.
- **Evidence grading**: Distinguishes between "confirmed" (direct proof), "likely" (strong inference), and "possible" (hypothesis). Never presents hypotheses as conclusions.
- **Insufficient evidence handling**: When static analysis can't confirm the cause, suggests specific logging or instrumentation that would confirm it.
- **Multiple candidates**: When several root causes are plausible, ranks them by likelihood with reasoning.

### Output Format

1. What is failing (precise symptoms)
2. Root cause (with evidence grade)
3. Execution trace (entry -> failure timeline)
4. What triggers it (reproduction conditions)
5. Recommended fixes (options with trade-offs)

---

## devops

**File**: `agents/devops.md`
**Model**: `anthropic/claude-sonnet-4-20250514`
**Mode**: `all` (Tab-switchable + delegatable)

### Role

Git workflows, Docker, CI/CD, deployments, environment configuration, and shell-driven automation. The operational specialist.

### Permissions

| Permission | Value |
|-----------|-------|
| read | allow |
| grep | allow |
| glob | allow |
| edit | **allow** |
| write | **allow** |
| bash | allow (deny: rm, rmdir, mkfs, dd, shutdown, reboot, halt, poweroff) |
| task | **deny** |

### Key Behaviors

- **State first**: Always inspects current state (git status, docker ps, env vars) before making changes.
- **Destructive operation protocol**: For irreversible actions (force push, drop database, delete resources), explicitly states what will be destroyed, whether it's recoverable, and the rollback procedure — then asks for confirmation.
- **Git workflow**: Prefers conventional commits. Won't amend pushed commits. Won't force push main/master without explicit confirmation.
- **Deployment safety**: States rollback procedure before deploying. Verifies build/artifact before deployment. Confirms target environment for production.
- **Secret awareness**: Never commits, logs, or displays secrets. Warns immediately if secrets are detected in staged files.
- **Scope discipline**: Executes only the operations assigned. Stops and reports failures instead of retrying with alternative approaches or attempting workarounds.

### Delivery Format

- What was done, what changed, what remains
- Key command outputs
- Operational risks or follow-up checks

---

## explore

**File**: `agents/explore.md`
**Model**: `anthropic/claude-sonnet-4-20250514`
**Mode**: `all` (Tab-switchable + delegatable)

### Role

Read-only codebase analyst. Answers questions about implementation, architecture, and code flow quickly and accurately.

### Permissions

| Permission | Value |
|-----------|-------|
| read | allow |
| grep | allow |
| glob | allow |
| edit | **deny** |
| write | **deny** |
| bash | **deny** |
| task | **deny** |

### Key Behaviors

- **Response depth calibration**:
  - "Where is X?" -> file:line, one sentence of context
  - "How does X work?" -> execution flow walkthrough with code snippets
  - "Why is X designed this way?" -> architectural context and trade-offs
  - "What calls X?" -> concrete list of callers with file:line references
- **Code snippet inclusion**: Includes 5-15 line snippets when they clarify the answer. Always paired with file:line references.
- **Honesty about gaps**: If it can't find something, says so explicitly. Doesn't speculate to fill gaps.
- **Scope boundaries**: Answers what's asked. Doesn't volunteer refactoring suggestions or unsolicited opinions.

---

## review

**File**: `agents/review.md`
**Model**: `anthropic/claude-opus-4-6`
**Mode**: `all` (Tab-switchable + delegatable)

### Role

Post-implementation verification. Reviews diffs against requirements, runs validation commands, and checks for correctness, completeness, and regressions.

### Permissions

| Permission | Value |
|-----------|-------|
| read | allow |
| grep | allow |
| glob | allow |
| edit | **deny** |
| write | **deny** |
| bash | allow (deny: rm, rmdir, mkfs, dd, shutdown, reboot, halt, poweroff) |
| task | **deny** |

### Key Behaviors

- **Review process**: Understands the goal -> reads every changed file -> checks correctness -> checks completeness -> runs validation (tests, lint, types, build) -> checks for regressions -> checks code quality.
- **Structured verdict**: Returns PASS, ISSUES FOUND, or FAIL with a summary paragraph.
- **Issue severity**: Critical (must fix — bugs, security, build failures), Warning (should fix — quality concerns), Nit (optional — style, naming).
- **Validation**: Runs all available validation commands before rendering a verdict.
- **Honesty**: If the code is fine, says PASS. Doesn't manufacture issues to seem thorough.

### Output Format

```
Verdict: PASS | ISSUES FOUND | FAIL

Summary: [one paragraph]

Validation results:
- Tests: pass/fail
- Types: pass/fail
- Lint: pass/fail
- Build: pass/fail

Issues (if any):
1. file:line — Description. Severity: critical/warning/nit.

What looks good: [brief note]
```
