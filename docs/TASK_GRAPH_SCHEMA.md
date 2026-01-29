# Task Graph Schema (Enhanced)

Based on patterns from jdrhyne/agent-skills task-orchestrator.

## Schema

```json
{
  "project": "wasm-sqlite-editor",
  "repo": "user/repo",
  "created": "2026-01-27T00:00:00Z",
  "model": "claude-sonnet-4",
  "phases": [
    {
      "name": "Sprint 1: Core Foundation",
      "goal": "Setup project structure and core types",
      "demoValidation": [
        "npm run dev starts without errors",
        "TypeScript compiles with no errors"
      ],
      "tasks": [
        {
          "id": "S1-T1",
          "subject": "Initialize project structure",
          "description": "Create Vite + React + TypeScript scaffold",
          "tags": ["setup", "core"],
          "files": ["package.json", "tsconfig.json", "vite.config.ts"],
          "allowedPaths": ["/"],
          "deliverable": "package.json, tsconfig.json, vite.config.ts",
          "acceptance": [
            "package.json has all required dependencies",
            "tsconfig.json has strict mode enabled",
            "vite.config.ts configured for React"
          ],
          "verification": ["npm run dev"],
          "dependsOn": [],
          "complexity": 2,
          "status": "pending",
          "attempt": 0,
          "maxAttempts": 3,
          "agent": null,
          "startedAt": null,
          "lastProgress": null,
          "completedAt": null,
          "commitHash": null,
          "error": null
        }
      ]
    }
  ]
}
```

## Field Reference

### Project-Level

| Field | Type | Description |
|-------|------|-------------|
| `project` | string | Project name |
| `repo` | string | GitHub repo (owner/name) |
| `created` | ISO datetime | When graph was created |
| `model` | string | Default AI model to use |

### Phase-Level

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Sprint/phase name with number |
| `goal` | string | What this phase accomplishes |
| `demoValidation` | string[] | How to verify phase completion |

### Task-Level

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique ID (S{sprint}-T{task}) |
| `subject` | string | Short task title |
| `description` | string | Full description |
| `tags` | string[] | Categories (core, ui, api, etc.) |
| `files` | string[] | Files this task will modify |
| `allowedPaths` | string[] | Glob patterns for allowed modifications |
| `deliverable` | string | What artifact is produced |
| `acceptance` | string[] | Acceptance criteria |
| `verification` | string[] | Commands to verify completion |
| `dependsOn` | string[] | Task IDs that must complete first |
| `complexity` | number | 1-10 difficulty rating |

### Task Status Fields

| Field | Type | Description |
|-------|------|-------------|
| `status` | string | Current status (see below) |
| `attempt` | number | Current attempt count |
| `maxAttempts` | number | Max retries before giving up |
| `agent` | string | Which agent is working on it |
| `startedAt` | ISO datetime | When task started |
| `lastProgress` | ISO datetime | Last activity timestamp |
| `completedAt` | ISO datetime | When task completed |
| `commitHash` | string | Git commit if successful |
| `error` | string | Error message if failed |

## Status Values

| Status | Meaning | Next Action |
|--------|---------|-------------|
| `pending` | Not started | Can be picked up |
| `blocked` | Waiting on dependency | Check dependsOn tasks |
| `running` | Agent working on it | Monitor progress |
| `stuck` | No progress 20+ min | Self-heal: restart |
| `error` | Failed with error | Retry with context |
| `complete` | Verification passed | Can be committed |
| `committed` | Changes committed | Done |
| `skipped` | Intentionally skipped | Done |

## Status Transitions

```
pending → running → complete → committed
           ↓
         stuck → running (self-heal restart)
           ↓
         error → running (retry with context)
           ↓
         skipped (after max attempts)
```

## Dependency Resolution

A task is **unblocked** when:
1. Its status is `pending`
2. All tasks in `dependsOn` have status `complete` or `committed`
3. No `running` task shares any files with it

```javascript
function isUnblocked(task, allTasks) {
  if (task.status !== 'pending') return false;
  
  const completedIds = allTasks
    .filter(t => t.status === 'complete' || t.status === 'committed')
    .map(t => t.id);
  
  const depsComplete = task.dependsOn.every(dep => completedIds.includes(dep));
  
  const runningFiles = allTasks
    .filter(t => t.status === 'running')
    .flatMap(t => t.files);
  
  const noFileConflict = !task.files.some(f => runningFiles.includes(f));
  
  return depsComplete && noFileConflict;
}
```

## Parallel Execution Rules

| Condition | Result |
|-----------|--------|
| Different files, no dependsOn | ✅ Can run in parallel |
| Same files | ❌ Must run sequentially |
| Task A in B's dependsOn | ❌ B waits for A |
| Different phases | ❌ Phase gate (all of N complete before N+1) |

## Self-Healing

When `lastProgress` is stale (>20 min):

1. Mark task as `stuck`
2. Capture current output/logs
3. Kill the agent session
4. Reset status to `pending`
5. Increment `attempt`
6. Relaunch with error context

```bash
# Detect stale task
now=$(date +%s)
last=$(date -d "$lastProgress" +%s)
mins=$(( (now - last) / 60 ))

if [ $mins -gt 20 ]; then
  echo "Task $id stuck for ${mins}m - restarting"
fi
```

## Example: Resolving Task Order

Given:
```json
[
  {"id": "S1-T1", "files": ["package.json"], "dependsOn": []},
  {"id": "S1-T2", "files": ["src/types.ts"], "dependsOn": []},
  {"id": "S1-T3", "files": ["src/types.ts"], "dependsOn": ["S1-T2"]},
  {"id": "S1-T4", "files": ["src/db.ts"], "dependsOn": ["S1-T1"]}
]
```

**Parallel batch 1**: S1-T1, S1-T2 (different files, no deps)
**After batch 1**: S1-T3, S1-T4 (deps now satisfied)
**S1-T3 and S1-T4**: Can run in parallel (different files)

Total: 2 batches instead of 4 sequential tasks = 2x faster
