---
name: parallel-execution
description: Orchestrate parallel task execution with dependency analysis and self-healing. Use when running Ralph with multiple agents or when tasks can be parallelized.
---

# Parallel Task Execution

Based on patterns from jdrhyne/agent-skills (task-orchestrator, parallel-task).

## Core Concepts

### 1. Dependency Rules

```
Same file = SEQUENTIAL    → Tasks touching same file must run in order
Different files = PARALLEL → Independent tasks can run simultaneously
Explicit depends = WAIT    → dependsOn array enforces ordering
Phase gates = BARRIER      → Next phase waits for current completion
```

### 2. Task Status Values

| Status | Meaning |
|--------|---------|
| `pending` | Not started yet |
| `blocked` | Waiting on dependency |
| `running` | Agent working on it |
| `stuck` | Needs intervention (auto-heal) |
| `error` | Failed, needs retry |
| `complete` | Done, ready for commit |
| `committed` | Changes committed |
| `merged` | PR merged (if using PRs) |

### 3. Task-Graph Schema (Enhanced)

```json
{
  "project": "wasm-sqlite-editor",
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
          "startedAt": null,
          "lastProgress": null,
          "completedAt": null,
          "agent": null,
          "attempt": 0
        }
      ]
    }
  ]
}
```

## Parallel Execution Loop

The orchestrator follows this loop (from parallel-task pattern):

```
LOOP:
  1. Read task-graph.json
  2. Find all unblocked tasks (dependsOn satisfied)
  3. Group by parallelizability (different files = parallel)
  4. Launch agents for parallel batch
  5. Monitor progress
  6. Self-heal stuck tasks
  7. Mark completed tasks
  8. Check phase gate
  9. REPEAT until all tasks done
```

### Finding Unblocked Tasks

```bash
# From task-graph.json, a task is unblocked when:
# - status == "pending"
# - all tasks in dependsOn have status == "complete" or "committed"
# - no other running task shares files with this task

jq -r '
  .phases[].tasks as $all |
  ($all | map(select(.status == "complete" or .status == "committed")) | map(.id)) as $done |
  ($all | map(select(.status == "running")) | map(.files) | flatten | unique) as $locked_files |
  $all | map(select(
    .status == "pending" and
    ((.dependsOn // []) | all(. as $dep | $done | index($dep))) and
    ((.files // []) | all(. as $f | $locked_files | index($f) | not))
  ))
' task-graph.json
```

### Parallel Batch Selection

```bash
# From unblocked tasks, select those that don't share files
select_parallel_batch() {
  local tasks="$1"
  local selected=()
  local used_files=()
  
  for task in $(echo "$tasks" | jq -c '.[]'); do
    task_files=$(echo "$task" | jq -r '.files[]')
    conflict=false
    
    for f in $task_files; do
      if [[ " ${used_files[*]} " =~ " $f " ]]; then
        conflict=true
        break
      fi
    done
    
    if ! $conflict; then
      selected+=("$task")
      used_files+=($task_files)
    fi
  done
  
  echo "${selected[@]}"
}
```

## Self-Healing (from task-orchestrator)

### Heartbeat Check (every 15 minutes)

```bash
check_task_health() {
  local task_id="$1"
  local started_at="$2"
  local last_progress="$3"
  
  now=$(date +%s)
  
  # Check for stall (no progress in 20+ minutes)
  if [[ -n "$last_progress" ]]; then
    progress_ts=$(date -d "$last_progress" +%s)
    mins_since=$((($now - $progress_ts) / 60))
    
    if [[ $mins_since -gt 20 ]]; then
      echo "STUCK:$task_id:no_progress_${mins_since}m"
      return 2
    fi
  fi
  
  echo "HEALTHY:$task_id"
  return 0
}
```

### Self-Heal Actions

| Condition | Action |
|-----------|--------|
| No progress 20+ min | Kill and restart with context |
| Error in output | Capture error, restart with fix hint |
| Waiting for input | Send appropriate response |
| Agent prompt idle | Mark complete, check for commits |

### Restart with Error Context

```bash
restart_with_context() {
  local task_id="$1"
  local error_log="$2"
  
  # Update task status
  update_task_status "$task_id" "pending" 
  
  # Increment attempt counter
  increment_task_attempt "$task_id"
  
  # Generate enhanced prompt with error context
  new_prompt="Previous attempt failed with:
$(tail -20 "$error_log")

Please fix the issue and retry. Focus on:
1. The specific error message
2. What might have caused it
3. How to avoid it this time"
  
  # Relaunch
  launch_agent "$task_id" "$new_prompt"
}
```

## Task Prompt Template

Based on parallel-task pattern:

```markdown
You are implementing a specific task from a development plan.

## Context
- Plan: artifacts/03-plan.md
- Sprint: {sprint_name}
- This task: {task_id} of {total_tasks}

## Related Context
- Dependencies completed: {completed_deps}
- Tasks in same sprint: {sibling_tasks}
- Files you may reference: {related_files}

## Your Task
**{task_id}: {subject}**

**Files to modify:** {files}

**Description:**
{description}

**Acceptance Criteria:**
{acceptance_criteria}

**Verification:**
{verification_commands}

## Instructions
1. Read progress.txt for learnings from previous tasks
2. Examine all relevant files & dependencies
3. Implement changes for all acceptance criteria
4. Keep work **atomic and committable**
5. For each file: read first, edit carefully, preserve formatting
6. Run verification commands
7. If pass, commit with message: "{commit_message}"
8. Append learnings to progress.txt

## Critical Rules
- Only modify files in allowed paths
- Stop and describe blockers if encountered
- Focus on this specific task only

## When Complete
Output exactly: TASK_COMPLETE
```

## Execution Summary Template

After each phase or full run:

```markdown
# Execution Summary

## Tasks: {completed}/{total}

### ✅ Completed
- S1-T1: Initialize project structure
  - Files: package.json, tsconfig.json
  - Duration: 12 min

### ❌ Failed
- S1-T3: Setup database schema
  - Error: "Cannot find module 'better-sqlite3'"
  - Attempt: 2/3
  - Next: Install native dependency

### ⏳ Blocked
- S2-T1: Implement query builder
  - Waiting on: S1-T3 (database schema)

## Files Modified
- package.json (S1-T1)
- tsconfig.json (S1-T1)
- src/types/index.ts (S1-T2)

## Learnings Captured
- Vite requires "moduleResolution": "bundler" in tsconfig
- Native SQLite bindings need special WASM handling
```

## Integration with Ralph

### With Parallelism

```bash
# Launch Ralph with parallel execution
./scripts/ralph.sh --parallel 3 --fresh-eyes 50

# Options:
#   --parallel N    Run up to N agents in parallel
#   --self-heal     Enable automatic stuck task recovery
#   --phase-gates   Wait for phase completion before next
```

### Without Parallelism (Sequential)

```bash
# Default single-agent mode
./scripts/ralph.sh --fresh-eyes 50
```

## Phase Gates

Don't start Phase N+1 until Phase N is 100% complete:

```bash
check_phase_complete() {
  local phase_name="$1"
  
  # Get all tasks in phase
  tasks=$(jq -r --arg p "$phase_name" '
    .phases[] | select(.name == $p) | .tasks
  ' task-graph.json)
  
  # Check if all are complete
  incomplete=$(echo "$tasks" | jq '[.[] | select(.status != "complete" and .status != "committed")] | length')
  
  if [[ "$incomplete" -eq 0 ]]; then
    echo "PHASE_COMPLETE"
    return 0
  else
    echo "PHASE_INCOMPLETE:$incomplete"
    return 1
  fi
}
```

## Auto PR Creation (using gh CLI)

When a task completes successfully, create a PR automatically:

```bash
create_pr_for_task() {
  local task_id="$1"
  local subject="$2"
  local issue_number="$3"  # Optional: linked issue
  
  # Get current branch
  branch=$(git branch --show-current)
  
  # Ensure we're not on main
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "ERROR: Cannot create PR from main branch"
    return 1
  fi
  
  # Push the branch
  git push -u origin "$branch"
  
  # Build PR body
  local body="## Summary
Implements task ${task_id}: ${subject}

## Changes
$(git log main..HEAD --oneline | sed 's/^/- /')

## Verification
- [ ] Tests pass
- [ ] Manual verification done

---
*Auto-generated by Ralph*"

  # Add issue link if provided
  if [[ -n "$issue_number" ]]; then
    body="Closes #${issue_number}

${body}"
  fi
  
  # Create PR
  gh pr create \
    --title "feat(${task_id}): ${subject}" \
    --body "$body" \
    --base main
  
  # Capture PR number
  pr_url=$(gh pr view --json url -q '.url')
  echo "PR created: $pr_url"
}
```

### Branch Naming Convention

```bash
# For each task, create a branch
git checkout -b "feat/${task_id}-$(echo "$subject" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 50)"

# Examples:
# feat/s1-t1-initialize-project-structure
# feat/s1-t2-define-core-types
```

### Full Task Completion Flow

```bash
complete_task() {
  local task_id="$1"
  
  # 1. Run verification
  if ! run_verification "$task_id"; then
    mark_task_error "$task_id" "Verification failed"
    return 1
  fi
  
  # 2. Commit changes
  git add -A
  git commit -m "feat(${task_id}): ${subject}"
  
  # 3. Mark task complete
  mark_task_complete "$task_id"
  
  # 4. Create PR (if AUTO_PR=true)
  if [[ "${AUTO_PR:-false}" == "true" ]]; then
    create_pr_for_task "$task_id" "$subject" "$issue_number"
  fi
  
  # 5. Return to main for next task
  git checkout main
  git pull
}
```

### Ralph Config for Auto PR

```bash
# In ralph.sh
AUTO_PR="true"           # Auto-create PRs when tasks complete
PR_BASE_BRANCH="main"    # Base branch for PRs
```

## Quick Reference

| Pattern | Source | Purpose |
|---------|--------|---------|
| Dependency rules | task-orchestrator | Same file = serial |
| Loop pattern | parallel-task | Launch → monitor → repeat |
| Self-healing | task-orchestrator | Auto-restart stuck tasks |
| Phase gates | task-orchestrator | Barrier between phases |
| Task prompt | parallel-task | Context-rich agent instructions |
| Execution summary | parallel-task | Standardized reporting |
| Auto PR | task-orchestrator | Create PRs with `gh` CLI |
