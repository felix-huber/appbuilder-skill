---
name: parallel-execution
description: Orchestrate parallel task execution with dependency analysis and self-healing. Use when running Ralph with multiple agents or when tasks can be parallelized.
---

# Parallel Task Execution

Orchestrates concurrent AI agent execution while respecting file-level dependencies and providing automatic recovery from stuck tasks.

## Dependency Rules

Tasks execute based on these constraints:

| Constraint | Behavior |
|------------|----------|
| Same file | Sequential - tasks touching the same file run in order |
| Different files | Parallel - independent tasks can run simultaneously |
| `dependsOn` array | Wait - explicit ordering enforced |
| Phase boundary | Barrier - next phase waits for current completion |

## Task Status Values

| Status | Meaning |
|--------|---------|
| `pending` | Not started |
| `blocked` | Waiting on dependency |
| `running` | Agent working |
| `stuck` | Needs intervention (auto-heal triggers) |
| `error` | Failed, needs retry |
| `complete` | Done, ready for commit |
| `committed` | Changes committed |
| `merged` | PR merged |

## Task-Graph Schema

```json
{
  "project": "my-project",
  "created": "2026-01-27T00:00:00Z",
  "phases": [
    {
      "name": "Sprint 1: Core Foundation",
      "tasks": [
        {
          "id": "S1-T1",
          "subject": "Initialize project structure",
          "files": ["package.json", "tsconfig.json"],
          "dependsOn": [],
          "status": "pending",
          "complexity": 3,
          "verification": ["npm run build", "npm test"],
          "startedAt": null,
          "completedAt": null,
          "agent": null,
          "attempt": 0
        }
      ]
    }
  ]
}
```

## Execution Loop

Ralph follows this cycle:

```
1. Read task source (task-graph.json or beads)
2. Find unblocked tasks (dependencies satisfied, no file conflicts)
3. Group by parallelizability
4. Launch agents for parallel batch
5. Monitor progress (heartbeat every 15 min)
6. Self-heal stuck tasks
7. Mark completed, commit changes
8. Check phase gate
9. Repeat until done
```

### Finding Unblocked Tasks

A task is unblocked when:
- `status == "pending"`
- All `dependsOn` tasks are `complete` or `committed`
- No running task shares files with this task

```bash
jq -r '
  .phases[].tasks as $all |
  ($all | map(select(.status == "complete" or .status == "committed")) | map(.id)) as $done |
  ($all | map(select(.status == "running")) | map(.files) | flatten | unique) as $locked |
  $all | map(select(
    .status == "pending" and
    ((.dependsOn // []) | all(. as $dep | $done | index($dep))) and
    ((.files // []) | all(. as $f | $locked | index($f) | not))
  ))
' task-graph.json
```

## Self-Healing

Ralph automatically recovers stuck tasks based on heartbeat monitoring.

### Detection Thresholds

| Condition | Default | Action |
|-----------|---------|--------|
| No progress | 20 min | Kill and restart with error context |
| Error in output | Immediate | Capture error, restart with fix hint |
| Agent idle at prompt | Immediate | Mark complete, check for commits |

### Restart with Context

When a task stalls, Ralph restarts it with the error log:

```bash
restart_with_context() {
  local task_id="$1"
  local error_log="$2"

  update_task_status "$task_id" "pending"
  increment_task_attempt "$task_id"

  new_prompt="Previous attempt failed with:
$(tail -20 "$error_log")

Fix the issue and retry. Focus on:
1. The specific error message
2. What might have caused it
3. How to avoid it this time"

  launch_agent "$task_id" "$new_prompt"
}
```

## Stale Bead Reset

At startup, Ralph resets any beads stuck in `IN_PROGRESS` from previous crashed runs. This prevents infinite loops where tasks appear claimed but no agent is working on them.

```bash
# Called automatically at ralph.sh startup
reset_stale_in_progress_beads() {
  local in_progress=$(br list --status in_progress --json)
  jq -r '.[].id' <<< "$in_progress" | while read -r bead_id; do
    br update "$bead_id" --status open --comment "Reset by Ralph (stale IN_PROGRESS)"
  done
}
```

## Lock File Mechanism

Ralph uses a lock file to prevent concurrent instances:

```bash
# Lock file location
$PROJECT_ROOT/.ralph.lock

# Contains PID of running instance
# Stale locks (dead process) are auto-removed
# Use --override-lock <pid> to force takeover
```

If Ralph detects an existing lock:
1. Checks if PID is still running
2. If dead, removes stale lock automatically
3. If alive, exits with instructions

Override for agents that cannot delete files:
```bash
./scripts/ralph.sh --override-lock 12345 --beads 50
```

## Multi-Stack Auto-Verification

Ralph auto-detects project type and runs appropriate verification commands:

| Stack | Detection | Commands |
|-------|-----------|----------|
| Makefile | `Makefile` exists | `make lint`, `make test`, `make build` |
| Node.js | `package.json` | `npm run lint`, `npm run typecheck`, `npm run build`, `npm test` |
| Python | `pyproject.toml`, `setup.py`, `requirements.txt` | `ruff check .`, `mypy .`, `pytest -v` |
| Rust | `Cargo.toml` | `cargo clippy`, `cargo check`, `cargo build`, `cargo test` |
| Go | `go.mod` | `go vet ./...`, `go build ./...`, `go test ./...` |
| Ruby | `Gemfile` | `bundle exec rubocop`, `bundle exec rspec` |

**Makefile takes priority** - if a Makefile has the target, it's used regardless of other project files.

### Fallback Verification

If a task has no explicit verification, Ralph checks (in order):
1. `--default-verify` CLI flag
2. `RALPH_DEFAULT_VERIFY` environment variable
3. `verification.txt` file in project root
4. Auto-detected stack commands (test, then build)

```bash
# Set default verification via CLI
./scripts/ralph.sh --default-verify "make test && make build" 50

# Or via environment
export RALPH_DEFAULT_VERIFY="npm test"
./scripts/ralph.sh 50
```

## Ralph CLI Examples

### Basic Execution

```bash
# 50 iterations, smart tool routing
./scripts/ralph.sh 50

# Use beads for task tracking
./scripts/ralph.sh --beads 50

# Use task-graph.json explicitly
./scripts/ralph.sh --no-beads 50
```

### Tool Selection

```bash
# Force Claude for all tasks
./scripts/ralph.sh --tool claude 50

# Force Codex for all tasks
./scripts/ralph.sh --tool codex 50

# Smart routing (default): backend->Codex, UI->Claude
./scripts/ralph.sh --tool smart 50

# Ask for each task
./scripts/ralph.sh --ask 50
```

### Strict Mode and Cross-Model Review

```bash
# Full strict mode: TDD enforcement, cross-model review, auto-commit
./scripts/ralph.sh --strict --beads 50

# Cross-model review: code with Claude, review with Codex
./scripts/ralph.sh --tool claude --review-tool codex --beads 50

# Require test changes in each task
./scripts/ralph.sh --require-tests 50

# Limit to 15 tasks, continue on errors
./scripts/ralph.sh --max-tasks 15 --continue-on-error 50
```

### Verification Control

```bash
# Disable specific checks
./scripts/ralph.sh --no-verify-tests 50
./scripts/ralph.sh --no-verify-lint --no-verify-typecheck 50

# Allow tasks without verification (not recommended)
./scripts/ralph.sh --allow-no-verify 50

# Set default verification for projects without task-level verification
./scripts/ralph.sh --default-verify "cargo test" 50

# Skip final E2E regression suite
./scripts/ralph.sh --no-final-e2e 50
```

### Final E2E Regression Suite

After all tasks complete, Ralph runs a full E2E test suite to catch regressions:

- **Detection**: Auto-detects `npm run test:e2e`, `npm run e2e`, or Playwright config
- **Per-bead tests**: Fast (~30s), focused on specific functionality
- **Final E2E**: Slower (~5-10 min), catches cross-feature regressions
- **Behavior**: If final E2E fails, Ralph exits with error before declaring success

Disable with `--no-final-e2e` for faster iteration during development.

### CI/CD Integration

```bash
# Auto-push after each commit (keeps remote in sync)
./scripts/ralph.sh --auto-push --beads 50

# Auto-create PRs for completed tasks
./scripts/ralph.sh --auto-pr --beads 50

# Specify PR base branch
./scripts/ralph.sh --auto-pr --pr-base develop 50
```

### Self-Healing and Recovery

```bash
# Disable self-healing
./scripts/ralph.sh --no-self-heal 50

# Custom stall threshold (minutes before task is considered stuck)
./scripts/ralph.sh --stall-threshold 30 50

# Shorter timeout for simpler tasks
./scripts/ralph.sh --stall-minutes 20 50

# Override stale lock from crashed instance
./scripts/ralph.sh --override-lock 12345 50
```

### Complex Task Timeouts

If tasks timeout with **no output** (exit codes 124, 137, 143), Ralph detects this and logs:
```
EMPTY OUTPUT DETECTED - Claude CLI likely hung during context loading
This task may be too complex. Consider breaking it into smaller sub-tasks.
```

**Solutions for complex tasks:**
1. Break into smaller sub-tasks (e.g., split "stress test with 20 iterations" into focused tests)
2. Reduce timeout: `--stall-minutes 15` to fail fast
3. Add progress markers to bead prompts ("Log progress after each step")
4. Implement complex E2E tests manually, use Ralph for unit/integration tests

### CLI Execution Details

Ralph runs AI tools with specific flags to ensure reliable automated execution:

```bash
# Claude Code (synchronous mode)
claude -p --dangerously-skip-permissions --no-session-persistence "<prompt>"

# Codex CLI
codex exec --yolo "<prompt>"
```

**Key behaviors:**
- `--no-session-persistence` ensures Claude runs synchronously when stdout is redirected
- Stdin is redirected from `/dev/null` to prevent CLI from waiting for input
- Output is captured to temp file, then copied to task log
- Use `tail -f .beads/logs/<task-id>.log` for real-time monitoring

## Phase Gates

Ralph waits for all tasks in a phase to complete before starting the next:

```bash
check_phase_complete() {
  local phase_name="$1"

  tasks=$(jq -r --arg p "$phase_name" '
    .phases[] | select(.name == $p) | .tasks
  ' task-graph.json)

  incomplete=$(echo "$tasks" | jq '[.[] | select(.status != "complete" and .status != "committed")] | length')

  [[ "$incomplete" -eq 0 ]]
}
```

## Task Prompt Template

Each agent receives a structured prompt:

```markdown
You are implementing a specific task from a development plan.

## Context
- Plan: artifacts/03-plan.md
- Sprint: {sprint_name}
- This task: {task_id} of {total_tasks}

## Your Task
**{task_id}: {subject}**

**Files to modify:** {files}

**Description:**
{description}

**Verification:**
{verification_commands}

## Instructions
1. Read progress.txt for learnings from previous tasks
2. Examine all relevant files and dependencies
3. Implement changes for all acceptance criteria
4. Run verification commands
5. If pass, commit with message: "{commit_message}"
6. Append learnings to progress.txt

## Critical Rules
- Only modify files in allowed paths
- Stop and describe blockers if encountered
- Focus on this specific task only

## When Complete
Output exactly: TASK_COMPLETE
```

## Execution Summary

After each run, Ralph produces:

```markdown
# Execution Summary

## Tasks: 8/12

### Completed
- S1-T1: Initialize project structure (12 min)
- S1-T2: Define core types (8 min)

### Failed
- S1-T3: Setup database schema
  - Error: "Cannot find module 'better-sqlite3'"
  - Attempt: 2/3
  - Next: Install native dependency

### Blocked
- S2-T1: Implement query builder
  - Waiting on: S1-T3

## Files Modified
- package.json (S1-T1)
- tsconfig.json (S1-T1)
- src/types/index.ts (S1-T2)
```

## Auto PR Creation

When `--auto-pr` is enabled, Ralph creates PRs for completed tasks:

```bash
create_pr_for_task() {
  local task_id="$1"
  local subject="$2"

  git push -u origin "$branch"

  gh pr create \
    --title "feat(${task_id}): ${subject}" \
    --body "## Summary
Implements task ${task_id}: ${subject}

## Changes
$(git log main..HEAD --oneline | sed 's/^/- /')

## Verification
- [ ] Tests pass
- [ ] Manual verification done

---
*Auto-generated by Ralph*" \
    --base main
}
```

### Branch Naming

```bash
# Feature branches follow this pattern:
feat/s1-t1-initialize-project-structure
feat/s1-t2-define-core-types
```

## Quick Reference

| Feature | Default | Flag |
|---------|---------|------|
| Tool routing | smart | `--tool <claude\|codex\|smart>` |
| Task source | auto-detect | `--beads` / `--no-beads` |
| Self-healing | on | `--no-self-heal` |
| Stall threshold | 20 min | `--stall-threshold <min>` |
| Build verification | on | `--no-verify-build` |
| Test verification | on | `--no-verify-tests` |
| Final E2E suite | on (if exists) | `--no-final-e2e` |
| Auto-PR | on | `--no-auto-pr` |
| Auto-push | off | `--auto-push` |
| TDD enforcement | off | `--require-tests` |
| Max attempts | 3 | `--max-attempts <n>` |
