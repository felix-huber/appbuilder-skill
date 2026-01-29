# Onboarding: AppBuilder Skill

## What Is This Project?

**AppBuilder Skill** is a complete AI-driven application development workflow/skill for Claude Code and Codex. It implements an **artifact-driven development process** with:

1. **Test-Driven Development (TDD)** — Unit test specs in each task, tests written first
2. **Oracle Review Loops** — Multi-lens GPT-5.2 Pro reviews until convergence (0 blockers/majors)
3. **Beads Task Tracking** — Git-backed issue tracker designed for AI agents
4. **Ralph Autonomous Execution** — Fire-and-forget task completion with fresh contexts
5. **Auto-PR** — Every completed task creates a PR automatically

This is essentially a "meta-tool" — it's not an application itself, but a **workflow framework for building applications using AI agents**.

---

## Core Philosophy: The Doodlestein Methodology

This project is heavily inspired by Jeffrey Emanuel's (@doodlestein) methodology:

> "Planning tokens are a lot fewer and cheaper than implementation tokens. Even a very big, complex markdown plan is shorter than a few substantive code files."

**Key principles:**
- **85% planning, 15% implementation** — Spend most time in "plan space"
- **Iterate until convergence** — Run reviews 4-9 times, not once
- **Fresh eyes** — Review code after each task with fresh context
- **Multi-model ensemble** — Use different models for different strengths (Claude for nuanced work, Codex for fast iteration, GPT-5.2 Pro for deep reviews)

---

## The Artifact Chain

The workflow progresses through these artifacts in order:

```
00-brief.md        → Problem definition (templates/BRIEF.template.md)
      ↓
01-prd.md          → Requirements + acceptance criteria
      ↓
   [oracle prd]    → GPT-5.2 Pro review (ITERATE UNTIL CONVERGENCE)
      ↓
02-ux.md           → Flows + state matrices
      ↓
   [oracle ux]     → GPT-5.2 Pro review (ITERATE UNTIL CONVERGENCE)
      ↓
05-design/*        → UI exploration (optional)
      ↓
03-plan.md         → Architecture + SPRINT-ORGANIZED task seeds
      ↓
   [oracle plan]   → GPT-5.2 Pro review (ITERATE UNTIL CONVERGENCE)
      ↓
04-task-graph.json → Compiled tasks with dependencies
      ↓
   [code]          → Implementation via Ralph autonomous loop
      ↓
06-oracle/code/*   → Code review (ITERATE UNTIL CONVERGENCE)
      ↓
07-verification.md → Gate results
      ↓
08-release.md      → Rollout plan
      ↓
09-retro.md        → Learnings
```

**Critical Rule**: Each Oracle review phase must iterate until issues converge to zero (or stable: 0 blockers, ≤2 majors). DO NOT proceed to the next phase until converged.

---

## Directory Structure

```
appbuilder-skill/
├── artifacts/                    # Generated documents (the artifact chain)
│   ├── 00-brief.md              # Initial idea
│   ├── 01-prd.md                # Product Requirements
│   ├── 02-ux.md                 # UX Specification
│   ├── 03-plan.md               # Implementation Plan
│   ├── 04-task-graph.json       # Compiled tasks
│   ├── 05-design/               # Design variants (keystone, tasteboard)
│   ├── 06-oracle/               # Review feedback organized by phase
│   │   ├── prd/                 # PRD reviews
│   │   ├── ux/                  # UX reviews
│   │   ├── plan/                # Plan reviews
│   │   └── code/                # Code reviews
│   └── 07-verification.md       # Final checklist
│
├── .beads/                       # Beads task database (if using beads)
│   ├── issues/                  # Task files
│   └── logs/                    # Per-task execution logs
│
├── .claude/
│   └── commands/                # Slash commands (/guide, /prd, /ux, etc.)
│
├── scripts/                      # Core automation scripts
│   ├── ralph.sh                 # Autonomous execution loop (THE MAIN SCRIPT)
│   ├── oracle_converge.sh       # Review convergence loop
│   ├── compile_task_graph.js    # Task graph compiler
│   ├── generate_beads_setup.js  # Creates beads setup script
│   ├── gate_pack.sh             # Pre-commit verification gates
│   └── ...
│
├── prompts/                      # Prompt templates by phase
│   ├── code/                    # Code review lenses
│   ├── plan/                    # Plan review lenses
│   ├── prd/                     # PRD review lenses
│   ├── ux/                      # UX review lenses
│   ├── ralph/                   # Task agent prompts
│   ├── review/                  # Fresh eyes, beads review
│   └── sprint/                  # Sprint decomposition
│
├── skills/                       # Skill documentation
│   ├── agent-browser/           # Browser automation patterns
│   ├── artifact-workflow/       # Artifact chain management
│   ├── frontend-design/         # UI design guidelines (oklch colors, animations)
│   ├── oracle-integration/      # Oracle CLI wrapper
│   ├── parallel-execution/      # Dependency rules, self-healing
│   ├── phase-transitions/       # THE KEY PROMPTS (iteration methodology)
│   ├── review-loops/            # Review iteration patterns
│   └── ui-exploration/          # Tasteboard, keystone, variants
│
├── templates/                    # Document templates
│   ├── BRIEF.template.md        # Starting point for new projects
│   ├── PRD.template.md
│   ├── UX.template.md
│   └── PLAN.template.md
│
├── tools/                        # Web-based tools
│   ├── task-board/              # Task visualization
│   ├── design-gallery/          # Design variant gallery
│   └── tasteboard/              # Design reference board
│
├── docs/                         # Additional documentation
│   ├── BEADS_SETUP.md           # Beads configuration
│   ├── MULTI_AGENT_COORDINATION.md  # MCP Agent Mail for parallel agents
│   ├── TASK_GRAPH_SCHEMA.md     # Task graph JSON schema
│   └── ...
│
├── CLAUDE.md                     # Agent instructions (loaded into context)
├── AGENTS.md                     # Multi-agent coordination rules
├── README.md                     # Project overview
└── package.json                  # npm scripts for common operations
```

---

## Key Scripts

### `ralph.sh` — The Main Execution Loop

This is **the heart of the system**. It runs autonomous execution:

```bash
# Basic usage
./scripts/ralph.sh 50                    # 50 iterations

# With beads
./scripts/ralph.sh --beads 50            # Use beads for task tracking

# Smart routing (default)
./scripts/ralph.sh --tool smart 50       # Backend→Codex, Frontend→Claude

# With fresh eyes review
./scripts/ralph.sh --fresh-eyes 50       # Review code after each task

# Cross-model review
./scripts/ralph.sh --review-tool codex 50  # Code with Claude, review with Codex

# Disable auto-PR
./scripts/ralph.sh --no-auto-pr 50
```

**How it works:**
1. Gets next task from `task-graph.json` or `br ready`
2. Spawns a fresh AI agent (Claude or Codex)
3. Agent implements the task
4. (Optional) Fresh eyes review
5. Creates PR automatically
6. Marks task complete
7. Repeat

### `oracle_converge.sh` — Review Convergence

Runs GPT-5.2 Pro reviews until convergence:

```bash
./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
./scripts/oracle_converge.sh ux artifacts/02-ux.md artifacts/01-prd.md
./scripts/oracle_converge.sh plan artifacts/03-plan.md artifacts/01-prd.md artifacts/02-ux.md
```

**Takes 30-90 minutes per pass, typically 2-4 passes to converge.**

### `compile_task_graph.js` — Task Graph Compiler

Compiles tasks from plan + Oracle issues into `04-task-graph.json`:

```bash
node scripts/compile_task_graph.js --plan artifacts/03-plan.md \
  --issues artifacts/06-oracle/plan/issues.json \
  --out artifacts/04-task-graph.json
```

### `generate_beads_setup.js` — Beads Setup Script

Generates `04-beads-setup.sh` from the task graph:

```bash
node scripts/generate_beads_setup.js
bash artifacts/04-beads-setup.sh  # Creates beads in .beads/
```

---

## Slash Commands

Available via `/command` in Claude Code:

| Command | Purpose |
|---------|---------|
| `/guide` | Show current state and next steps |
| `/brief` | Create problem brief (artifact 00) |
| `/prd` | Generate PRD from brief (artifact 01) |
| `/ux` | Generate UX spec from PRD (artifact 02) |
| `/ui` | UI exploration: tasteboard + keystone + variants |
| `/plan` | Generate implementation plan with SPRINTS (artifact 03) |
| `/oracle <kind>` | Run GPT-5.2 Pro review (prd/ux/plan/code) |
| `/artifact-tasks` | Compile task graph from plan + issues |
| `/sprint` | Create beads from plan |
| `/ralph` | Run autonomous execution loop |
| `/review <type>` | Run iterative review loops |
| `/board` | Open task board UI |
| `/swarm-status` | Report swarm health |
| `/gates` | Run verification checks |
| `/ship` | Create release plan |
| `/retro` | Capture learnings |
| `/combined-lfg` | Full integrated workflow |

---

## Task Management Options

### Option 1: task-graph.json (Built-in, No Dependencies)

- Tasks stored in `artifacts/04-task-graph.json`
- Ralph reads/updates this file directly
- Run: `./scripts/ralph.sh 50`

### Option 2: beads_rust (More Features, Requires Cargo)

```bash
# Install
cargo install --git https://github.com/Dicklesworthstone/beads_rust.git

# Initialize
br init

# Key commands
br list                    # List all tasks
br ready                   # Show tasks ready to work
br show <id>               # Show task details
br start <id>              # Start working on task
br close <id>              # Complete task
```

Run with: `./scripts/ralph.sh --beads 50`

---

## The Key Skills

### `skills/phase-transitions/SKILL.md`

**THE MOST IMPORTANT FILE** — Contains the exact prompts for each phase:

1. **Plan Creation Prompts** — Multi-model (ChatGPT Pro + Claude Opus + synthesis)
2. **Plan → Beads Prompts** — Transformation prompts
3. **Beads Review Prompt** — Run 6-9 times!
4. **Fresh Eyes Prompt** — Run after every task until no bugs found
5. **Cross-Agent Review** — Different model perspective

**Key iteration requirements:**
- Plan review: 4-5 passes
- Beads review: 6-9 passes
- Fresh eyes: Until no bugs found
- Oracle review: Until converged (0 blockers/majors)

### `skills/oracle-integration/SKILL.md`

Oracle CLI integration:
- Browser mode only (uses ChatGPT session)
- 8 specialized lenses: product, ux, architecture, security, performance, tests, simplicity, ops
- Structured output: issues.json with consistent schema

### `skills/frontend-design/SKILL.md`

Frontend design guidelines:
- ASCII wireframes before coding
- oklch() colors (never generic Bootstrap blue)
- Animation micro-syntax
- Modern font recommendations
- Theme patterns (dark mode, light mode, brutalism, glassmorphism)

---

## Iteration Requirements (NON-NEGOTIABLE)

| Phase | Iterations | Convergence Criteria |
|-------|------------|---------------------|
| Plan review | 4-5 passes | Suggestions become incremental |
| Beads review | 6-9 passes | No more changes |
| Fresh eyes | Until stable | No bugs found |
| Oracle review | Until converged | 0 new blockers/majors |

---

## Critical Rules (From CLAUDE.md)

1. **Never delete files without permission** — Even files you created
2. **No file proliferation** — Never create `file_v2.js`, `file_improved.js`, etc. Revise in place.
3. **No automated code transforms** — Never run scripts that process/change code files
4. **Simplicity check** — "Would a senior engineer say this is overcomplicated? If yes, simplify."
5. **Oracle convergence** — Every Oracle review must iterate until 0 blockers/majors
6. **Clean shutdown** — Always push to remote before ending session

---

## Tool Routing (Smart Mode)

By default, Ralph routes tasks by type:

| Task Type | Tool | Why |
|-----------|------|-----|
| Backend (core, api, data, worker, db) | Codex | Fast iteration |
| Frontend (ui, components, design, css) | Claude Code | Nuanced implementation |
| Heavy doc reviews (PRD, UX, Plan) | GPT-5.2 Pro | Deep reasoning via Oracle |

---

## npm Scripts

```bash
npm run oracle:prd    # Review PRD
npm run oracle:ux     # Review UX
npm run oracle:plan   # Review Plan
npm run tasks         # Compile task graph
npm run beads         # Generate beads setup script
npm run ralph         # Run Ralph (task-graph mode)
npm run ralph:beads   # Run Ralph (beads mode)
npm run gates         # Run verification gates
npm run status        # Show swarm status
npm run board         # Open task board
npm run tasteboard    # Open design reference board
npm run gallery       # Open design gallery
```

---

## Prerequisites

Required tools:
1. **Claude Code CLI**: `npm install -g @anthropic-ai/claude-code`
2. **jq**: `brew install jq` (JSON processing)
3. **Node.js 18+**

Optional:
4. **beads_rust**: `cargo install --git https://github.com/Dicklesworthstone/beads_rust.git`
5. **GitHub CLI**: `brew install gh && gh auth login` (for auto-PR)
6. **DCG (destructive command guard)**: Prevents AI from running destructive commands

---

## Quick Start Workflow

```bash
# 1. Create brief
cp templates/BRIEF.template.md artifacts/00-brief.md
# Edit artifacts/00-brief.md with your app idea

# 2. Generate PRD
claude "/prd"

# 3. Run Oracle convergence on PRD (30-90 min × 2-4 rounds)
./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md

# 4. Generate UX spec
claude "/ux"

# 5. Run Oracle convergence on UX
./scripts/oracle_converge.sh ux artifacts/02-ux.md artifacts/01-prd.md

# 6. Generate plan
claude "/plan"

# 7. Run Oracle convergence on plan
./scripts/oracle_converge.sh plan artifacts/03-plan.md artifacts/01-prd.md artifacts/02-ux.md

# 8. Compile task graph
claude "/artifact-tasks"

# 9. (Optional) Set up beads
bash artifacts/04-beads-setup.sh

# 10. Run autonomous execution
./scripts/ralph.sh --fresh-eyes 100  # or --beads for beads mode
```

---

## Multi-Agent Coordination (Advanced)

For running 2+ parallel agents, use MCP Agent Mail:
- Each agent gets an identity (e.g., "FrontendFalcon", "BackendBear")
- File reservations prevent conflicts
- Inbox/outbox for agent communication

See `docs/MULTI_AGENT_COORDINATION.md` for details.

---

## Key Files to Understand

1. **CLAUDE.md** — Instructions loaded into every Claude Code session
2. **AGENTS.md** — Multi-agent coordination rules
3. **skills/phase-transitions/SKILL.md** — THE prompts (the magic)
4. **scripts/ralph.sh** — The autonomous execution loop
5. **scripts/oracle_converge.sh** — Review convergence
6. **templates/BRIEF.template.md** — Starting point for new projects

---

## Session Completion (Landing the Plane)

When ending a work session:

1. **File issues** for remaining work
2. **Run quality gates** if code changed
3. **Update issue status**
4. **PUSH TO REMOTE** (MANDATORY):
   ```bash
   git pull --rebase
   br sync --flush-only  # If using beads
   git add .beads/ && git commit -m "Update beads"
   git push
   git status  # Must show "up to date with origin"
   ```
5. **Clean up** stashes, prune remote branches
6. **Hand off** context for next session

**NEVER stop before pushing — that leaves work stranded locally.**

---

## Summary

AppBuilder Skill is a meta-workflow that:
1. Takes a brief (your idea)
2. Progressively refines it through PRD → UX → Plan artifacts
3. Reviews each with Oracle (GPT-5.2 Pro) until converged
4. Compiles into executable tasks
5. Runs Ralph to implement autonomously
6. Creates PRs automatically

The core insight: **Spend 85% of time planning, 15% implementing. Iterate reviews until stable. Fresh eyes after every task.**
