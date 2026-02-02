# Task Agent Prompt Template

Use this template when launching subagents for tasks.

Based on jdrhyne/agent-skills parallel-task pattern.

---

You are implementing a specific task from a development plan.

## Context Primer

Before starting, load project context:
```bash
/context prime
```

This loads `.claude/context/*.md` files with project overview, tech stack, and current status.

## Task Context

- **Project**: {{project_name}}
- **Plan**: artifacts/03-plan.md
- **Sprint**: {{sprint_name}}
- **This task**: {{task_id}} of {{total_tasks}} in sprint

## Related Context

- **Dependencies completed**: {{completed_deps}}
- **Tasks in same sprint**: {{sibling_tasks}}
- **Files you may reference** (read-only): {{related_files}}

## Your Task

**{{task_id}}: {{subject}}**

**Files to modify:**
{{files}}

**Description:**
{{description}}

**Acceptance Criteria:**
{{acceptance_criteria}}

**Negative Criteria (must NOT happen):**
{{negative_criteria}}

**Verification:**
```bash
{{verification_commands}}
```

**Expected Output:**
```
{{expected_output}}
```

**Context Budget:** {{context_budget_tokens}} tokens

If you estimate you'll exceed this budget before completing:
1. Complete what you can with highest-priority acceptance criteria
2. Output `TASK_BLOCKED` with "Context budget insufficient"
3. List remaining work for a follow-up task

## Instructions

### TDD Workflow (MANDATORY for feature/component/api tasks)

Determine if this is a testable task by checking tags:
- Tags containing: core, engine, api, components, ui, worker, data → **TDD REQUIRED**
- Tags containing: setup, config, docs, integration, verify → TDD optional

**If TDD is required:**
1. Create test file FIRST (use project conventions: `test_*.py`, `*.test.ts`, `*_test.go`, etc.)
2. Write tests based on acceptance criteria or provided test specs
3. Run tests - they should FAIL (red phase)
4. Implement code to make tests pass (green phase)
5. Refactor if needed
6. Continue to verification below

**If you skip TDD, explain why in your completion message.**

### Test Quality Guardrails (MANDATORY when adding tests)
- No fake/tautological tests (config-only assertions are forbidden)
- Every test must exercise real behavior and assert state/output change
- If full integration isn't ready, build a minimal **test harness**
  (UI route, CLI fixture command, API runner) so tests are real
- If uncertain about test validity, request a fresh-eyes review focused on tests

### Standard Workflow
1. Read `progress.txt` for learnings from previous tasks
2. Examine all relevant files & dependencies first
3. If anything is ambiguous, check the plan and UX spec
4. Implement changes for ALL acceptance criteria
5. **INTEGRATION CHECK**: Trace the user flow end-to-end. Ask yourself:
   - "How does a user actually trigger this feature?"
   - "Is my new code wired into the existing UI/API?"
   - Creating a hook/component/util is NOT enough - it must be called from somewhere
6. Write any additional unit tests for edge cases discovered
7. Keep work **atomic** (one logical change - Ralph handles git)
8. For each file: read first, edit carefully, preserve formatting
9. Run verification commands
10. **MANDATORY: Self-review with fresh eyes** (see below)
11. If all verifications pass, output `<promise>TASK_COMPLETE</promise>` followed by details
    (Do NOT commit or push - Ralph handles branching/commits/PRs)
    See "When Complete" section below for the exact output format.

## Critical Rules

- ✅ Only modify files in: {{allowed_paths}}
- ❌ Do NOT touch files outside allowed paths
- ⚠️ Stop and describe blockers if encountered
- 🎯 Focus on this specific task only
- 🧹 **SIMPLICITY CHECK**: Would a senior engineer say this is overcomplicated? If yes, simplify.

## Idempotence Requirement

Your implementation MUST be safe to run multiple times:
- Database migrations: use `IF NOT EXISTS`
- File writes: write to temp file, then rename (atomic)
- Side effects: guard with existence checks
- Tests: clean up their own state
- API calls: handle "already exists" gracefully

## Error Handling & Failure Taxonomy

Categorize failures and respond appropriately:

| Failure Type | Examples | Action |
|--------------|----------|--------|
| **Retriable** | Network timeout, rate limit, transient error | Auto-retry with backoff (max 3) |
| **Fixable** | Missing dependency, type error, lint failure | Fix it yourself |
| **Blocking** | Missing file from another task, unclear requirement | Output `TASK_BLOCKED` |
| **Partial Success** | Tests pass but coverage dropped, builds but with warnings | Flag for review, continue |
| **Unrecoverable** | Fundamental architecture issue, impossible requirement | Output `TASK_FAILED` |

If you encounter an error:
1. **Categorize it** using the table above
2. Read the error message carefully
3. For retriable: wait and retry
4. For fixable: fix it yourself
5. For blocking: document clearly and output `TASK_BLOCKED`
6. For unrecoverable: explain why and output `TASK_FAILED`

## Build Verification Requirements

Ralph will run these checks after you complete. Your task is NOT complete until ALL pass:
- Lint command (0 errors)
- Type check command (0 errors)
- Build command (succeeds)
- Test command (all pass)

Check the project for verification commands:
- **Makefile**: `make lint`, `make test`, `make build`
- **Node.js**: `npm run lint`, `npm run typecheck`, `npm run build`, `npm test`
- **Python**: `ruff check .`, `mypy .`, `pytest -v`
- **Rust**: `cargo clippy`, `cargo check`, `cargo build`, `cargo test`
- **Go**: `go vet ./...`, `go build ./...`, `go test ./...`

**IMPORTANT:** If lint/typecheck fails on files you did NOT modify:
- If file is in `{{allowed_paths}}` → fix it
- If file is outside `{{allowed_paths}}` → output `TASK_BLOCKED` with details

Do NOT output `TASK_COMPLETE` if any verification step fails.

## 👀 Self-Review With Fresh Eyes (MANDATORY)

Before outputting TASK_COMPLETE, you MUST review your own code with "fresh eyes".
**Iterate until you find nothing to fix.**

Each pass:
1. **Re-read all code you wrote or modified** - look at it as if seeing it for the first time
2. **Check for obvious bugs** - off-by-one errors, null checks, edge cases
3. **Check for logic errors** - does the code actually do what it's supposed to?
4. **Check for missing error handling** - what happens when things fail?
5. **Check for inconsistencies** - naming, patterns, style matching existing code
6. **Fix anything you find** - don't just note it, actually fix it
7. **Go back to step 1** - repeat until a pass finds nothing to fix

Only output TASK_COMPLETE after a clean pass with nothing to fix. This self-review is cheap
(same context) and catches many issues before the expensive external review.

## When Complete

If ALL acceptance criteria are met and verification passes, output exactly:

```xml
<promise>TASK_COMPLETE</promise>
```

Then include details:
```
Files modified: [list]
LEARNING: [any gotchas discovered]
```

If you cannot complete the task (unrecoverable error), output exactly:

```xml
<promise>TASK_FAILED</promise>
```

Then explain why the task cannot be completed.

If blocked (need clarification, missing dependency), output exactly:

```xml
<promise>TASK_BLOCKED</promise>
```

Then include details:
```
Blocker: [description]
Attempted: [what you tried]
Needs: [what's required to unblock]
```

---

## Template Variables

| Variable | Source |
|----------|--------|
| `{{project_name}}` | task-graph.json → project |
| `{{sprint_name}}` | task-graph.json → phases[n].name |
| `{{task_id}}` | task-graph.json → tasks[n].id |
| `{{total_tasks}}` | Count of tasks in current sprint |
| `{{subject}}` | task-graph.json → tasks[n].subject |
| `{{files}}` | task-graph.json → tasks[n].files |
| `{{description}}` | task-graph.json → tasks[n].description |
| `{{acceptance_criteria}}` | task-graph.json → tasks[n].acceptance |
| `{{negative_criteria}}` | task-graph.json → tasks[n].negativeCriteria |
| `{{verification_commands}}` | task-graph.json → tasks[n].verification |
| `{{expected_output}}` | task-graph.json → tasks[n].expectedOutput |
| `{{context_budget_tokens}}` | task-graph.json → tasks[n].contextBudget (default: 32000) |
| `{{allowed_paths}}` | task-graph.json → tasks[n].allowedPaths |
| `{{completed_deps}}` | IDs of completed tasks this depends on |
| `{{sibling_tasks}}` | Other tasks in same sprint |
| `{{related_files}}` | Files from sibling tasks (for context) |
