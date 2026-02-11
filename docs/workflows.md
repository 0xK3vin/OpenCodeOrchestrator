# Workflows

How the orchestrator chains agents together for common tasks.

## Default Pipeline

The standard execution for any request that changes code is:

  **plan → build → review**

This is the default. The orchestrator follows it unless a specific shortcut exception applies, and must justify any deviation to the user.

## Core Patterns

### Standard workflow (default)

```
User: "Add real-time notifications with WebSocket support"
Orchestrator: "Starting with planning — sending to plan."
  -> plan: produces implementation spec with file paths, interfaces, phased delivery
Orchestrator: "Plan is ready — sending to build."
  -> build: implements phase 1 following the plan step-by-step
Orchestrator: "Build complete — sending to review to verify."
  -> review: reads diff, runs tests/lint/types, checks against plan requirements
  -> returns PASS
Orchestrator: unified summary to user
```

This is the default chain for all code-changing requests: `plan → build → review`. The orchestrator does not report completion until review passes.

### Review loop (issues found)

```
Orchestrator: "Build complete — sending to review."
  -> review: finds critical issue — missing null check in WebSocket handler
  -> returns ISSUES FOUND with file:line details
Orchestrator: "Review found issues — sending back to build."
  -> build: fixes the null check, re-runs tests
Orchestrator: "Fix applied — sending to review again."
  -> review: re-checks, all clean
  -> returns PASS
Orchestrator: unified summary to user
```

The orchestrator loops `build → review` until review passes or the user decides to accept as-is.

### Bug with unclear cause

```
User: "The checkout flow is returning 500 errors intermittently"
Orchestrator: "Unclear failure — sending to debug to isolate root cause first."
  -> debug: traces execution, finds race condition in inventory check
  -> returns diagnostic with evidence grade "confirmed"
Orchestrator: "Root cause identified — sending to plan to design the fix."
  -> plan: produces fix spec
Orchestrator: "Plan ready — sending to build."
  -> build: implements fix based on plan
Orchestrator: "Build complete — sending to review."
  -> review: verifies fix
Orchestrator: summary with root cause explanation + fix details
```

Always diagnose before fixing when the cause is unclear: `debug → plan → build → review`.

### Bug with known cause

```
User: "The date picker is off by one day due to timezone handling in utils/date.ts"
Orchestrator: "Known single-file bug — skipping plan, sending to build. Will review after."
  -> build: fixes timezone handling, runs tests
Orchestrator: "Build complete — sending to review."
  -> review: verifies
Orchestrator: summary
```

Skip debug when the user already knows the cause. Plan can be skipped only if the fix is confined to a single file, under ~20 lines, and unambiguous. Review still runs.

### Blocker during build

```
Orchestrator: "Plan ready — sending to build."
  -> build: implements first two steps, hits a pre-existing type error in a dependency
  -> reports blocker: "Completed steps 1-2. Blocked at step 3 — UserService.getProfile()
     returns `User | undefined` but the plan assumes it always returns `User`.
     Did not attempt a workaround."
Orchestrator: "Build hit a blocker — the plan needs adjustment. Sending back to plan."
  -> plan: revises step 3 to handle the undefined case
Orchestrator: "Revised plan ready — sending to build."
  -> build: completes remaining steps
Orchestrator: "Build complete — sending to review."
  -> review: PASS
Orchestrator: unified summary to user
```

Specialists stop and report blockers instead of improvising fixes. The orchestrator decides the next step.

### Codebase question

```
User: "How does the authentication middleware work?"
Orchestrator: "Codebase question — sending to explore."
  -> explore: traces auth flow, returns explanation with file:line references and code snippets
Orchestrator: relays the explanation
```

Pure read-only analysis, no changes needed.

### Deployment

```
User: "Deploy the latest changes to staging"
Orchestrator: "Deployment task — sending to devops."
  -> devops: checks git status, verifies build, deploys to staging
Orchestrator: deployment status + rollback instructions
```

### Feature + deployment

```
User: "Implement the caching layer and deploy it to staging"
Orchestrator: splits into two phases
  -> plan -> build -> review (feature implementation)
  -> devops (deployment)
Orchestrator: unified summary of feature + deployment status
```

Sequential because deployment depends on build completion.

## Parallel delegation

When tasks are independent, the orchestrator delegates them simultaneously:

```
User: "How does auth work, and separately, what's the DB schema for users?"
Orchestrator: "Two independent questions — sending to explore in parallel."
  -> explore (task 1): auth flow explanation
  -> explore (task 2): DB schema breakdown
Orchestrator: merged response organized by topic
```

## When steps are skipped

The orchestrator may skip pipeline steps only under strict conditions, and must tell the user which step is being skipped and why.

### Skipping plan (`build → review`)

Allowed only when ALL conditions are met:
- The change is confined to a single file
- The change is under ~20 lines
- No new interfaces, types, or public APIs are introduced
- The intent and approach are unambiguous

### Skipping review (`build` only)

Allowed only for purely cosmetic changes:
- Typo corrections in strings, comments, or documentation
- Whitespace or formatting adjustments
- Comment additions or updates

If any logic, behavior, interface, or API is touched — even minimally — review must run.

### Never skip both plan AND review

Unless the change is purely cosmetic (typo/comment only), at least one of plan or review must run. In practice, review runs for nearly everything.

## Delegation prompt quality

The orchestrator constructs self-contained prompts for each delegation. Specialists have no memory of prior conversation.

### What every delegation includes

1. **Context** — User's request, prior agent outputs, relevant codebase state
2. **Goal** — One sentence: what the specialist should accomplish
3. **Scope** — What to touch and what to leave alone
4. **Constraints** — Style, compatibility, performance requirements
5. **Expected output** — What to return (plan, code changes, diagnostic, etc.)
6. **Completion criteria** — How to know the task is done

### Example: bad vs good delegation

**Bad:**
> Fix the auth bug

**Good:**
> The login endpoint at src/api/auth.ts:47 returns 500 when the session cookie is expired instead of 401. The error is `TypeError: Cannot read property 'userId' of null` at line 52. Fix the null check so expired sessions return 401 with body `{error: 'session_expired'}`. Run existing tests in `tests/api/auth.test.ts` after. Only modify src/api/auth.ts.

## Memory integration

The orchestrator uses megamemory (project knowledge graph) to maintain context across sessions:

- **Session start**: Queries for project overview to orient itself
- **Before major tasks**: Queries for relevant concepts (architecture, patterns, prior decisions)
- **After significant work**: Records new features, architecture decisions, and patterns

This means the orchestrator's delegation prompts can include relevant project context even for the first request in a new session.
