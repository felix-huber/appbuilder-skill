# /ralph — Run Autonomous Execution Loop

## Goal
Execute tasks autonomously using the Ralph pattern - fresh AI agent context each iteration, memory via git + progress.txt.

## Prerequisites
- At least one AI coding tool installed:
  - **Claude Code CLI**: `npm install -g @anthropic-ai/claude-code`
  - **Codex CLI**: `npm install -g @openai/codex` or from https://github.com/openai/codex
- `jq` installed (`brew install jq`)
- Git repository initialized
- Task source (one of):
  - `artifacts/04-task-graph.json` (default, run `/artifact-tasks` first)
  - **Beads** (`br`) for task tracking (`cargo install --git https://github.com/Dicklesworthstone/beads_rust.git`)

---

## ⚠️ CHECK EXISTING STATE FIRST

**Before starting Ralph, check execution state:**

```bash
# Check task source
ls -la artifacts/04-task-graph.json 2>/dev/null
cat progress.txt 2>/dev/null | tail -20

# If using beads
br list --json 2>/dev/null | jq 'length'
br ready --json 2>/dev/null | jq 'length'

# Check for in-progress work
git status --short
```

| Situation | Action |
|-----------|--------|
| No task graph or beads | → Run `/artifact-tasks` first |
| Tasks in progress (dirty git) | → Complete current task first |
| `progress.txt` shows partial work | → Ralph will resume automatically |
| All tasks complete | → Run `/gates` for verification |

---

## CLI Flags Reference

### Claude Code
```bash
claude -p --dangerously-skip-permissions "<prompt>"
```
- `-p` / `--print`: Non-interactive mode, output to stdout
- `--dangerously-skip-permissions`: Skip all approval prompts (YOLO mode)

### Codex CLI
```bash
codex exec --yolo "<prompt>"
```
- `exec` / `e`: Non-interactive execution mode
- `--yolo`: Skip approvals and sandbox (alias for `--dangerously-bypass-approvals-and-sandbox`)
- Alternative: `--full-auto` (safer, keeps sandbox but auto-approves)

## Usage

```bash
# Basic usage (default: smart routing, 20 iterations)
./scripts/ralph.sh

# Set max iterations
./scripts/ralph.sh 50

# Use specific tool
./scripts/ralph.sh --tool claude 50    # Claude Code
./scripts/ralph.sh --tool codex 50     # Codex CLI

# Smart routing: backend→Codex, frontend→Claude
./scripts/ralph.sh --tool smart 50

# Ask which tool for each task (interactive)
./scripts/ralph.sh --ask 50

# Use beads for task management
./scripts/ralph.sh --beads 50

# Combine options
./scripts/ralph.sh --tool smart --beads 100
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `--tool <claude\|codex\|smart>` | AI tool to use (default: smart) |
| `--ask` | Ask which tool for each task (interactive) |
| `--backend-tool <tool>` | Tool for backend/API tasks (default: codex) |
| `--frontend-tool <tool>` | Tool for UI/frontend tasks (default: claude) |
| `--beads` | Force beads_rust (`br`) for task management |
| `--no-beads`, `--graph` | Force task-graph.json for task management |
| `--fresh-eyes` | Enable fresh-eyes code review after each task |
| `--no-self-heal` | Disable auto-recovery of stuck tasks |
| `--stall-threshold <min>` | Minutes before task is stuck (default: 20) |
| `--auto-pr` | Enable auto-PR creation (default: on) |
| `--no-auto-pr` | Disable auto-PR creation |
| `--pr-base <branch>` | Base branch for PRs (default: main) |
| `--no-devin` | Disable Devin AI code review |
| `-h, --help` | Show help |
| `<number>` | Max iterations (default: 20) |

## Self-Healing (enabled by default)

Ralph monitors task execution and auto-recovers stuck tasks:
- If a task runs longer than STALL_THRESHOLD (default: 20 minutes) → reset and retry
- Failed tasks are retried with different approach hints
- Max 3 self-heal attempts before marking as failed
- Disable with `--no-self-heal`

## Auto-PR (enabled by default)

After each completed task, Ralph will:
1. Create a feature branch: `task/<task-id>`
2. Commit changes with descriptive message
3. Create a PR against PR_BASE_BRANCH

**Requires:** gh CLI (`brew install gh && gh auth login`)

Disable with `--no-auto-pr`

## Learnings Capture

Ralph records learnings from each task to `learnings.md`:
- Task execution details
- Extracts LEARNING:/NOTE:/INSIGHT:/TIP: markers from agent output
- Tracks patterns for improving future prompts

## Task Source Selection

By default, Ralph auto-detects available task sources:

| Situation | Behavior |
|-----------|----------|
| Both `.beads/` and `task-graph.json` exist | Interactive prompt asks which to use |
| Only `.beads/` exists | Auto-selects beads_rust |
| Only `task-graph.json` exists | Auto-selects task-graph |
| Neither exists | Shows setup instructions |

Use `--beads` or `--no-beads` to skip interactive selection.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAUDE_CMD` | Custom Claude Code command (default: `claude -p --dangerously-skip-permissions`) |
| `CODEX_CMD` | Custom Codex command (default: `codex exec --yolo`) |
| `FRESH_EYES` | `"true"` to enable fresh-eyes review |
| `SELF_HEAL` | `"false"` to disable self-healing |
| `STALL_THRESHOLD` | Minutes before task is stuck (default: 20) |
| `AUTO_PR` | `"false"` to disable auto-PR |
| `PR_BASE_BRANCH` | Base branch for PRs (default: main) |
| `DEVIN_REVIEW` | `"false"` to disable Devin review |

Example:
```bash
export CODEX_CMD="codex exec --full-auto"  # Safer mode with sandbox
export AUTO_PR="true"                       # Enable auto-PR
export PR_BASE_BRANCH="develop"             # PR against develop branch
./scripts/ralph.sh --tool codex 50
```

## Smart Routing

When using `--tool smart`, Ralph routes tasks based on their tags:

| Task Tags | Routed To |
|-----------|-----------|
| `ui`, `components`, `frontend`, `design`, `css`, `styles`, `layout`, `view` | Frontend tool (Claude) |
| `core`, `engine`, `api`, `backend`, `data`, `worker`, `db`, `database`, `server` | Backend tool (Codex) |
| Both frontend + backend tags | Frontend tool (safer for UI) |
| Unknown tags | Claude (default) |

## Beads Integration

[Beads](https://github.com/Dicklesworthstone/beads_rust) is a git-backed issue tracker designed for AI agents.

### Setup
```bash
# Install beads
cargo install --git https://github.com/Dicklesworthstone/beads_rust.git
# Or: cargo install beads_rust

# Initialize in your project
cd your-project
br init
```

### Usage with Ralph
```bash
# Create tasks in beads
br create "Implement authentication" -t task -p 1
br create "Build login UI" -t task -p 2

# Run Ralph with beads
./scripts/ralph.sh --beads 50
```

### How it works
- Tasks fetched via: `br ready --json` (returns tasks with no blockers)
- Task completion via: `br close <id>`
- Task failure via: `br update <id> --status blocked`

## How Ralph Works

```
┌─────────────────────────────────────────────────────────────┐
│                    ralph.sh loop                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Spawn fresh AI agent instance (Claude/Codex)            │
│     ↓                                                       │
│  2. Get next ready task (task-graph.json or br ready)       │
│     ↓                                                       │
│  3. Read progress.txt → learn from previous iterations      │
│     ↓                                                       │
│  4. Implement the task                                      │
│     ↓                                                       │
│  5. Run verification commands                               │
│     ↓                                                       │
│  6. If passing: commit, mark task completed                 │
│     ↓                                                       │
│  7. Append learnings to progress.txt                        │
│     ↓                                                       │
│  8. Repeat until all tasks done or max iterations           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Full Workflow

```
/brief          → Create project brief
    ↓
/prd            → Generate PRD
    ↓
/oracle prd     → Review PRD with 8 lenses
    ↓
/ux             → Generate UX spec
    ↓
/oracle ux      → Review UX
    ↓
/plan           → Create implementation plan with task seeds
    ↓
/oracle plan    → Review plan
    ↓
/artifact-tasks → Compile task graph with verification
    ↓
./scripts/ralph.sh --tool smart 100   # Autonomous execution
    ↓
/gates          → Final verification
    ↓
/ship           → Release plan
```

## Task Status Flow

```
pending → in_progress → completed
                     ↘ failed
```

## Debugging

```bash
# See task status (task-graph mode)
cat artifacts/04-task-graph.json | jq '.tasks[] | {id, subject, status, tags}'

# See task status (beads mode)
br list --json | jq '.[] | {id, title, status}'

# See ready tasks (beads)
br ready

# See learnings
cat progress.txt

# Check git history
git log --oneline -20

# See last prompt sent to AI
cat /tmp/ralph-prompt-*.md
```

## Tips

### Run Overnight with Smart Routing
```bash
./scripts/ralph.sh --tool smart 100 > ralph.log 2>&1 &
tail -f ralph.log
```

### Use Beads for Better Task Tracking
```bash
# Initialize beads
br init

# Import from your plan (or ask AI to create tasks)
# Then run with beads
./scripts/ralph.sh --beads --tool smart 100
```

### Recovery from Failures
```bash
# Task-graph mode: manually mark task complete
jq '.tasks = [.tasks[] | if .id == "T-xxx" then .status = "completed" else . end]' \
  artifacts/04-task-graph.json > tmp && mv tmp artifacts/04-task-graph.json

# Beads mode: close the task
br close bd-xxxx --reason "manually completed"

# Resume
./scripts/ralph.sh
```

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [snarktank/ralph](https://github.com/snarktank/ralph)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
- [OpenAI Codex CLI](https://github.com/openai/codex)
- [Beads issue tracker](https://github.com/Dicklesworthstone/beads_rust)
