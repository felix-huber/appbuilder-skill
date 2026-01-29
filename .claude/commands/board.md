# /board — Open the Task Board

## Goal
Open a visual Kanban view of the task graph.

## What it shows
- `artifacts/04-task-graph.json` rendered as columns: Pending, Blocked, In Progress, Completed
- Filter by tag, status, source (plan vs oracle)
- Search across subjects and tags
- Export markdown report

## Prerequisites
- `artifacts/04-task-graph.json` must exist (run `/artifact-tasks` first)

## Run

**Start the server and open the board:**

```bash
# Start server in background and open browser
python -m http.server 8080 --directory . &
open http://localhost:8080/tools/task-board/  # macOS
# Or: xdg-open http://localhost:8080/tools/task-board/  # Linux
```

Just run this directly. Do not ask the user to run it.

## Features

### Columns
- **Pending**: Tasks ready to start (no blockers)
- **Blocked**: Tasks waiting on dependencies
- **In Progress**: Tasks currently being worked
- **Completed**: Finished tasks

### Filters
- **Search**: Filter by subject or tag text
- **Tag**: Filter by specific tag
- **Status**: Filter by task status
- **Source**: Filter by plan seeds vs oracle issues

### Export
Click "Download markdown report" to get a summary of all tasks.

## Updating task status

The board reads from `artifacts/04-task-graph.json`. To update task status:

1. Edit the JSON directly (set `"status": "in_progress"` or `"completed"`)
2. Or use Claude Code's task management
3. Reload the board to see changes

## Next step
Use the board to track progress during `/slfg` or `/workflows:work` execution.
