# AppBuilder Skill

AI-driven application development with Test-Driven Development, automated review loops, and autonomous task execution.

## What This Is

A complete skill/workflow for building applications using AI agents (Claude Code, Codex) with:

- **Artifact-Driven Development**: Brief → PRD → UX → Plan → Tasks → Code
- **Test-Driven Development (TDD)**: Unit test specs in each task, tests written first
- **Oracle Review Loops**: Multi-lens AI review until convergence (0 blockers/majors)
- **Beads Task Tracking**: Git-backed issue tracker designed for AI agents
- **Ralph Autonomous Execution**: Fire-and-forget task completion with fresh contexts
- **Auto-PR & Devin Review**: Every task → PR → AI code review

## Prerequisites

### Required Tools

```bash
# 1. Claude Code CLI
npm install -g @anthropic-ai/claude-code

# 2. Beads (git-backed task tracker for AI agents)
cargo install --git https://github.com/Dicklesworthstone/beads_rust.git

# 3. GitHub CLI (for auto-PR creation)
brew install gh
gh auth login

# 4. jq (JSON processing)
brew install jq  # macOS
apt install jq   # Linux

# 5. Node.js 18+
node --version  # Should be >= 18.0.0
```

### Recommended: DCG Safety Tool

Prevents AI agents from running destructive commands:

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/master/install.sh?$(date +%s)" | bash
```

Blocks: `git reset --hard`, `git clean -f`, `rm -rf` outside temp dirs, etc.

## Quick Start

```bash
# 1. Clone and setup
git clone https://github.com/felix-huber/appbuilder-skill.git
cd appbuilder-skill

# 2. Initialize beads
br init

# 3. Create your brief
cp templates/BRIEF.template.md artifacts/00-brief.md
# Edit artifacts/00-brief.md with your app idea

# 4. Run the full pipeline
claude "/guide"  # Shows all available commands

# Or step by step:
claude "/prd"      # Generate PRD from brief
claude "/ux"       # Generate UX spec from PRD
claude "/plan"     # Generate implementation plan
claude "/sprint"   # Create beads from plan
./scripts/ralph.sh --beads 50  # Execute autonomously
```

## The Full Workflow (A → Z)

### Phase 1: Specification

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  00-brief.md    │ ──▶ │   01-prd.md     │ ──▶ │   02-ux.md      │
│  (Your idea)    │     │  (Requirements) │     │  (UX Spec)      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
         │                       │                       │
         └───────────────────────┴───────────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │      /oracle prd        │
                    │      /oracle ux         │
                    │   (Review until 0 bugs) │
                    └─────────────────────────┘
```

### Phase 2: Planning

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   02-ux.md      │ ──▶ │  03-plan.md     │ ──▶ │  .beads/        │
│                 │     │  (Sprints/Tasks)│     │  (Task tracker) │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                 │
                    ┌────────────▼────────────┐
                    │      /oracle plan       │
                    │   (Review until 0 bugs) │
                    └─────────────────────────┘
```

### Phase 3: Execution (Ralph Loop)

```
┌─────────────────────────────────────────────────────────────────┐
│                      RALPH AUTONOMOUS LOOP                       │
│                                                                  │
│   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│   │ Get Next │ ─▶ │  Spawn   │ ─▶ │  Create  │ ─▶ │  Devin   │  │
│   │   Task   │    │  Agent   │    │    PR    │    │  Review  │  │
│   └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│        ▲                                               │         │
│        └───────────────────────────────────────────────┘         │
│                    (Repeat until all tasks done)                 │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 4: Review & Ship

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Code Complete  │ ──▶ │  /review        │ ──▶ │  /ship          │
│                 │     │  (Final checks) │     │  (Release)      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

## Test-Driven Development (TDD)

Every feature bead includes **Unit Test Specs** that agents write FIRST:

```markdown
## bd-abc: Implement user store

UNIT TEST SPECS (write these FIRST):
```typescript
describe('userStore', () => {
  it('starts with empty users array')
  it('addUser appends to users')
  it('removeUser filters out by id')
  it('getUser returns user by id or undefined')
})
```

ACCEPTANCE CRITERIA:
- [ ] Unit tests written first (TDD)
- [ ] All unit tests pass
- [ ] Implementation complete
```

### Test Pyramid

```
        ┌───────────────────┐
        │    E2E Tests      │  ← Separate beads (depend on features)
        │  (User flows)     │
        └───────────────────┘
       ┌─────────────────────┐
       │  Integration Tests  │  ← Separate beads (test contracts)
       │  (API contracts)    │
       └─────────────────────┘
      ┌───────────────────────┐
      │     Unit Tests        │  ← Inside feature beads (TDD)
      │  (Functions/Classes)  │
      └───────────────────────┘
```

## GitHub Integration

### Prerequisites

```bash
# Authenticate with GitHub
gh auth login

# Verify authentication
gh auth status

# Set up git remote (if not already)
git remote add origin https://github.com/felix-huber/appbuilder-skill.git
```

### Auto-PR Flow

When Ralph completes a task:

1. **Creates branch**: `task/bd-xyz`
2. **Commits changes**: `feat(bd-xyz): Task subject`
3. **Pushes to origin**: `git push -u origin task/bd-xyz`
4. **Creates PR**: Via `gh pr create`
5. **Triggers Devin Review**: AI code review on the PR

### Devin Review

After all tasks complete, Ralph triggers Devin AI review:

```bash
# Manual trigger
npx devin-review

# Or via web
# https://devin.ai/felix-huber/appbuilder-skill/pull/123
```

## Directory Structure

```
appbuilder-skill/
├── artifacts/                    # Generated documents
│   ├── 00-brief.md              # Your initial idea
│   ├── 01-prd.md                # Product Requirements
│   ├── 02-ux.md                 # UX Specification
│   ├── 03-plan.md               # Implementation Plan
│   ├── 04-task-graph.json       # Compiled tasks
│   ├── 05-design/               # Design variants
│   ├── 06-oracle/               # Review feedback
│   │   ├── prd/                 # PRD reviews
│   │   ├── ux/                  # UX reviews
│   │   ├── plan/                # Plan reviews
│   │   └── code/                # Code reviews
│   └── 07-verification.md       # Final checklist
├── .beads/                       # Beads task database
│   ├── issues/                  # Task files
│   └── logs/                    # Per-task execution logs
├── .claude/
│   └── commands/                # Slash commands
│       ├── guide.md             # /guide - Show all commands
│       ├── prd.md               # /prd - Generate PRD
│       ├── ux.md                # /ux - Generate UX spec
│       ├── plan.md              # /plan - Generate plan
│       ├── sprint.md            # /sprint - Create beads
│       ├── oracle.md            # /oracle - Run reviews
│       ├── ralph.md             # /ralph - Autonomous execution
│       ├── review.md            # /review - Final review
│       └── ship.md              # /ship - Release
├── prompts/                      # Prompt templates
│   ├── sprint/
│   │   ├── decompose.txt        # Sprint decomposition
│   │   └── to_beads.txt         # Convert to beads
│   ├── ralph/
│   │   └── task_prompt.md       # Task agent template
│   ├── review/
│   │   ├── fresh_eyes.txt       # Post-task review
│   │   ├── test_coverage.txt    # Test coverage check
│   │   └── beads_review.txt     # Beads optimization
│   └── plan/, prd/, ux/, code/  # Oracle review lenses
├── scripts/
│   ├── ralph.sh                 # Autonomous execution loop
│   ├── oracle_converge.sh       # Review convergence loop
│   ├── gate_pack.sh             # Pre-commit gates
│   └── ...
├── templates/                    # Document templates
│   ├── BRIEF.template.md
│   ├── PRD.template.md
│   ├── UX.template.md
│   └── PLAN.template.md
├── skills/                       # Skill documentation
├── tools/                        # Web tools (task board, etc.)
├── CLAUDE.md                     # Agent instructions
├── AGENTS.md                     # Multi-agent coordination
└── package.json
```

## Available Commands

### Slash Commands (in Claude Code)

| Command | Description |
|---------|-------------|
| `/guide` | Show all available commands and current state |
| `/brief` | Create initial brief from idea |
| `/prd` | Generate PRD from brief |
| `/ux` | Generate UX spec from PRD |
| `/plan` | Generate implementation plan |
| `/sprint` | Decompose plan into beads |
| `/oracle <type>` | Run Oracle review (prd/ux/plan/code) |
| `/ralph` | Start autonomous execution |
| `/review` | Run final review suite |
| `/ship` | Prepare release |
| `/board` | Open task board UI |

### npm Scripts

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
```

### Direct Scripts

```bash
# Ralph with options
./scripts/ralph.sh --beads 50           # 50 iterations with beads
./scripts/ralph.sh --tool claude 50     # Force Claude for all
./scripts/ralph.sh --fresh-eyes 50      # Enable fresh-eyes review
./scripts/ralph.sh --no-auto-pr 50      # Disable auto-PR

# Oracle convergence
./scripts/oracle_converge.sh prd artifacts/01-prd.md
./scripts/oracle_converge.sh plan artifacts/03-plan.md

# Gates
./scripts/gate_pack.sh                  # Run all verification
```

### Beads Commands

```bash
br init                    # Initialize beads in project
br list                    # List all tasks
br list --status open      # List open tasks
br ready                   # Show tasks ready to work
br show bd-xyz             # Show task details
br start bd-xyz            # Start working on task
br close bd-xyz            # Complete task
br stats                   # Show statistics
br sync                    # Sync to git
```

## Monitoring Ralph Execution

```bash
# In terminal 1: Run Ralph
./scripts/ralph.sh --beads 50

# In terminal 2: Watch logs
tail -f .beads/logs/*.log          # All task logs
tail -f progress.txt               # Summary progress

# Check status anytime
br stats && br list --status in_progress
```

## Configuration

### Environment Variables

```bash
# Custom Claude command
export CLAUDE_CMD="claude -p --dangerously-skip-permissions"

# Custom Codex command  
export CODEX_CMD="codex exec --yolo"

# Disable auto-PR
export AUTO_PR=false

# PR base branch
export PR_BASE_BRANCH=develop
```

### Ralph Options

| Option | Default | Description |
|--------|---------|-------------|
| `--tool <t>` | smart | Tool selection: claude, codex, smart |
| `--beads` | auto | Use beads for task tracking |
| `--fresh-eyes` | false | Run fresh-eyes review after each task |
| `--auto-pr` | true | Create PR for each completed task |
| `--no-auto-pr` | - | Disable auto-PR |
| `--pr-base <b>` | main | Base branch for PRs |
| `--no-devin` | - | Disable Devin review |

## Troubleshooting

### "gh CLI not authenticated"

```bash
gh auth login
gh auth status  # Verify
```

### "No origin remote"

```bash
git remote add origin https://github.com/felix-huber/appbuilder-skill.git
git push -u origin main
```

### "Task stuck"

```bash
# Check what's running
br list --status in_progress
ps aux | grep claude

# Check logs
cat .beads/logs/bd-xyz.log

# Kill and restart
pkill -f ralph.sh
./scripts/ralph.sh --beads 50
```

### "Convergence not reached"

```bash
# Check current state
cat artifacts/06-oracle/plan/convergence-history.json

# Force fresh run
rm artifacts/06-oracle/plan/convergence-history.json
./scripts/oracle_converge.sh plan artifacts/03-plan.md
```

## Best Practices

1. **Start with a clear brief** - The better your 00-brief.md, the better everything downstream
2. **Run Oracle reviews** - Don't skip the convergence loops, they catch real issues
3. **Monitor progress** - Keep `tail -f progress.txt` running in another terminal
4. **Review PRs** - Even with Devin review, human review catches things
5. **Use DCG** - The safety tool prevents costly mistakes

## License

MIT

## Links

- [Beads (Task Tracker)](https://github.com/Dicklesworthstone/beads_rust)
- [DCG (Safety Tool)](https://github.com/Dicklesworthstone/destructive_command_guard)
- [Geoffrey Huntley's Ralph](https://ghuntley.com/ralph/)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
