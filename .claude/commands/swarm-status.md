# /swarm-status — Show Swarm Health and Progress

## Goal
Display current swarm status including teams, teammates, tasks, and blockers.

## Quick Path
Run the status script:
```bash
node scripts/swarm_status.js
```

For a specific team:
```bash
node scripts/swarm_status.js --team <team-name>
```

## What to Report

### 1. Teams Overview
```
╔═══════════════════════════════════════════════════════════╗
║                    SWARM STATUS                           ║
╠═══════════════════════════════════════════════════════════╣
║ Teams: 1                                                  ║
║ Total Teammates: 4                                        ║
║ Backend: tmux                                             ║
╚═══════════════════════════════════════════════════════════╝
```

### 2. Team Details
```
Team: my-project
├── Leader: team-lead (you)
├── Teammates:
│   ├── engine-worker [🟢 active] — Working on task #3
│   ├── ui-worker [🟢 active] — Working on task #5
│   ├── test-worker [🟡 idle] — Waiting for unblocked tasks
│   └── io-worker [🔴 error] — Last error: timeout
```

### 3. Task Progress
```
Tasks: 19 total
├── ✅ Completed: 7 (37%)
├── 🔄 In Progress: 3 (16%)
├── ⏳ Pending: 6 (32%)
├── 🚫 Blocked: 3 (16%)
└── ❌ Failed: 0 (0%)

Progress: [███████░░░░░░░░░░░░░] 37%
```

### 4. Blocked Tasks
```
Blocked Tasks:
├── #12 "Write E2E tests" — blocked by #8, #9
├── #15 "Deploy to staging" — blocked by #12, #14
└── #17 "Update docs" — blocked by #15
```

### 5. Stuck Detection
Flag potentially stuck tasks:
```
⚠️  Potential Issues:
├── Task #5 has been in_progress for 45 minutes (threshold: 30min)
├── Task #8 has no owner but is unblocked
└── Teammate 'io-worker' has been idle for 20 minutes
```

## Detailed View

If user wants more detail:
```bash
node scripts/swarm_status.js --verbose
```

Shows:
- Full task descriptions
- Teammate message history
- File paths touched
- Verification results

## Actions

Based on status, suggest actions:

| Situation | Suggestion |
|-----------|------------|
| Stuck task | "Task #5 seems stuck. Check teammate logs or reassign." |
| Idle teammate | "ui-worker is idle. Assign unblocked task #8?" |
| Many blockers | "3 tasks blocked by #8. Prioritize #8 completion." |
| Error state | "io-worker in error state. Check logs, consider respawn." |

## Integration with Compound Engineering

If using Compound Engineering's TeammateTool:

```
TeammateTool checkInbox { team_name: "my-project" }
TaskList { team: "my-project" }
```

Report combines both sources.
