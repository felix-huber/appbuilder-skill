# Beads Setup Guide — Optional Task Management

## What is Beads?

**beads_rust** (`br`) is an optional CLI task tracker that provides:
- Dependency-aware task selection (`br ready` shows unblocked tasks)
- Better visualization of task dependencies
- Task status tracking across agent sessions
- Integration with Ralph for autonomous execution

**Default alternative:** `artifacts/04-task-graph.json` works without any install.

## When to Use Beads vs Task-Graph

| Scenario | Use Task-Graph (default) | Use Beads |
|----------|--------------------------|-----------|
| Simple project (<20 tasks) | ✅ | Overkill |
| Complex dependencies | Works | ✅ Better |
| Multiple parallel agents | Works | ✅ Coordination |
| First time using Oracle Swarm | ✅ Simpler | Wait |
| Need task visualization | No | ✅ `br list --tree` |

## Installation

```bash
# Install Rust if needed
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install beads_rust
cargo install --git https://github.com/Dicklesworthstone/beads_rust.git

# Verify installation
br --version
```

## Setup in Your Project

### Step 1: Initialize beads
```bash
cd your-project
br init
```

This creates `.beads/` directory.

### Step 2: Run the setup script
After Oracle Swarm generates tasks:
```bash
bash artifacts/04-beads-setup.sh
```

This populates beads from `artifacts/04-task-graph.json`.

### Step 3: Verify tasks
```bash
# List all beads
br list

# Show as tree (dependencies)
br list --tree

# Show ready tasks (no blockers)
br ready

# Show ready tasks with JSON (for Ralph)
br ready --json
```

## How Ralph Uses Beads

When you run `./scripts/ralph.sh --beads`, Ralph:

1. **Gets next task:** `br ready --json` → returns unblocked tasks
2. **Picks first ready task** → converts to prompt format
3. **Runs agent** (Claude/Codex) with task prompt
4. **Marks complete on success:** `br complete <bead-id>`
5. **Marks failed on failure:** `br fail <bead-id>`
6. **Loops** → gets next ready task

### The Prompt Sent to Agents

```
You are an autonomous coding agent working on task: bd-a1b2c3

## Task
**Implement SQLite query parser**

## Tags
core, parser

## Description
Create a parser that handles SELECT, INSERT, UPDATE, DELETE.
Must handle JOINs and subqueries.

Deliverable: src/parser/index.ts

## Allowed Paths
Only modify files in: src/parser/

## Verification / Acceptance Criteria
- npm run test -- --grep 'parser'
- npm run typecheck

## Instructions
1. Read progress.txt for context from previous iterations
2. Implement the task following the description
3. Run the verification commands to confirm success
4. If all verifications pass, commit your changes
5. Append any learnings to progress.txt

## When Complete
Output exactly: <promise>TASK_COMPLETE</promise>
```

## Manual Bead Operations

```bash
# Create a new bead
br create "Fix login bug" -t task -p 2 --description "Auth fails on refresh"

# Add labels
br label add bd-xyz123 bug critical

# Add dependency (xyz depends on abc)
br dep add bd-xyz123 bd-abc456

# Start working on a bead
br start bd-xyz123

# Mark complete
br complete bd-xyz123

# Mark failed
br fail bd-xyz123 --reason "Blocked by API issue"

# Search beads
br search "login"

# Filter by label
br list --label bug
```

## Codex/Claude Knows Which Bead

The agent receives:
1. **Bead ID** — `bd-a1b2c3` in the prompt
2. **Full description** — Self-documenting context
3. **Allowed paths** — Where to modify
4. **Verification** — Commands to prove success

The agent doesn't need to "pick" a bead — Ralph picks based on `br ready` (dependency order).

## Example Workflow

```bash
# 1. Generate tasks from plan
/artifact-tasks

# 2. Initialize beads
br init

# 3. Populate beads from task graph
bash artifacts/04-beads-setup.sh

# 4. Review what's ready
br ready

# 5. Run autonomous implementation
./scripts/ralph.sh --beads --fresh-eyes 100

# 6. Monitor progress
br list --status
```

## Troubleshooting

### "br: command not found"
```bash
# Add cargo bin to PATH
export PATH="$HOME/.cargo/bin:$PATH"

# Or reinstall
cargo install --git https://github.com/Dicklesworthstone/beads_rust.git --force
```

### "No ready tasks" but tasks exist
```bash
# Check if dependencies are blocking
br list --tree

# Check status of blockers
br show bd-<blocker-id>

# Force a task to ready (if blocker is false positive)
br dep remove bd-child bd-blocker
```

### Task stuck in progress
```bash
# Reset to pending
br reset bd-xyz123

# Or mark as failed and retry
br fail bd-xyz123 --reason "Retry needed"
```
