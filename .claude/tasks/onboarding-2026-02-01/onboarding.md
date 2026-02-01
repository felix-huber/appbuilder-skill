# Onboarding: AppBuilder Skill (2026-02-01)

## Executive Summary

**AppBuilder Skill** is a meta-workflow framework for building applications using AI agents (Claude Code, Codex, GPT-5.2 Pro). It's not an application itself—it's a **methodology + tooling** for AI-driven software development.

Core philosophy: **"85% planning, 15% implementation"** (Doodlestein Methodology)

---

## What This Project Does

1. **Artifact-Driven Development**: Brief → PRD → UX → Plan → Tasks → Code
2. **Test-Driven Development (TDD)**: Unit test specs in each task, tests written first
3. **Oracle Review Loops**: Multi-lens GPT-5.2 Pro reviews until convergence (0 blockers/majors)
4. **Beads Task Tracking**: Git-backed issue tracker designed for AI agents
5. **Ralph Autonomous Execution**: Fire-and-forget task completion with fresh contexts
6. **Auto-PR**: Every completed task creates a PR automatically

---

## The Artifact Chain

```
00-brief.md        → Problem definition (your idea)
      ↓
01-prd.md          → Requirements + acceptance criteria
      ↓
   [oracle prd]    → GPT-5.2 Pro review (ITERATE UNTIL CONVERGENCE)
      ↓
02-ux.md           → Flows + state matrices
      ↓
   [oracle ux]     → GPT-5.2 Pro review (ITERATE UNTIL CONVERGENCE)
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
```

---

## Directory Structure (Key Files)

```
appbuilder-skill/
├── artifacts/                    # Generated documents (the artifact chain)
│   ├── 00-brief.md              # Initial idea
│   ├── 01-prd.md                # Product Requirements
│   ├── 02-ux.md                 # UX Specification
│   ├── 03-plan.md               # Implementation Plan
│   ├── 04-task-graph.json       # Compiled tasks
│   ├── 05-design/               # Design variants
│   ├── 06-oracle/               # Review feedback by phase
│   └── 07-verification.md       # Final checklist
│
├── .beads/                       # Beads task database (SQLite + logs)
│
├── .claude/commands/             # Slash commands
│   ├── guide.md                 # /guide - Where am I? What's next?
│   ├── ralph.md                 # /ralph - Autonomous execution
│   ├── oracle.md                # /oracle - Run GPT-5.2 Pro review
│   ├── plan.md                  # /plan - Generate implementation plan
│   ├── prd.md                   # /prd - Generate PRD
│   ├── ux.md                    # /ux - Generate UX spec
│   ├── sprint.md                # /sprint - Create beads from plan
│   ├── review.md                # /review - Iterative review loops
│   ├── gates.md                 # /gates - Verification checks
│   └── ship.md                  # /ship - Release planning
│
├── scripts/                      # Core automation (THE HEART)
│   ├── ralph.sh                 # Autonomous execution loop (142KB!)
│   ├── oracle_converge.sh       # Review convergence loop
│   ├── compile_task_graph.js    # Task graph compiler
│   ├── generate_beads_setup.js  # Beads setup script generator
│   └── gate_pack.sh             # Verification gates
│
├── prompts/                      # Prompt templates
│   ├── ralph/task_prompt.md     # Task agent template
│   ├── ralph/council/           # Council of Subagents (critic.md, oracle.md, synthesizer.md)
│   ├── review/beads_review.txt  # Beads review prompt (run 6-9 times!)
│   └── sprint/, prd/, ux/, code/, plan/  # Phase-specific prompts
│
├── skills/                       # Skill documentation
│   ├── phase-transitions/SKILL.md  # THE KEY PROMPTS (iteration methodology)
│   ├── oracle-integration/      # Oracle CLI wrapper
│   ├── frontend-design/         # UI design guidelines (oklch, animations)
│   └── parallel-execution/      # Dependency rules, self-healing
│
├── templates/                    # Document templates
│   ├── BRIEF.template.md        # Starting point for new projects
│   ├── PRD.template.md
│   ├── UX.template.md
│   └── PLAN.template.md
│
├── reference-specs/              # Exemplary planning documents
│   ├── USAGE.md                 # How to use reference specs
│   ├── frankentui-plan.md       # 4800 lines - ADRs, invariants
│   ├── flywheel-gateway-plan.md # 10200 lines - TypeScript/Bun platform
│   └── jeffreysprompts-webapp-plan.md  # 7300 lines - Next.js/React
│
├── CLAUDE.md                     # Agent instructions (CRITICAL)
├── AGENTS.md                     # Multi-agent coordination rules
├── tasks/todo.md                 # Session-level task tracking
└── tasks/lessons.md              # Learnings from mistakes
```

---

## Key Scripts

### `ralph.sh` — The Main Execution Loop (142KB!)

The heart of the system. Autonomous task execution with fresh AI contexts.

```bash
./scripts/ralph.sh 50                    # 50 iterations
./scripts/ralph.sh --beads 50            # Use beads for task tracking
./scripts/ralph.sh --tool smart 50       # Backend→Codex, Frontend→Claude
./scripts/ralph.sh --fresh-eyes 50       # Review after each task
./scripts/ralph.sh --tool codex 50       # Force Codex for all tasks
```

**Key Features:**
- Smart routing: backend→Codex (fast), frontend→Claude (nuanced)
- Self-healing: Auto-restarts stuck tasks after 20 minutes
- Auto-PR: Creates PR for each completed task
- Build verification: Lint, typecheck, build, test after each task
- Council review: Optional multi-agent verification (Analyst/Sentinel/Designer/Healer)
- Learning capture: Extracts LEARNING:/NOTE:/TIP: markers from agent output

### `oracle_converge.sh` — Review Convergence

Runs GPT-5.2 Pro reviews until convergence (0 blockers/majors):

```bash
./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
./scripts/oracle_converge.sh ux artifacts/02-ux.md artifacts/01-prd.md
./scripts/oracle_converge.sh plan artifacts/03-plan.md artifacts/01-prd.md artifacts/02-ux.md
```

**Takes 30-90 minutes per pass, typically 2-4 passes to converge.**

---

## Slash Commands

| Command | Purpose |
|---------|---------|
| `/guide` | Show current state and next steps |
| `/brief` | Create project brief (artifact 00) |
| `/prd` | Generate PRD from brief (artifact 01) |
| `/ux` | Generate UX spec from PRD (artifact 02) |
| `/plan` | Generate implementation plan (artifact 03) |
| `/oracle <kind>` | Run GPT-5.2 Pro review (prd/ux/plan/code) |
| `/artifact-tasks` | Compile task graph from plan + issues |
| `/sprint` | Create beads from plan |
| `/ralph` | Run autonomous execution loop |
| `/review <type>` | Run iterative review loops |
| `/gates` | Run verification checks |
| `/ship` | Create release plan |
| `/fix-ci` | Automatically fix failing CI tests |
| `/techdebt` | Scan and report technical debt |
| `/board` | Open task board UI |

---

## Iteration Requirements (NON-NEGOTIABLE!)

| Phase | Iterations Required | Convergence Criteria |
|-------|--------------------|-----------------------|
| Plan review | 4-5 passes | Suggestions become incremental |
| Beads review | 6-9 passes | No more changes |
| Fresh eyes code review | Until stable | No bugs found |
| Oracle review | Until converged | 0 new blockers/majors |

**DO NOT SKIP ITERATIONS. The extra planning time pays massive dividends during implementation.**

---

## Task Management Options

### Option 1: task-graph.json (Default, No Dependencies)
- Tasks stored in `artifacts/04-task-graph.json`
- Ralph reads/updates this file directly
- Run: `./scripts/ralph.sh 50`

### Option 2: beads_rust (More Features, Requires Cargo)
```bash
# Install
cargo install --git https://github.com/Dicklesworthstone/beads_rust.git

# Key commands
br init                    # Initialize beads
br list                    # List all tasks
br ready                   # Show tasks ready to work
br show <id>               # Show task details
br start <id>              # Start working on task
br close <id>              # Complete task
```
Run with: `./scripts/ralph.sh --beads 50`

---

## Critical Rules (From CLAUDE.md)

### Rule 1: Never Delete Files Without Permission
Ask first, always. Even files you created.

### Rule 2: No File Proliferation
Revise existing files. Never create `file_v2.js`, `file_improved.js`, etc.

### Rule 3: No Automated Code Transforms
Make changes manually. Use subagents in parallel for many simple changes.

### Rule 4: Simplicity
> "Would a senior engineer say this is overcomplicated? If yes, simplify."

### Rule 5: No Laziness
Find root causes. No temporary fixes. Minimal impact.

---

## Non-Negotiables

1. **Browser Oracle only** — Never API mode for GPT-5.2 Pro
2. **Artifacts are truth** — Update `artifacts/` before code
3. **No evidence = not done** — Show commands + outputs
4. **Task graph is truth** — Explicit dependencies via beads or task-graph.json
5. **Iterate until convergence** — Reviews run multiple times
6. **Backpressure required** — Tasks must have verification

---

## Tool Routing (Smart Mode)

| Task Type | Tool | Why |
|-----------|------|-----|
| Backend (core, api, data, worker, db) | Codex | Fast iteration |
| Frontend (ui, components, design, css) | Claude Code | Nuanced implementation |
| Heavy doc reviews (PRD, UX, Plan) | GPT-5.2 Pro | Deep reasoning via Oracle |

---

## Current State

### Artifacts Present:
- `artifacts/05-design/` — Design variants
- `artifacts/07-verification.md` — Verification checklist
- `artifacts/08-execution-summary.md` — Execution summary
- `artifacts/workflow-improvements-plan.md` — Improvement planning

### Beads State:
- `.beads/beads.db` — 176KB SQLite database (has tasks)
- `.beads/logs/` — Empty (no execution logs)

### Git Status:
- Many modified files in `.claude/commands/`, `prompts/`, `scripts/`, `skills/`
- New untracked files in `artifacts/`, `prompts/`, `reference-specs/`, `tasks/`

---

## Quick Reference: Starting a New Project

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

# 9. Run autonomous execution
./scripts/ralph.sh --fresh-eyes 100
```

---

## Key Files to Read First

1. **CLAUDE.md** — Agent instructions (loaded into every session)
2. **skills/phase-transitions/SKILL.md** — THE actual prompts (the magic)
3. **scripts/ralph.sh** — The autonomous execution loop
4. **prompts/ralph/task_prompt.md** — Task agent template
5. **prompts/ralph/council/critic.md** — Council review pattern

---

## Session Best Practices

### At Session Start:
1. Check `tasks/todo.md` for incomplete work
2. Read `tasks/lessons.md` for patterns to avoid
3. Run `/guide` to see current state

### During Session:
1. For non-trivial tasks (3+ steps), write plan to `tasks/todo.md` first
2. Get user approval before implementing
3. Track progress by checking off items
4. If things go sideways: STOP, document in `tasks/lessons.md`, re-plan

### At Session End:
1. File issues for remaining work
2. Run quality gates if code changed
3. **PUSH TO REMOTE** (mandatory):
   ```bash
   git pull --rebase
   git add .
   git commit -m "Session update"
   git push
   ```
4. Update issue status

**NEVER stop before pushing — that leaves work stranded locally.**

---

## Task Agent Workflow (From task_prompt.md)

When implementing a task:

1. **TDD Workflow (if applicable)**:
   - Create test file FIRST
   - Write tests based on acceptance criteria
   - Run tests - they should FAIL (red phase)
   - Implement code to make tests pass (green phase)
   - Refactor if needed

2. **Standard Workflow**:
   - Read `progress.txt` for learnings from previous tasks
   - Examine all relevant files & dependencies first
   - Implement changes for ALL acceptance criteria
   - **INTEGRATION CHECK**: Trace user flow end-to-end
   - Run verification commands
   - **Self-review with fresh eyes (4 PASSES!)**

3. **On Completion**:
   ```xml
   <promise>TASK_COMPLETE</promise>
   ```
   Then include: Files modified, LEARNING: markers

4. **If Blocked**:
   ```xml
   <promise>TASK_BLOCKED</promise>
   ```
   Then include: Blocker description, what was attempted, what's needed

---

## Council of Subagents (Optional Advanced Review)

When `--council-review` is enabled, Ralph uses multi-agent verification:

| Role | Focus |
|------|-------|
| **Analyst** | Correctness, architecture, performance |
| **Sentinel** | Anti-patterns, security, reliability |
| **Designer** | UI/UX, accessibility, user experience |
| **Healer** | Fixes issues, re-runs verification |

Proposals are then critiqued by the **Critic** (prompts/ralph/council/critic.md) for blind peer review.

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
npm run board         # Open task board (http://localhost:8080)
```

---

## Debugging Ralph

```bash
# See task status (task-graph mode)
cat artifacts/04-task-graph.json | jq '.tasks[] | {id, subject, status, tags}'

# See task status (beads mode)
br list --json | jq '.[] | {id, title, status}'

# See ready tasks
br ready

# See learnings
cat progress.txt

# Check git history
git log --oneline -20

# See last prompt sent to AI
cat /tmp/ralph-prompt-*.md
```

---

## Recovery: When Things Go Sideways

**Detection Signals:**
- Tests keep failing unexpectedly
- Implementation feels hacky
- Scope is expanding
- You're unsure which direction to go
- Same bug keeps coming back

**Recovery Steps:**
1. STOP — Don't push through
2. Document what went wrong in `tasks/lessons.md`
3. Write new plan in `tasks/todo.md`
4. Only proceed when the new plan is clear

---

## Summary

AppBuilder Skill transforms AI-driven development from chaotic to systematic:

1. **Artifacts provide truth** — No guessing about what to build
2. **Oracle ensures quality** — GPT-5.2 Pro catches issues before implementation
3. **Ralph executes autonomously** — Fire-and-forget task completion
4. **Fresh eyes catch bugs** — Self-review after every task
5. **Iteration is mandatory** — Plan review 4-5x, beads review 6-9x, Oracle until converged

The core insight: **Spend 85% of time planning, 15% implementing. Iterate reviews until stable. Fresh eyes after every task.**
