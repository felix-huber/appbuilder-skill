#!/usr/bin/env bash
set -euo pipefail

# Ralph Loop for Oracle Swarm Extension
# Autonomous execution of task graph using fresh AI agent contexts.
#
# Based on Geoffrey Huntley's Ralph pattern and snarktank/ralph
# https://github.com/snarktank/ralph
#
# Supports multiple AI coding tools:
#   - Claude Code: claude -p --dangerously-skip-permissions
#   - Codex CLI: codex exec --yolo
#   - Smart routing (default): backend→Codex, UI→Claude
#
# Task sources:
#   - Default: artifacts/04-task-graph.json (Oracle Swarm format)
#   - Beads: Use `br ready` to get tasks from beads issue tracker
#
# Usage:
#   ./scripts/ralph.sh [options] [max_iterations]
#
# Options:
#   --tool <claude|codex|smart>  Select AI tool (default: smart)
#   --ask                        Ask which tool to use for each task
#   --backend-tool <tool>        Tool for backend tasks (default: codex)
#   --frontend-tool <tool>       Tool for frontend tasks (default: claude)
#   --beads                      Use beads_rust (br) for task management instead of task-graph.json
#
# CLI Flags Used:
#   Claude Code: claude -p --dangerously-skip-permissions "<prompt>"
#   Codex CLI:   codex exec --yolo "<prompt>"
#
# Examples:
#   ./scripts/ralph.sh 50                    # 50 iterations with Claude Code
#   ./scripts/ralph.sh --tool codex 50       # Use Codex for all tasks
#   ./scripts/ralph.sh --tool smart 50       # Smart routing by task type
#   ./scripts/ralph.sh --ask 50              # Ask for each task
#   ./scripts/ralph.sh --beads 50            # Use beads for task tracking

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_GRAPH="$PROJECT_ROOT/artifacts/04-task-graph.json"
PROGRESS_FILE="$PROJECT_ROOT/progress.txt"
LEARNINGS_FILE="$PROJECT_ROOT/learnings.md"
LOGS_DIR="$PROJECT_ROOT/.beads/logs"
CURRENT_TASK_ID=""  # Set during execution for logging

# Defaults
MAX_ITERATIONS=20
TOOL="smart"           # smart = route by task type (codex for backend, claude for frontend)
ASK_MODE=false
BACKEND_TOOL="codex"   # Backend/core/api tasks → Codex (fast iteration)
FRONTEND_TOOL="claude" # Frontend/UI/design tasks → Claude Code (nuanced)
USE_BEADS=""  # Empty = auto-detect/interactive, "true" = beads, "false" = task-graph
FRESH_EYES="false"     # Set to "true" for post-task review
REVIEW_TOOL=""         # Empty = same as coding tool, "codex" or "claude" = cross-model review

# Self-healing (from task-orchestrator pattern)
SELF_HEAL="true"       # Auto-recover stuck tasks
STALL_THRESHOLD=20     # Minutes before considering a task stuck

# Auto-PR feature
AUTO_PR="true"         # Auto-create PRs when tasks complete (requires gh CLI)
PR_BASE_BRANCH="main"  # Base branch for PRs

# Build verification (CRITICAL for catching broken code)
VERIFY_BUILD="true"    # Run npm run build after each task (default: true)
VERIFY_TYPECHECK="true" # Run npm run typecheck after each task (default: true)
VERIFY_LINT="true"     # Run npm run lint after each task (default: true)
VERIFY_TESTS="true"    # Run npm test after each task (default: true)
BUILD_FAIL_COUNT=0     # Track consecutive build failures

# Council of Subagents review (multi-agent verification pattern)
# Uses specialized subagents: Analyst (quality), Sentinel (anti-patterns), Designer (UI), Healer (fixes)
COUNCIL_REVIEW="false"  # Set to "true" to run council review after each task

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_tool() { echo -e "${CYAN}[TOOL]${NC} $1"; }

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tool)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--tool requires a value (claude, codex, or smart)"
          exit 1
        fi
        TOOL="$2"
        shift 2
        ;;
      --ask)
        ASK_MODE=true
        shift
        ;;
      --backend-tool)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--backend-tool requires a value"
          exit 1
        fi
        BACKEND_TOOL="$2"
        shift 2
        ;;
      --frontend-tool)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--frontend-tool requires a value"
          exit 1
        fi
        FRONTEND_TOOL="$2"
        shift 2
        ;;
      --beads)
        USE_BEADS="true"
        shift
        ;;
      --no-beads|--graph)
        USE_BEADS="false"
        shift
        ;;
      --fresh-eyes)
        FRESH_EYES="true"
        shift
        ;;
      --review-tool)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--review-tool requires a value (claude or codex)"
          exit 1
        fi
        REVIEW_TOOL="$2"
        FRESH_EYES="true"  # Implicitly enable fresh-eyes when review-tool is set
        shift 2
        ;;
      --no-self-heal)
        SELF_HEAL="false"
        shift
        ;;
      --stall-threshold)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--stall-threshold requires a value (minutes)"
          exit 1
        fi
        STALL_THRESHOLD="$2"
        shift 2
        ;;
      --auto-pr)
        AUTO_PR="true"
        shift
        ;;
      --no-auto-pr)
        AUTO_PR="false"
        shift
        ;;
      --verify-build)
        VERIFY_BUILD="true"
        shift
        ;;
      --no-verify-build)
        VERIFY_BUILD="false"
        shift
        ;;
      --verify-typecheck)
        VERIFY_TYPECHECK="true"
        shift
        ;;
      --no-verify-typecheck)
        VERIFY_TYPECHECK="false"
        shift
        ;;
      --verify-lint)
        VERIFY_LINT="true"
        shift
        ;;
      --no-verify-lint)
        VERIFY_LINT="false"
        shift
        ;;
      --verify-tests)
        VERIFY_TESTS="true"
        shift
        ;;
      --no-verify-tests)
        VERIFY_TESTS="false"
        shift
        ;;
      --council-review)
        COUNCIL_REVIEW="true"
        shift
        ;;
      --no-council-review)
        COUNCIL_REVIEW="false"
        shift
        ;;
      --pr-base)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--pr-base requires a branch name"
          exit 1
        fi
        PR_BASE_BRANCH="$2"
        shift 2
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          MAX_ITERATIONS="$1"
        elif [[ "$1" != -* ]]; then
          log_warn "Ignoring unknown argument: $1"
        fi
        shift
        ;;
    esac
  done
  
  # Validate tool value
  case "$TOOL" in
    claude|codex|smart) ;;
    *)
      log_error "Invalid tool: $TOOL (must be claude, codex, or smart)"
      exit 1
      ;;
  esac

  if [[ -n "$REVIEW_TOOL" ]]; then
    case "$REVIEW_TOOL" in
      claude|codex) ;;
      *)
        log_error "--review-tool must be 'claude' or 'codex', got: $REVIEW_TOOL"
        exit 1
        ;;
    esac
  fi
}

show_help() {
  cat << 'EOF'
Ralph Loop - Autonomous AI Agent Execution

Usage: ./scripts/ralph.sh [options] [max_iterations]

Options:
  --tool <claude|codex|smart>  Select AI tool (default: smart)
                               smart  = Route by task type (RECOMMENDED)
                               claude = Claude Code CLI for all tasks
                               codex  = OpenAI Codex CLI for all tasks
  --ask                        Ask which tool to use for each task
  --backend-tool <tool>        Tool for backend/core tasks (default: codex)
  --frontend-tool <tool>       Tool for UI/frontend tasks (default: claude)
  --beads                      Use beads_rust (br) for task tracking
  --no-beads, --graph          Use task-graph.json (Oracle Swarm built-in)
  --fresh-eyes                 Run fresh-eyes code review after each task
  --review-tool <claude|codex> Use different tool for code review (cross-model)
  --no-self-heal               Disable auto-recovery of stuck tasks
  --stall-threshold <min>      Minutes before task is considered stuck (default: 20)
  --auto-pr                    Create PR after each completed task (default: on)
  --no-auto-pr                 Disable auto-PR creation
  --pr-base <branch>           Base branch for PRs (default: main)
  --verify-build               Enable build verification (default: on)
  --no-verify-build            Disable build verification
  --verify-typecheck           Enable typecheck verification (default: on)
  --no-verify-typecheck        Disable typecheck verification
  --verify-lint                Enable lint verification (default: on)
  --no-verify-lint             Disable lint verification
  --verify-tests               Enable test verification (default: on)
  --no-verify-tests            Disable test verification
  --council-review             Enable Council of Subagents review (Analyst/Sentinel/Designer/Healer)
  --no-council-review          Disable council review (default)
  -h, --help                   Show this help

Tool Routing (Doodlestein Methodology):
  By default (--tool smart), Ralph routes tasks by type:
  - Backend tasks (core, engine, api, data, worker, db) → Codex (fast iteration)
  - Frontend tasks (ui, components, design, css, styles) → Claude Code (nuanced)
  
  Heavy document reviews (PRD, UX, Plan) use GPT-5.2 Pro via /oracle command.

Cross-Model Review (--review-tool):
  Use a different model for code review than for coding:
  - Code with Claude (Opus 4.5), review with Codex (GPT 5.2)
  - Code with Codex, review with Claude
  Different models catch different types of issues!
  
  Example: ./scripts/ralph.sh --tool claude --review-tool codex --beads 50

Task Source Selection:
  By default, Ralph will auto-detect available task sources:
  - If both beads (.beads/) and task-graph.json exist → interactive prompt
  - If only one exists → auto-select that source
  - Use --beads or --no-beads to skip interactive selection

Fresh Eyes Review (--fresh-eyes):
  Per Doodlestein methodology, after each task completion, Ralph will:
  1. Ask the agent to review the new code with "fresh eyes"
  2. Fix any bugs/issues found
  3. Repeat until no issues are found (max 3 passes)
  This adds time but catches bugs much earlier.

Build Verification (enabled by default):
  After each task completion (before marking complete):
  1. Run npm run lint     → Catch code quality issues
  2. Run npm run typecheck → Catch TypeScript errors
  3. Run npm run build    → Catch build errors
  4. Run npm run test     → Verify TDD tests pass
  5. Detect anti-patterns  → Disabled lint rules, weakened tsconfig
  If ANY step fails, the task is marked FAILED even if agent said complete.
  Use --no-verify-build, --no-verify-tests, etc to disable specific checks.

Council of Subagents Review (--council-review):
  Multi-agent verification pattern using four specialized roles:
  1. Analyst: Reviews code quality, correctness, architecture
  2. Sentinel: Detects anti-patterns, shortcuts, security issues
  3. Designer: Reviews UI/UX quality (Stripe-level bar) - only for UI tasks
  4. Healer: Fixes issues found by other subagents
  Adds time but catches issues that single-agent review misses.
  See docs/AGENT_EVALUATION.md for details.

UI Quality (automatic for frontend tasks):
  When task tags include ui, component, frontend, design, css, style, or ux:
  - UI quality requirements are automatically injected into the prompt
  - Designer subagent reviews for Stripe/Linear/Vercel quality bar
  - Covers visual polish, micro-interactions, accessibility, responsiveness

Self-Healing (enabled by default):
  Ralph monitors task execution and auto-recovers stuck tasks:
  - If a task runs longer than STALL_THRESHOLD minutes → reset and retry
  - Failed tasks are retried with different approach hints
  - Use --no-self-heal to disable

Auto-PR (enabled by default):
  After each completed task, Ralph will:
  1. Create a feature branch (task/<task-id>)
  2. Commit changes with descriptive message
  3. Create a PR against PR_BASE_BRANCH
  Requires gh CLI: brew install gh && gh auth login

Learnings Capture:
  Ralph records learnings from each task to learnings.md:
  - What worked well
  - Issues encountered
  - Patterns discovered
  Useful for improving future prompts and workflows.

CLI Flags Used (YOLO mode by default):
  Claude Code: claude -p --dangerously-skip-permissions "<prompt>"
  Codex CLI:   codex exec --yolo "<prompt>"

Environment Variables:
  CLAUDE_CMD       Custom Claude Code command
  CODEX_CMD        Custom Codex command
  FRESH_EYES       "true" to enable fresh-eyes review
  COUNCIL_REVIEW   "true" to enable council review
  SELF_HEAL        "false" to disable self-healing
  STALL_THRESHOLD  Minutes before task is stuck (default: 20)
  AUTO_PR          "false" to disable auto-PR
  PR_BASE_BRANCH   Base branch for PRs (default: main)
  VERIFY_BUILD     "false" to disable build verification
  VERIFY_TYPECHECK "false" to disable typecheck verification
  VERIFY_LINT      "false" to disable lint verification
  VERIFY_TESTS     "false" to disable test verification

Examples:
  ./scripts/ralph.sh 50                    # 50 iterations, smart routing (default)
  ./scripts/ralph.sh --beads 50            # Force beads_rust (br) for tasks
  ./scripts/ralph.sh --fresh-eyes 50       # Enable fresh-eyes review after each task
  ./scripts/ralph.sh --tool claude 50      # Use Claude Code for all tasks
  ./scripts/ralph.sh --tool codex 50       # Use Codex for all tasks
  ./scripts/ralph.sh --ask 50              # Interactive tool selection per task

Task Type Detection (for smart routing):
  Frontend: tags contain ui, components, frontend, design, css, styles
  Backend:  tags contain core, engine, api, backend, data, worker, db

Beads Integration (beads_rust):
  Install: cargo install --git https://github.com/Dicklesworthstone/beads_rust.git
  Commands used:
    - br ready --json     : Get tasks with no blockers
    - br close <id>       : Complete a task
    - br update <id>      : Update task status
    - br dep add <a> <b>  : Add dependency (a depends on b)

Task Graph Integration (Oracle Swarm):
  Generate: /artifact-tasks to compile from plan + Oracle issues
  Format:   artifacts/04-task-graph.json
EOF
}

# Check prerequisites
check_prerequisites() {
  local has_claude=false
  local has_codex=false
  
  # Create logs directory
  mkdir -p "$LOGS_DIR"
  
  # Check which tools are available
  if command -v claude &> /dev/null; then
    has_claude=true
  fi
  if command -v codex &> /dev/null; then
    has_codex=true
  fi
  
  # Check for selected tool
  case "$TOOL" in
    claude)
      if [[ "$has_claude" != "true" ]]; then
        log_error "Claude Code CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
        exit 1
      fi
      ;;
    codex)
      if [[ "$has_codex" != "true" ]]; then
        log_error "Codex CLI not found. Install from: https://github.com/openai/codex"
        exit 1
      fi
      ;;
    smart)
      # For smart routing, we need at least one tool
      if [[ "$has_claude" != "true" && "$has_codex" != "true" ]]; then
        log_error "Smart routing requires at least one tool (claude or codex)"
        log_error "Install Claude Code: npm install -g @anthropic-ai/claude-code"
        log_error "Install Codex: https://github.com/openai/codex"
        exit 1
      fi
      
      # Warn about missing tools
      if [[ "$has_claude" != "true" ]]; then
        log_warn "Claude Code not found - will use codex for all tasks"
        FRONTEND_TOOL="codex"
      fi
      if [[ "$has_codex" != "true" ]]; then
        log_warn "Codex not found - will use claude for all tasks"
        BACKEND_TOOL="claude"
      fi
      ;;
  esac
  
  if ! command -v jq &> /dev/null; then
    log_error "jq not found. Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
  fi
  
  # Interactive task source selection (if not explicitly set)
  if [[ "$USE_BEADS" != "true" && "$USE_BEADS" != "false" ]]; then
    select_task_source
  fi
  
  # Check task source
  if [[ "$USE_BEADS" == "true" ]]; then
    # Beads mode - check for br CLI
    if ! command -v br &> /dev/null; then
      log_error "beads_rust CLI (br) not found."
      log_error "Install with: cargo install --git https://github.com/Dicklesworthstone/beads_rust.git"
      exit 1
    fi
    
    # Check if beads is initialized
    if [[ ! -d ".beads" ]]; then
      log_error "Beads not initialized in this project."
      log_error "Run: br init"
      exit 1
    fi
    
    log_info "Using beads_rust (br) for task management"
  else
    # Standard mode - check for task-graph.json
    if [[ ! -f "$TASK_GRAPH" ]]; then
      log_error "Task graph not found at: $TASK_GRAPH"
      log_error "Run /artifact-tasks first to compile the task graph."
      log_error "Or use --beads to use beads for task management."
      exit 1
    fi
  fi
  
  if ! git rev-parse --git-dir &> /dev/null; then
    log_error "Not a git repository. Initialize with: git init"
    exit 1
  fi
}

# Interactive task source selection
select_task_source() {
  local has_beads=false
  local has_graph=false
  
  # Check what's available
  [[ -d ".beads" ]] && command -v br &> /dev/null && has_beads=true
  [[ -f "$TASK_GRAPH" ]] && has_graph=true
  
  # If both are available, ask user
  if [[ "$has_beads" == "true" && "$has_graph" == "true" ]]; then
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            SELECT TASK SOURCE                                 ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  Both task sources are available:                             ║"
    echo "║                                                               ║"
    echo "║  [1] beads_rust (br)                                          ║"
    echo "║      → .beads/ directory with dependency-aware tracking       ║"
    echo "║      → Commands: br ready, br close, br update                ║"
    echo "║                                                               ║"
    echo "║  [2] task-graph.json (Oracle Swarm built-in)                  ║"
    echo "║      → artifacts/04-task-graph.json                           ║"
    echo "║      → Compiled from plan + Oracle issues                     ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    
    while true; do
      read -p "Choose task source [1/2] (or 'q' to quit): " choice
      case "$choice" in
        1|beads|br)
          USE_BEADS="true"
          log_info "Selected: beads_rust (br)"
          return
          ;;
        2|graph|json)
          USE_BEADS="false"
          log_info "Selected: task-graph.json"
          return
          ;;
        q|quit|exit)
          echo "Aborted."
          exit 0
          ;;
        *)
          echo "Please enter 1 or 2"
          ;;
      esac
    done
  elif [[ "$has_beads" == "true" ]]; then
    # Only beads available
    USE_BEADS="true"
    log_info "Auto-selected: beads_rust (br) - only available source"
  elif [[ "$has_graph" == "true" ]]; then
    # Only task-graph available  
    USE_BEADS="false"
    log_info "Auto-selected: task-graph.json - only available source"
  else
    # Neither available - show setup instructions
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            NO TASK SOURCE FOUND                               ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  Choose one of these setup options:                           ║"
    echo "║                                                               ║"
    echo "║  Option A: Use beads_rust (br) for task tracking              ║"
    echo "║    1. cargo install --git https://github.com/                 ║"
    echo "║           Dicklesworthstone/beads_rust.git                    ║"
    echo "║    2. br init                                                 ║"
    echo "║    3. br create \"Task title\" -t task -p 1                     ║"
    echo "║    4. ./scripts/ralph.sh --beads                              ║"
    echo "║                                                               ║"
    echo "║  Option B: Use Oracle Swarm task-graph.json                   ║"
    echo "║    1. Create artifacts/03-plan.md with tasks                  ║"
    echo "║    2. Run /artifact-tasks to compile                          ║"
    echo "║    3. ./scripts/ralph.sh                                      ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    exit 1
  fi
}

# Initialize progress file if needed
init_progress() {
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    cat > "$PROGRESS_FILE" << 'EOF'
# Progress Log

This file tracks learnings across Ralph iterations.
Each iteration appends discoveries here for future context.

## Codebase Patterns
- (Patterns will be added as discovered)

## Gotchas
- (Gotchas will be added as discovered)

## Iteration Log
EOF
    log_info "Created progress.txt"
  fi
}

# Determine which tool to use for a task
get_tool_for_task() {
  local task_json="$1"
  local tags=$(echo "$task_json" | jq -r '(.tags // []) | map(ascii_downcase) | join(" ")')
  
  if [[ "$ASK_MODE" == "true" ]]; then
    local subject=$(echo "$task_json" | jq -r '.subject')
    echo "" >&2
    log_info "Task: $subject" >&2
    log_info "Tags: $tags" >&2
    echo -e "${CYAN}Which tool should handle this task?${NC}" >&2
    echo "  1) claude  - Claude Code" >&2
    echo "  2) codex   - OpenAI Codex" >&2
    echo -n "Choice [1/2]: " >&2
    read -r choice
    case "$choice" in
      2|codex) echo "codex" ;;
      *) echo "claude" ;;
    esac
    return
  fi
  
  if [[ "$TOOL" != "smart" ]]; then
    echo "$TOOL"
    return
  fi
  
  # Smart routing based on tags
  local frontend_tags="ui components frontend design css styles layout view"
  local backend_tags="core engine api backend data worker db database server"
  
  local is_frontend=false
  local is_backend=false
  
  for tag in $tags; do
    if [[ " $frontend_tags " =~ " $tag " ]]; then
      is_frontend=true
    fi
    if [[ " $backend_tags " =~ " $tag " ]]; then
      is_backend=true
    fi
  done
  
  # Decide based on detected type
  if [[ "$is_frontend" == "true" && "$is_backend" == "false" ]]; then
    echo "$FRONTEND_TOOL"
  elif [[ "$is_backend" == "true" && "$is_frontend" == "false" ]]; then
    echo "$BACKEND_TOOL"
  elif [[ "$is_frontend" == "true" && "$is_backend" == "true" ]]; then
    # Mixed - prefer frontend tool for UI safety
    echo "$FRONTEND_TOOL"
  else
    # Default to claude for unknown
    echo "claude"
  fi
}

# Run a task with the specified tool
run_with_tool() {
  local tool="$1"
  local prompt="$2"
  local output=""
  local log_file=""
  
  # Create log file for this task if we have a task ID
  if [[ -n "$CURRENT_TASK_ID" ]]; then
    log_file="$LOGS_DIR/${CURRENT_TASK_ID}.log"
    echo "=== Task: $CURRENT_TASK_ID ===" > "$log_file"
    echo "=== Tool: $tool ===" >> "$log_file"
    echo "=== Started: $(date -Iseconds) ===" >> "$log_file"
    echo "" >> "$log_file"
    log_info "Logging to: $log_file"
    log_info "Watch with: tail -f $log_file"
  fi
  
  log_tool "Using: $tool"
  
  case "$tool" in
    claude)
      # Claude Code CLI flags:
      #   -p / --print : Non-interactive mode, output to stdout
      #   --dangerously-skip-permissions : Skip all approval prompts (YOLO mode)
      # Customize via CLAUDE_CMD env var if needed
      local claude_cmd="${CLAUDE_CMD:-claude -p --dangerously-skip-permissions}"
      if [[ -n "$log_file" ]]; then
        output=$($claude_cmd "$prompt" 2>&1 | tee -a "$log_file" | tee /dev/stderr) || true
      else
        output=$($claude_cmd "$prompt" 2>&1 | tee /dev/stderr) || true
      fi
      ;;
    codex)
      # Codex CLI flags:
      #   exec / e : Non-interactive execution mode
      #   --yolo : Skip approvals and sandbox (alias for --dangerously-bypass-approvals-and-sandbox)
      #   Alternative: --full-auto (safer, keeps sandbox but auto-approves)
      # Customize via CODEX_CMD env var if needed
      local codex_cmd="${CODEX_CMD:-codex exec --yolo}"
      if [[ -n "$log_file" ]]; then
        output=$($codex_cmd "$prompt" 2>&1 | tee -a "$log_file" | tee /dev/stderr) || true
      else
        output=$($codex_cmd "$prompt" 2>&1 | tee /dev/stderr) || true
      fi
      ;;
    *)
      log_error "Unknown tool: $tool"
      return 1
      ;;
  esac
  
  # Log completion
  if [[ -n "$log_file" ]]; then
    echo "" >> "$log_file"
    echo "=== Finished: $(date -Iseconds) ===" >> "$log_file"
  fi
  
  echo "$output"
}

# Council of Subagents Review Pattern
# Uses four specialized subagent roles to verify task completion:
#   - Analyst: Reviews code quality, correctness, architecture
#   - Sentinel: Watches for anti-patterns, security issues, shortcuts
#   - Designer: Reviews UI/UX quality (only for UI-tagged tasks)
#   - Healer: Fixes issues found by Analyst/Sentinel/Designer
#
# Based on research from multi-agent evaluation patterns.
# See: docs/AGENT_EVALUATION.md
run_council_review() {
  local task_id="$1"
  local tool="${2:-claude}"  # Default to Claude for reviews
  local task_tags="${3:-}"   # Task tags to determine if Designer review needed
  local log_file="$LOGS_DIR/${task_id}-council.log"

  # Ensure log directory exists
  mkdir -p "$LOGS_DIR" 2>/dev/null || true

  log_info "╔════════════════════════════════════════════════════════════════╗"
  log_info "║             COUNCIL OF SUBAGENTS REVIEW                        ║"
  log_info "╚════════════════════════════════════════════════════════════════╝"

  # Get the diff of recent changes
  # Need to handle both committed and uncommitted changes from the task
  local diff_content=""
  local changed_files=""
  if git rev-parse --git-dir &>/dev/null; then
    # First check for uncommitted changes (working tree + staged)
    local uncommitted_files
    local uncommitted_diff
    uncommitted_files=$(git diff --name-only HEAD 2>/dev/null || echo "")
    uncommitted_diff=$(git diff HEAD 2>/dev/null || echo "")

    if [[ -n "$uncommitted_files" ]]; then
      # There are uncommitted changes - review those
      changed_files="$uncommitted_files"
      diff_content="$uncommitted_diff"
    elif git rev-parse HEAD~1 &>/dev/null 2>&1; then
      # No uncommitted changes, but there's a previous commit
      # Review the most recent commit (task probably committed its work)
      changed_files=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
      diff_content=$(git diff HEAD~1 HEAD 2>/dev/null || echo "")
    fi
  fi

  # Truncate if too large
  local diff_lines
  diff_lines=$(printf '%s\n' "$diff_content" | wc -l | tr -d ' ')
  if (( diff_lines > 300 )); then
    diff_content=$(printf '%s\n' "$diff_content" | head -n 300)
    diff_content="${diff_content}"$'\n'"... (truncated, ${diff_lines} total lines)"
  fi

  if [[ -z "$changed_files" ]]; then
    log_info "No changes to review - skipping council review"
    return 0
  fi

  local issues_found=false
  local council_issues=""

  # ═══════════════════════════════════════════════════════════════
  # ANALYST: Review code quality and correctness
  # ═══════════════════════════════════════════════════════════════
  log_info "🔍 Analyst: Reviewing code quality and correctness..."

  local analyst_prompt="You are the ANALYST subagent in a code review council.
Your role: Evaluate code QUALITY and CORRECTNESS.

CHANGED FILES:
$changed_files

DIFF:
$diff_content

Review for:
1. Does the code correctly implement the intended functionality?
2. Are there logic errors, off-by-one errors, or race conditions?
3. Is the code well-structured and maintainable?
4. Are edge cases handled appropriately?
5. Are there missing null/undefined checks?

Output format:
If issues found:
ANALYST_ISSUES:
- [severity] file:line - description

If no issues:
ANALYST_OK

Be concise. Only report real issues, not stylistic preferences."

  set +e
  local analyst_output
  analyst_output=$(run_with_tool "$tool" "$analyst_prompt" 2>&1)
  set -e

  {
    echo "=== ANALYST REVIEW ==="
    echo "$analyst_output"
    echo ""
  } >> "$log_file"

  if echo "$analyst_output" | grep -q "ANALYST_ISSUES"; then
    issues_found=true
    council_issues+="ANALYST found issues:"$'\n'
    council_issues+=$(echo "$analyst_output" | grep -A 50 "ANALYST_ISSUES" | head -20)
    council_issues+=$'\n\n'
    log_warn "  Analyst found issues"
  else
    log_success "  Analyst: ✅ No issues"
  fi

  # ═══════════════════════════════════════════════════════════════
  # SENTINEL: Watch for anti-patterns and shortcuts
  # ═══════════════════════════════════════════════════════════════
  log_info "🛡️ Sentinel: Scanning for anti-patterns and shortcuts..."

  local sentinel_prompt="You are the SENTINEL subagent in a code review council.
Your role: Detect ANTI-PATTERNS and SHORTCUTS that hide problems.

CHANGED FILES:
$changed_files

DIFF:
$diff_content

Watch for:
1. Lint rules being disabled (@ts-ignore, eslint-disable, 'off' rules)
2. TypeScript config being weakened (skipLibCheck, any casts)
3. Tests being skipped or mocked inappropriately
4. Error swallowing (empty catch blocks, catch all)
5. TODO/FIXME comments that should be addressed
6. Magic numbers or hardcoded values
7. Security issues (XSS, injection, exposed secrets)
8. Overly broad types (any, unknown without narrowing)

Output format:
If violations found:
SENTINEL_VIOLATIONS:
- [severity] file:line - description

If no violations:
SENTINEL_OK

Be strict. These patterns cause production failures."

  set +e
  local sentinel_output
  sentinel_output=$(run_with_tool "$tool" "$sentinel_prompt" 2>&1)
  set -e

  {
    echo "=== SENTINEL REVIEW ==="
    echo "$sentinel_output"
    echo ""
  } >> "$log_file"

  if echo "$sentinel_output" | grep -q "SENTINEL_VIOLATIONS"; then
    issues_found=true
    council_issues+="SENTINEL found violations:"$'\n'
    council_issues+=$(echo "$sentinel_output" | grep -A 50 "SENTINEL_VIOLATIONS" | head -20)
    council_issues+=$'\n\n'
    log_warn "  Sentinel found violations"
  else
    log_success "  Sentinel: ✅ No violations"
  fi

  # ═══════════════════════════════════════════════════════════════
  # DESIGNER: Review UI/UX quality (only for UI-tagged tasks)
  # ═══════════════════════════════════════════════════════════════
  local is_ui_task=false
  if echo "$task_tags" | grep -qiE "ui|component|frontend|design|css|style|ux"; then
    is_ui_task=true
  fi

  if [[ "$is_ui_task" == "true" ]]; then
    log_info "🎨 Designer: Reviewing UI/UX quality (Stripe-level bar)..."

    local designer_prompt="You are the DESIGNER subagent in a code review council.
Your role: Ensure WORLD-CLASS UI/UX quality at the Stripe/Linear level.

CHANGED FILES:
$changed_files

DIFF:
$diff_content

You must do a spectacular job reviewing for absolutely world-class UI/UX quality.
Apply an intense focus on the most visually appealing, user-friendly, intuitive,
slick, polished, \"Stripe level\" of quality possible.

Review for:
1. **Visual Polish**: Spacing, alignment, typography, color harmony
2. **Micro-interactions**: Hover states, transitions, loading states, animations
3. **Accessibility**: Color contrast, focus states, screen reader support
4. **Responsiveness**: Mobile-first, breakpoints, touch targets
5. **Consistency**: Design system adherence, component reuse
6. **Delight**: Does it feel premium? Would a designer be proud of this?
7. **Edge Cases**: Empty states, error states, long content, RTL support

Quality bar examples (what we're aiming for):
- Stripe: Clean, confident, spacious, purposeful animations
- Linear: Fast, keyboard-first, beautiful dark mode, crisp icons
- Vercel: Minimal, elegant, excellent typography, subtle gradients

Output format:
If UI/UX issues found:
DESIGNER_ISSUES:
- [severity] file:line - description (with specific fix suggestion)

If the UI meets the quality bar:
DESIGNER_OK

Be demanding. We want users to say \"wow\" when they see this UI."

    set +e
    local designer_output
    designer_output=$(run_with_tool "$tool" "$designer_prompt" 2>&1)
    set -e

    {
      echo "=== DESIGNER REVIEW ==="
      echo "$designer_output"
      echo ""
    } >> "$log_file"

    if echo "$designer_output" | grep -q "DESIGNER_ISSUES"; then
      issues_found=true
      council_issues+="DESIGNER found UI/UX issues:"$'\n'
      council_issues+=$(echo "$designer_output" | grep -A 50 "DESIGNER_ISSUES" | head -20)
      council_issues+=$'\n\n'
      log_warn "  Designer found UI/UX issues"
    else
      log_success "  Designer: ✅ UI/UX meets quality bar"
    fi
  fi

  # ═══════════════════════════════════════════════════════════════
  # HEALER: Fix issues if found
  # ═══════════════════════════════════════════════════════════════
  if [[ "$issues_found" == "true" ]]; then
    log_info "💊 Healer: Attempting to fix issues..."

    local healer_prompt="You are the HEALER subagent in a code review council.
The ANALYST, SENTINEL, and DESIGNER found the following issues that need fixing:

$council_issues

Your job: Fix these issues in the codebase.

Instructions:
1. Read each issue carefully
2. Locate the affected file(s)
3. Apply targeted fixes
4. Do NOT introduce new features or refactorings
5. Keep fixes minimal and focused

After fixing each issue, explain what you changed.

If you cannot fix an issue (e.g., requires clarification), explain why.

Output:
HEALER_FIXES:
- Fixed: [description of what was fixed]
- Skipped: [description of what couldn't be fixed and why]

Then output: HEALER_COMPLETE"

    set +e
    local healer_output
    healer_output=$(run_with_tool "$tool" "$healer_prompt" 2>&1)
    set -e

    {
      echo "=== HEALER REVIEW ==="
      echo "$healer_output"
      echo ""
    } >> "$log_file"

    if echo "$healer_output" | grep -q "HEALER_COMPLETE"; then
      log_success "  Healer: Applied fixes"

      # Re-run build verification after healer fixes
      log_info "Re-verifying build after healer fixes..."
      if verify_build "$task_id"; then
        log_success "Build still passes after healer fixes"
      else
        log_error "Build FAILED after healer fixes!"
        log_error "Manual intervention required"
        return 1
      fi
    else
      log_warn "  Healer: Could not complete all fixes"
    fi
  fi

  # Summary
  log_info "╔════════════════════════════════════════════════════════════════╗"
  if [[ "$issues_found" == "true" ]]; then
    log_info "║  Council review: Issues found and addressed                    ║"
  else
    log_info "║  Council review: ✅ All checks passed                          ║"
  fi
  log_info "╚════════════════════════════════════════════════════════════════╝"
  log_info "Full council log: $log_file"

  # Log to progress
  {
    echo ""
    echo "### Council Review - $(date -Iseconds)"
    echo "- Task: $task_id"
    echo "- Issues found: $issues_found"
    echo "- Log: $log_file"
  } >> "$PROGRESS_FILE"

  return 0
}

# Fresh Eyes Code Review (Doodlestein methodology)
# Run after each task completion to catch bugs early
# Keep running until no bugs are found
# Supports cross-model review and Codex-optimized review prompts
run_fresh_eyes_review() {
  local tool="$1"
  local max_review_passes=3
  local pass=1
  
  # Check if we're in a git repo
  local in_git_repo=false
  if git rev-parse --git-dir &>/dev/null; then
    in_git_repo=true
  fi
  
  # Use Codex two-phase review if tool is codex and we have git
  # Phase 1: Find issues (read-only analysis)
  # Phase 2: Fix issues (apply changes)
  if [[ "$tool" == "codex" && "$in_git_repo" == "true" ]]; then
    log_info "  Using Codex two-phase code review..."
    
    # Check if there are uncommitted changes
    if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
      log_info "  No uncommitted changes to review"
      return 0
    fi
    
    # Generate diff for Codex to review
    local diff_content
    diff_content=$(git diff HEAD 2>/dev/null || git diff 2>/dev/null || echo "")
    local staged_diff
    staged_diff=$(git diff --cached 2>/dev/null || echo "")
    local changed_files
    changed_files=$(git diff --name-status HEAD 2>/dev/null || git diff --name-status 2>/dev/null || echo "unknown")

    local combined_diff=""
    if [[ -n "$diff_content" ]]; then
      combined_diff="$diff_content"
    fi
    if [[ -n "$staged_diff" ]]; then
      if [[ -n "$combined_diff" ]]; then
        combined_diff="${combined_diff}"$'\n'"$staged_diff"
      else
        combined_diff="$staged_diff"
      fi
    fi

    local diff_note=""
    if [[ -n "$combined_diff" ]]; then
      local diff_line_count
      diff_line_count=$(printf '%s\n' "$combined_diff" | wc -l | tr -d ' ')
      if (( diff_line_count > 500 )); then
        combined_diff=$(printf '%s\n' "$combined_diff" | head -n 500)
        diff_note="NOTE: Diff truncated to first 500 lines to avoid context overflow."
      fi
    fi
    
    # PHASE 1: Find issues (using OpenAI's recommended review prompt)
    log_info "  Phase 1: Analyzing code for issues..."
    local review_prompt="You are acting as a reviewer for code changes made by another engineer.
Focus on issues that impact correctness, performance, security, maintainability, or developer experience.
Flag only actionable issues. When you flag an issue, provide a short, direct explanation and cite the affected file and line range.
Prioritize severe issues (P1, P2) and avoid nit-level comments.

CHANGED FILES:
$changed_files

DIFF:
$diff_note
$combined_diff

Review the changes above and list any issues you find.
Format each issue as:
[P1] Issue title — file:line-range
  Description of the problem and suggested fix.
Use P1, P2, or P3 for severity.

If no issues found, output exactly: NO_ISSUES_FOUND"

    local review_output
    set +e
    review_output=$(run_with_tool "$tool" "$review_prompt" 2>&1)
    set -e
    
    # Check if issues were found
    if echo "$review_output" | grep -qx "NO_ISSUES_FOUND"; then
      log_success "  Codex review complete - no issues found"
      return 0
    fi

    local issue_lines
    issue_lines=$(echo "$review_output" | grep -E '^\[P[123]\]' || true)
    if [[ -z "$issue_lines" ]]; then
      log_warn "  Codex review output contained no parsable issues"
      return 0
    fi
    
    # PHASE 2: Fix the issues found
    log_info "  Phase 2: Fixing identified issues..."
    local fix_prompt="You just reviewed this code and found issues. Now fix them.

ISSUES FOUND IN REVIEW:
$issue_lines

CHANGED FILES:
$changed_files

Please fix ALL the issues identified above. For each fix:
1. Read the relevant file
2. Make the necessary changes
3. Verify the fix is correct

After fixing all issues, output: FIXES_APPLIED
If you couldn't fix something, explain why and output: PARTIAL_FIX"

    local fix_output
    set +e
    fix_output=$(run_with_tool "$tool" "$fix_prompt" 2>&1)
    set -e
    
    if echo "$fix_output" | grep -qx "FIXES_APPLIED"; then
      log_success "  Codex found and fixed all issues"
    elif echo "$fix_output" | grep -qx "PARTIAL_FIX"; then
      log_warn "  Codex fixed some issues but not all - manual review needed"
    else
      log_info "  Codex fix phase complete"
    fi
    
    return 0
  fi
  
  # Standard fresh-eyes prompt for Claude or non-git scenarios
  local review_prompt=$(cat <<'EOF'
Great, now I want you to carefully read over all of the new code you
just wrote and other existing code you just modified with "fresh eyes"
looking super carefully for any obvious bugs, errors, problems, issues,
confusion, etc.

Carefully fix anything you uncover.

If you find issues, fix them and output: <review>FOUND_ISSUES</review>
If everything looks good, output: <review>NO_ISSUES</review>
EOF
)
  
  while [[ $pass -le $max_review_passes ]]; do
    log_info "  Fresh eyes review pass $pass/$max_review_passes..."
    
    local review_output
    set +e
    review_output=$(run_with_tool "$tool" "$review_prompt" 2>&1)
    set -e
    
    if echo "$review_output" | grep -q "<review>NO_ISSUES</review>"; then
      log_success "  Fresh eyes review complete - no issues found"
      return 0
    elif echo "$review_output" | grep -q "<review>FOUND_ISSUES</review>"; then
      log_info "  Issues found and fixed, running another pass..."
      pass=$((pass + 1))
    else
      # No clear signal, assume done
      log_info "  Fresh eyes review complete (no clear signal)"
      return 0
    fi
  done
  
  log_warn "  Reached max review passes ($max_review_passes), continuing..."
}

# Get next pending task (respects dependencies)
get_next_task() {
  if [[ "$USE_BEADS" == "true" ]]; then
    get_next_task_beads
  else
    get_next_task_graph
  fi
}

# Get next task from task-graph.json
get_next_task_graph() {
  # Find first task where:
  # - status is "pending"
  # - all blockedBy tasks are "completed"
  jq -r '
    .tasks as $all |
    ($all | map(select(.status == "completed")) | map(.id)) as $completed |
    $all | map(select(
      .status == "pending" and
      ((.blockedBy // []) | all(. as $dep | $completed | index($dep)))
    )) | first // empty
  ' "$TASK_GRAPH"
}

# Get next task from beads (br ready)
get_next_task_beads() {
  # br ready --json returns tasks with no open blockers
  # Format: [{"id": "bd-a1b2", "title": "...", "priority": 1, "type": "task", ...}]
  local ready_tasks
  ready_tasks=$(br ready --json 2>/dev/null || echo "[]")
  
  if [[ "$ready_tasks" == "[]" || -z "$ready_tasks" ]]; then
    echo ""
    return
  fi
  
  # Get the first ready task and convert to our format
  echo "$ready_tasks" | jq -r '
    .[0] | {
      id: .id,
      subject: .title,
      description: (.description // ""),
      tags: ((.labels // []) | map(ascii_downcase)),
      priority: .priority,
      type: .type
    }
  '
}

# Get task by ID
get_task_by_id() {
  local task_id="$1"
  if [[ "$USE_BEADS" == "true" ]]; then
    br show "$task_id" --json 2>/dev/null | jq -r '{
      id: .id,
      subject: .title,
      description: (.description // ""),
      tags: ((.labels // []) | map(ascii_downcase))
    }'
  else
    jq -r --arg id "$task_id" '.tasks[] | select(.id == $id)' "$TASK_GRAPH"
  fi
}

# Mark task as completed
mark_task_completed() {
  local task_id="$1"
  if [[ "$USE_BEADS" == "true" ]]; then
    br close "$task_id" --reason "completed" 2>/dev/null || true
    log_success "Closed beads task $task_id"
  else
    local tmp=$(mktemp)
    jq --arg id "$task_id" '
      .tasks = [.tasks[] | if .id == $id then .status = "completed" else . end]
    ' "$TASK_GRAPH" > "$tmp" && mv "$tmp" "$TASK_GRAPH"
    log_success "Marked task $task_id as completed"
  fi
}

# Mark task as failed
mark_task_failed() {
  local task_id="$1"
  if [[ "$USE_BEADS" == "true" ]]; then
    br update "$task_id" --status blocked --comment "Failed during Ralph execution" 2>/dev/null || true
    log_warn "Marked beads task $task_id as blocked (failed)"
  else
    local tmp=$(mktemp)
    jq --arg id "$task_id" '
      .tasks = [.tasks[] | if .id == $id then .status = "failed" else . end]
    ' "$TASK_GRAPH" > "$tmp" && mv "$tmp" "$TASK_GRAPH"
    log_warn "Marked task $task_id as failed"
  fi
}

# Mark task as in_progress
mark_task_in_progress() {
  local task_id="$1"
  if [[ "$USE_BEADS" == "true" ]]; then
    br update "$task_id" --status in_progress 2>/dev/null || true
  else
    local tmp=$(mktemp)
    jq --arg id "$task_id" '
      .tasks = [.tasks[] | if .id == $id then .status = "in_progress" else . end]
    ' "$TASK_GRAPH" > "$tmp" && mv "$tmp" "$TASK_GRAPH"
  fi
}

# Track task start time for stall detection
# Uses a file for persistence across script restarts
TASK_TRACKING_FILE="$PROJECT_ROOT/.ralph-task-tracking.json"

# Initialize tracking file if needed
init_task_tracking() {
  if [[ ! -f "$TASK_TRACKING_FILE" ]]; then
    echo '{}' > "$TASK_TRACKING_FILE"
  fi
}

# Record when a task starts (persists to file)
record_task_start() {
  local task_id="$1"
  init_task_tracking
  local now=$(date +%s)
  local tmp=$(mktemp)
  jq --arg id "$task_id" --arg ts "$now" '.[$id] = ($ts | tonumber)' "$TASK_TRACKING_FILE" > "$tmp" && mv "$tmp" "$TASK_TRACKING_FILE"
}

# Clear task tracking (on completion or failure)
clear_task_tracking() {
  local task_id="$1"
  if [[ -f "$TASK_TRACKING_FILE" ]]; then
    local tmp=$(mktemp)
    jq --arg id "$task_id" 'del(.[$id])' "$TASK_TRACKING_FILE" > "$tmp" && mv "$tmp" "$TASK_TRACKING_FILE"
  fi
}

# Check if a task has stalled (exceeded STALL_THRESHOLD)
check_task_stalled() {
  local task_id="$1"
  init_task_tracking
  
  local start_time
  start_time=$(jq -r --arg id "$task_id" '.[$id] // 0' "$TASK_TRACKING_FILE" 2>/dev/null || echo "0")
  
  if [[ "$start_time" -eq 0 ]]; then
    return 1  # No start time recorded, not stalled
  fi
  
  local now=$(date +%s)
  local elapsed_minutes=$(( (now - start_time) / 60 ))
  
  if [[ "$elapsed_minutes" -ge "$STALL_THRESHOLD" ]]; then
    log_warn "Task $task_id has been tracked for $elapsed_minutes minutes (threshold: $STALL_THRESHOLD)"
    return 0  # Stalled
  fi
  
  return 1  # Not stalled
}

# Get all tracked task IDs
get_tracked_tasks() {
  init_task_tracking
  jq -r 'keys[]' "$TASK_TRACKING_FILE" 2>/dev/null || true
}

# Handle stalled task - reset and prepare for retry with hints
handle_stalled_task() {
  local task_id="$1"
  local attempt="${2:-1}"
  
  log_warn "Self-healing stalled task: $task_id (attempt $attempt)"
  
  # Reset task to pending
  if [[ "$USE_BEADS" == "true" ]]; then
    br update "$task_id" --status open --comment "Self-healed after stall (attempt $attempt)" 2>/dev/null || true
  else
    local tmp=$(mktemp)
    jq --arg id "$task_id" --arg attempt "$attempt" '
      .tasks = [.tasks[] | if .id == $id then .status = "pending" | .healAttempt = ($attempt | tonumber) else . end]
    ' "$TASK_GRAPH" > "$tmp" && mv "$tmp" "$TASK_GRAPH"
  fi
  
  # Clear the tracking
  clear_task_tracking "$task_id"
  
  # Log the self-heal event
  {
    echo ""
    echo "### Self-Heal Event - $(date -Iseconds)"
    echo "- Task: $task_id"
    echo "- Reason: Stalled (exceeded ${STALL_THRESHOLD}m threshold)"
    echo "- Action: Reset to pending for retry"
    echo "- Attempt: $attempt"
  } >> "$PROGRESS_FILE"
}

# Create PR for completed task
create_auto_pr() {
  local task_id="$1"
  local subject="$2"
  
  if [[ "${AUTO_PR:-true}" != "true" ]]; then
    return 0
  fi
  
  # Check if gh CLI is available
  if ! command -v gh &>/dev/null; then
    log_warn "gh CLI not found - skipping auto-PR (install with: brew install gh)"
    return 0
  fi
  
  # Check if authenticated
  if ! gh auth status &>/dev/null; then
    log_warn "gh CLI not authenticated - skipping auto-PR (run: gh auth login)"
    return 0
  fi
  
  # Check if there are changes to commit
  if [[ -z "$(git status --porcelain)" ]]; then
    log_info "No changes to commit - skipping PR"
    return 0
  fi
  
  local branch_name="task/${task_id}"
  local safe_subject=$(echo "$subject" | tr -cd '[:alnum:] ._-' | cut -c1-50)
  
  log_info "Creating PR for task $task_id..."
  
  # First, stash any uncommitted changes
  git stash push -u -m "ralph-auto-pr-temp" 2>/dev/null || true
  
  # Switch to base branch and pull latest
  git checkout "${PR_BASE_BRANCH:-main}" 2>/dev/null || {
    log_warn "Could not switch to base branch ${PR_BASE_BRANCH:-main}"
    git stash pop 2>/dev/null || true
    return 1
  }
  git pull --ff-only 2>/dev/null || true
  
  # Create feature branch from base
  git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name" 2>/dev/null || {
    log_warn "Could not create/switch to branch $branch_name"
    git stash pop 2>/dev/null || true
    return 1
  }
  
  # Apply stashed changes
  git stash pop 2>/dev/null || true
  
  # Stage and commit all changes
  git add -A
  git commit -m "feat($task_id): $safe_subject

Automated commit by Ralph autonomous execution loop.

Task ID: $task_id
Subject: $subject
Timestamp: $(date -Iseconds)" || {
    log_warn "Nothing to commit"
    git checkout "${PR_BASE_BRANCH:-main}" 2>/dev/null || true
    return 0
  }
  
  # Push branch
  git push -u origin "$branch_name" 2>/dev/null || {
    log_warn "Could not push branch $branch_name"
    git checkout "${PR_BASE_BRANCH:-main}" 2>/dev/null || true
    return 1
  }
  
  # Create PR
  local pr_url
  pr_url=$(gh pr create \
    --base "${PR_BASE_BRANCH:-main}" \
    --head "$branch_name" \
    --title "feat($task_id): $safe_subject" \
    --body "## Task: $task_id

**Subject:** $subject

---

*Automated PR created by Ralph autonomous execution loop.*

### Checklist
- [ ] Code review
- [ ] Tests pass
- [ ] Ready to merge" 2>&1) || {
    log_warn "Could not create PR: $pr_url"
    git checkout "${PR_BASE_BRANCH:-main}" 2>/dev/null || true
    return 1
  }
  
  log_success "PR created: $pr_url"
  
  # Switch back to base branch
  git checkout "${PR_BASE_BRANCH:-main}" 2>/dev/null || true
  
  # Log to progress
  {
    echo "- PR: $pr_url"
  } >> "$PROGRESS_FILE"
  
  return 0
}

# Capture learnings from task execution
capture_learnings() {
  local task_id="$1"
  local subject="$2"
  local tool="$3"
  local output="$4"
  
  # Extract any learnings/notes from the output
  local learnings=""
  
  # Look for learning markers in output
  if echo "$output" | grep -q "LEARNING:\|NOTE:\|INSIGHT:\|TIP:"; then
    learnings=$(echo "$output" | grep -E "LEARNING:|NOTE:|INSIGHT:|TIP:" | head -10)
  fi
  
  # Record to learnings file
  {
    echo ""
    echo "## $(date -Iseconds) - $task_id"
    echo ""
    echo "**Task:** $subject"
    echo ""
    echo "**Tool:** $tool"
    echo ""
    if [[ -n "$learnings" ]]; then
      echo "**Learnings:**"
      echo "$learnings"
      echo ""
    fi
    echo "**Patterns:**"
    echo "- Task type: $(echo "$subject" | grep -oE '\[[^]]*\]' | head -1 || echo 'general')"
    echo "- Completion: success"
    echo ""
    echo "---"
  } >> "$LEARNINGS_FILE"
}

# =============================================================================
# BUILD VERIFICATION (CRITICAL)
# =============================================================================
# After each task, verify the project still builds.
# This catches integration issues, type mismatches, and broken imports.
# Without this, tasks can be marked "complete" while the app doesn't compile!

# Check if npm script exists in package.json
has_npm_script() {
  local script="$1"
  [[ -f "package.json" ]] || return 1
  command -v node &>/dev/null || return 1
  node -e 'const p=require("./package.json"); const s=process.argv[1]; process.exit(((p.scripts||{})[s])?0:1)' "$script" 2>/dev/null
}

# Verify the project builds successfully
# Returns 0 on success, 1 on failure
verify_build() {
  local task_id="$1"
  local log_file="$LOGS_DIR/${task_id}-build.log"

  # Ensure log directory exists
  mkdir -p "$LOGS_DIR" 2>/dev/null || true

  # Skip if not a Node project
  if [[ ! -f "package.json" ]]; then
    log_info "No package.json - skipping build verification"
    return 0
  fi

  log_info "╔════════════════════════════════════════════════════════════════╗"
  log_info "║               BUILD VERIFICATION                               ║"
  log_info "╚════════════════════════════════════════════════════════════════╝"

  local build_passed=true
  local typecheck_passed=true
  local lint_passed=true
  local build_output=""
  local typecheck_output=""
  local lint_output=""

  # Step 0: Lint (catches code quality issues early)
  if [[ "${VERIFY_LINT:-true}" == "true" ]]; then
    log_info "Running lint..."

    if has_npm_script "lint"; then
      set +e
      lint_output=$(npm run lint 2>&1)
      local lint_exit=$?
      set -e

      if [[ $lint_exit -eq 0 ]]; then
        log_success "✅ Lint PASSED"
      else
        # Lint failed - could be errors or warnings exceeding max-warnings
        # Count actual error lines (format: "file:line:col  error  message")
        local error_lines=$(echo "$lint_output" | grep -cE "^\s*[0-9]+:[0-9]+\s+error\s" || echo "0")
        # Also check for summary line like "X errors"
        local summary_errors=$(echo "$lint_output" | grep -oE "[0-9]+ errors?" | head -1 | grep -oE "[0-9]+" || echo "0")

        if [[ "$error_lines" -gt 0 || "$summary_errors" -gt 0 ]]; then
          local total_errors=$((error_lines > summary_errors ? error_lines : summary_errors))
          log_error "❌ Lint FAILED ($total_errors errors)"
          lint_passed=false
          # Show first few error lines
          echo "$lint_output" | grep -E "error" | head -5 | while read -r line; do
            log_error "   $line"
          done
        else
          # Lint failed but no errors found - likely max-warnings exceeded
          log_warn "⚠️ Lint failed (likely max-warnings exceeded)"
          log_warn "   This may indicate too many warnings - consider fixing them"
          # Don't fail the task for warnings, but log it
        fi
      fi

      # Log full output
      {
        echo "=== Lint Output ==="
        echo "$lint_output"
        echo ""
      } >> "$log_file"
    else
      log_info "⏭️ Lint skipped (no lint script)"
    fi
  fi

  # Step 1: TypeCheck (faster, catches most issues)
  if [[ "${VERIFY_TYPECHECK:-true}" == "true" ]]; then
    log_info "Running typecheck..."

    if has_npm_script "typecheck"; then
      set +e
      typecheck_output=$(npm run typecheck 2>&1)
      local typecheck_exit=$?
      set -e

      if [[ $typecheck_exit -eq 0 ]]; then
        log_success "✅ TypeCheck PASSED"
      else
        log_error "❌ TypeCheck FAILED"
        typecheck_passed=false
        # Extract error count
        local error_count=$(echo "$typecheck_output" | grep -c "error TS" || echo "unknown")
        log_error "   TypeScript errors: $error_count"
        # Show first few errors
        echo "$typecheck_output" | grep "error TS" | head -5 | while read -r line; do
          log_error "   $line"
        done
      fi

      # Log full output
      {
        echo "=== TypeCheck Output ==="
        echo "$typecheck_output"
        echo ""
      } >> "$log_file"

    elif [[ -f "tsconfig.json" ]] && command -v tsc &>/dev/null; then
      set +e
      typecheck_output=$(tsc --noEmit 2>&1)
      local typecheck_exit=$?
      set -e

      if [[ $typecheck_exit -eq 0 ]]; then
        log_success "✅ TypeCheck PASSED (tsc --noEmit)"
      else
        log_error "❌ TypeCheck FAILED (tsc --noEmit)"
        typecheck_passed=false
      fi

      {
        echo "=== TypeCheck Output (tsc) ==="
        echo "$typecheck_output"
        echo ""
      } >> "$log_file"
    else
      log_info "⏭️ TypeCheck skipped (no typecheck script)"
    fi
  fi

  # Step 2: Full Build
  if [[ "${VERIFY_BUILD:-true}" == "true" ]]; then
    log_info "Running build..."

    if has_npm_script "build"; then
      set +e
      build_output=$(npm run build 2>&1)
      local build_exit=$?
      set -e

      if [[ $build_exit -eq 0 ]]; then
        log_success "✅ Build PASSED"
      else
        log_error "❌ Build FAILED"
        build_passed=false
        # Show last few lines of build output
        echo "$build_output" | tail -10 | while read -r line; do
          log_error "   $line"
        done
      fi

      # Log full output
      {
        echo "=== Build Output ==="
        echo "$build_output"
        echo ""
      } >> "$log_file"
    else
      log_info "⏭️ Build skipped (no build script)"
    fi
  fi

  # Step 3: Run Tests (CRITICAL for TDD verification)
  local tests_passed=true
  if [[ "${VERIFY_TESTS:-true}" == "true" ]]; then
    log_info "Running tests..."

    if has_npm_script "test"; then
      set +e
      local test_output
      test_output=$(npm run test 2>&1)
      local test_exit=$?
      set -e

      if [[ $test_exit -eq 0 ]]; then
        log_success "✅ Tests PASSED"
      else
        log_error "❌ Tests FAILED"
        tests_passed=false
        # Show first few failure lines
        echo "$test_output" | grep -iE "fail|error|✗" | head -5 | while read -r line; do
          log_error "   $line"
        done
      fi

      # Log full output
      {
        echo "=== Test Output ==="
        echo "$test_output"
        echo ""
      } >> "$log_file"
    else
      log_info "⏭️ Tests skipped (no test script)"
    fi
  fi

  # Check if we actually ran any verification
  local ran_lint=false
  local ran_typecheck=false
  local ran_build=false
  local ran_tests=false

  if [[ "${VERIFY_LINT:-true}" == "true" ]] && has_npm_script "lint"; then
    ran_lint=true
  fi

  if [[ "${VERIFY_TYPECHECK:-true}" == "true" ]]; then
    if has_npm_script "typecheck" || { [[ -f "tsconfig.json" ]] && command -v tsc &>/dev/null; }; then
      ran_typecheck=true
    fi
  fi

  if [[ "${VERIFY_BUILD:-true}" == "true" ]] && has_npm_script "build"; then
    ran_build=true
  fi

  if [[ "${VERIFY_TESTS:-true}" == "true" ]] && has_npm_script "test"; then
    ran_tests=true
  fi

  if [[ "$ran_lint" == "false" && "$ran_typecheck" == "false" && "$ran_build" == "false" && "$ran_tests" == "false" ]]; then
    log_warn "⚠️ No verification was performed (no lint, typecheck, build, or test scripts found)"
    log_warn "   Consider adding these scripts to package.json"
  fi

  # Step 3: Check for suspicious changes (anti-pattern detection)
  # Only run if we're in a git repo with commits
  if git rev-parse HEAD~1 &>/dev/null; then
    log_info "Checking for suspicious changes..."

    local suspicious_changes=false
    local suspicious_warnings=""

    # Check if lint config was modified to disable rules
    # Look for added lines containing 'off' in eslint configs
    if git diff --name-only HEAD~1 2>/dev/null | grep -qiE "eslint|\.eslintrc"; then
      local lint_diff=$(git diff HEAD~1 -- '*eslint*' '*eslintrc*' 2>/dev/null || true)
      # Only flag if we see ADDED lines (starting with +) that disable rules
      if echo "$lint_diff" | grep -E '^\+.*["'"'"']off["'"'"']' | grep -qv "^+++"; then
        suspicious_changes=true
        suspicious_warnings+="  - Lint rules were disabled (added 'off')\n"
        log_warn "⚠️ SUSPICIOUS: Lint config modified to disable rules"
      fi
    fi

    # Check if max-warnings was increased in package.json
    if git diff --name-only HEAD~1 2>/dev/null | grep -q "package.json"; then
      local pkg_diff=$(git diff HEAD~1 -- package.json 2>/dev/null || true)
      # Look for added lines with max-warnings > 0
      if echo "$pkg_diff" | grep -E '^\+.*max-warnings['"'"'" ]+[1-9]' | grep -qv "^+++"; then
        suspicious_changes=true
        suspicious_warnings+="  - max-warnings was increased (errors may be hidden)\n"
        log_warn "⚠️ SUSPICIOUS: max-warnings increased in package.json"
      fi
    fi

    # Check if tsconfig was modified to skip checks
    if git diff --name-only HEAD~1 2>/dev/null | grep -qE "tsconfig"; then
      local ts_diff=$(git diff HEAD~1 -- '*tsconfig*' 2>/dev/null || true)
      # Look for added lines that weaken type checking
      if echo "$ts_diff" | grep -E '^\+.*(skipLibCheck.*true|noImplicitAny.*false|strict.*false)' | grep -qv "^+++"; then
        suspicious_changes=true
        suspicious_warnings+="  - TypeScript strictness was reduced\n"
        log_warn "⚠️ SUSPICIOUS: TypeScript config weakened"
      fi
    fi

    if [[ "$suspicious_changes" == "true" ]]; then
      log_warn "╔════════════════════════════════════════════════════════════════╗"
      log_warn "║         ⚠️ SUSPICIOUS CHANGES DETECTED                         ║"
      log_warn "╚════════════════════════════════════════════════════════════════╝"
      log_warn "The agent may be hiding errors instead of fixing them:"
      echo -e "$suspicious_warnings" | while read -r line; do
        [[ -n "$line" ]] && log_warn "$line"
      done
      log_warn "Review the changes carefully before accepting."

      # Log to progress file
      {
        echo ""
        echo "### SUSPICIOUS CHANGES - $(date -Iseconds)"
        echo "- Task: $task_id"
        echo -e "$suspicious_warnings"
      } >> "$PROGRESS_FILE"
    fi
  fi

  # Determine overall result
  if [[ "$lint_passed" == "true" && "$typecheck_passed" == "true" && "$build_passed" == "true" && "$tests_passed" == "true" ]]; then
    log_success "╔════════════════════════════════════════════════════════════════╗"
    log_success "║           ✅ BUILD VERIFICATION PASSED                         ║"
    log_success "╚════════════════════════════════════════════════════════════════╝"
    BUILD_FAIL_COUNT=0
    return 0
  else
    log_error "╔════════════════════════════════════════════════════════════════╗"
    log_error "║           ❌ BUILD VERIFICATION FAILED                          ║"
    log_error "╚════════════════════════════════════════════════════════════════╝"
    log_error "Full build log: $log_file"

    # Track consecutive failures
    BUILD_FAIL_COUNT=$((BUILD_FAIL_COUNT + 1))

    # Log to progress file
    {
      echo ""
      echo "### BUILD FAILURE - $(date -Iseconds)"
      echo "- Task: $task_id"
      echo "- Lint: $([ "$lint_passed" == "true" ] && echo "PASS" || echo "FAIL")"
      echo "- TypeCheck: $([ "$typecheck_passed" == "true" ] && echo "PASS" || echo "FAIL")"
      echo "- Build: $([ "$build_passed" == "true" ] && echo "PASS" || echo "FAIL")"
      echo "- Tests: $([ "$tests_passed" == "true" ] && echo "PASS" || echo "FAIL")"
      echo "- Consecutive failures: $BUILD_FAIL_COUNT"
    } >> "$PROGRESS_FILE"

    return 1
  fi
}

# Count tasks by status
count_tasks() {
  local status="$1"
  if [[ "$USE_BEADS" == "true" ]]; then
    # Map our status to beads status
    local br_status="$status"
    case "$status" in
      pending) br_status="open" ;;
      completed) br_status="closed" ;;
      in_progress) br_status="in_progress" ;;
      failed) br_status="blocked" ;;
    esac
    br list --status "$br_status" --json 2>/dev/null | jq 'length' || echo "0"
  else
    jq --arg s "$status" '[.tasks[] | select(.status == $s)] | length' "$TASK_GRAPH"
  fi
}

# Get learnings from current session to inject into prompt
# Uses SESSION_LEARNINGS_START_LINE set at Ralph startup to get ALL learnings
# from this build session, not just an arbitrary "last N" count
get_recent_learnings() {
  # Parameter is now optional max_lines safeguard (default 200)
  local max_lines="${1:-200}"

  if [[ ! -f "$LEARNINGS_FILE" ]]; then
    echo ""
    return
  fi

  # Defensive: if SESSION_LEARNINGS_START_LINE not set, default to 0 (get all)
  local start_line="${SESSION_LEARNINGS_START_LINE:-0}"

  # Get current file line count
  local current_lines
  current_lines=$(wc -l < "$LEARNINGS_FILE" | tr -d ' ')

  # Calculate how many new lines since session started
  local new_lines=$((current_lines - start_line))

  if [[ "$new_lines" -le 0 ]]; then
    echo ""
    return
  fi

  # Get all lines added since session start (these are THIS session's learnings)
  # Apply max_lines safeguard to prevent prompt explosion
  if [[ "$new_lines" -gt "$max_lines" ]]; then
    # If too many, get most recent max_lines
    tail -n "$max_lines" "$LEARNINGS_FILE" 2>/dev/null
  else
    # Get all session learnings
    tail -n "$new_lines" "$LEARNINGS_FILE" 2>/dev/null
  fi
}

# Get recent progress context
get_recent_progress() {
  local max_lines="${1:-20}"

  if [[ ! -f "$PROGRESS_FILE" ]]; then
    echo ""
    return
  fi

  # Get the last N lines of meaningful progress (skip blank lines)
  tail -n "$max_lines" "$PROGRESS_FILE" 2>/dev/null | grep -v '^$' | head -15
}

# Generate prompt for AI tool
generate_prompt() {
  local task_json="$1"
  local task_id=$(echo "$task_json" | jq -r '.id')
  local subject=$(echo "$task_json" | jq -r '.subject')
  local description=$(echo "$task_json" | jq -r '.description // ""')
  local deliverable=$(echo "$task_json" | jq -r '.deliverable // ""')
  local allowed_paths=$(echo "$task_json" | jq -r '(.allowedPaths // []) | join(", ")')
  if [[ -z "$allowed_paths" ]]; then
    allowed_paths="(not specified — keep changes minimal and scoped)"
  fi
  local verification=$(echo "$task_json" | jq -r '(.verification // []) | join("\n- ")')
  if [[ -z "$verification" ]]; then
    verification="(not specified — add an appropriate verification step)"
  fi
  local setup=$(echo "$task_json" | jq -r '.setup // ""')
  local tags=$(echo "$task_json" | jq -r '(.tags // []) | join(", ")')

  # Get ALL learnings from this session plus recent progress
  local recent_learnings
  recent_learnings=$(get_recent_learnings)  # All session learnings (up to 200 lines safeguard)
  local recent_progress
  recent_progress=$(get_recent_progress 15)

  cat << EOF
You are an autonomous coding agent working on task: $task_id

## Task
**$subject**

## Tags
$tags

## Description
$description

## Deliverable
$deliverable

## Allowed Paths
Only modify files in: $allowed_paths

## Setup (if needed)
$setup

## Verification / Acceptance Criteria
- $verification

$(if [[ -n "$recent_learnings" ]] || [[ -n "$recent_progress" ]]; then
echo "## Context from This Build Session"
echo ""
if [[ -n "$recent_learnings" ]]; then
echo "### Learnings (all from this session)"
echo "These are ALL learnings captured during this Ralph run - even early ones may be relevant."
echo ""
echo "$recent_learnings"
echo ""
fi
if [[ -n "$recent_progress" ]]; then
echo "### Recent Progress"
echo "\`\`\`"
echo "$recent_progress"
echo "\`\`\`"
echo ""
fi
fi)

$(# Inject UI quality requirements for frontend tasks
if echo "$tags" | grep -qiE "ui|component|frontend|design|css|style|ux"; then
cat << 'UIQUALITY'
## 🎨 UI/UX Quality Requirements (CRITICAL)

This is a UI task. You must do a **spectacular job** building absolutely world-class
UI/UX components with an intense focus on making the most visually appealing,
user-friendly, intuitive, slick, polished, "Stripe level" of quality possible.

**Quality Bar** (what we're aiming for):
- **Stripe**: Clean, confident, spacious, purposeful animations
- **Linear**: Fast, keyboard-first, beautiful dark mode, crisp icons
- **Vercel**: Minimal, elegant, excellent typography, subtle gradients

**Mandatory Considerations**:
1. **Visual Polish**: Perfect spacing, alignment, typography, color harmony
2. **Micro-interactions**: Smooth hover states, transitions, loading states
3. **Accessibility**: WCAG compliance, focus states, screen reader support
4. **Responsiveness**: Mobile-first, proper breakpoints, touch-friendly
5. **Consistency**: Follow existing design system and component patterns
6. **Delight**: Make it feel premium - users should say "wow"

**Edge Cases to Handle**:
- Empty states (no data)
- Loading states (skeleton, spinner)
- Error states (clear, actionable)
- Long content (truncation, overflow)
- Keyboard navigation

Leverage the good libraries already in the project. Do not compromise on quality.
UIQUALITY
fi)

## Instructions

1. Review the context above from previous iterations
2. Implement the task following the description
3. Run the verification commands to confirm success
4. **MANDATORY: Run build verification** (see below)
5. If all verifications pass, output <promise>TASK_COMPLETE</promise>
   (Do NOT commit or push - Ralph handles branching/commits/PRs)

## Critical Rules

- Only modify files in allowed paths
- Run ALL verification commands before committing
- If verification fails, fix the issue and retry
- If you cannot complete the task, explain why clearly

## ❌ FORBIDDEN ANTI-PATTERNS ❌

DO NOT do any of the following to "pass" verification:

1. **DO NOT disable lint rules** - Fix the actual issues, don't add 'off' rules
2. **DO NOT increase max-warnings** - Fix warnings, don't hide them
3. **DO NOT weaken TypeScript config** - Don't add skipLibCheck, don't disable strict mode
4. **DO NOT modify test files to skip failing tests** - Fix the code, not the tests
5. **DO NOT create mock implementations** that don't match real behavior

If you find yourself wanting to do any of these, STOP and either:
- Fix the root cause
- Output TASK_BLOCKED with an explanation

The orchestrator will detect these patterns and REJECT the task.

## ⚠️ MANDATORY BUILD VERIFICATION ⚠️

Before outputting TASK_COMPLETE, you MUST run these commands and they MUST pass:

\`\`\`bash
# 1. Lint - catches code quality issues
npm run lint 2>&1

# 2. TypeCheck - catches type errors, missing imports, interface mismatches
npm run typecheck 2>&1 || tsc --noEmit 2>&1

# 3. Build - catches compilation errors that dev mode misses
npm run build 2>&1
\`\`\`

**If ANY command fails, DO NOT output TASK_COMPLETE.**
Instead, fix the errors and re-run until all pass.

Common issues to watch for:
- Missing required props on components
- Type mismatches between files
- Imports from non-existent files
- Interface changes that break callers

The orchestrator will verify the build after you report completion.
If the build fails, your task will be marked as FAILED even if you said TASK_COMPLETE.

## Learnings (Optional)

If you discover something useful, output it with a marker:
- LEARNING: <what you learned>
- NOTE: <important observation>
- TIP: <helpful hint for future tasks>

## When Complete

If ALL verification commands pass and build passes:
Output exactly: <promise>TASK_COMPLETE</promise>
(Do NOT commit - Ralph handles git operations via auto-PR)

If you cannot complete the task:
Output exactly: <promise>TASK_FAILED</promise>
And explain why.
EOF
}

# Print status summary
print_status() {
  local completed=$(count_tasks "completed")
  local pending=$(count_tasks "pending")
  local in_progress=$(count_tasks "in_progress")
  local failed=$(count_tasks "failed")
  local total=0
  local pct=0
  local task_source="task-graph.json"
  
  if [[ "$USE_BEADS" == "true" ]]; then
    # For beads, total is sum of all statuses
    total=$((completed + pending + in_progress + failed))
    task_source="beads_rust (br)"
  else
    total=$(jq '.tasks | length' "$TASK_GRAPH" 2>/dev/null || echo "0")
  fi
  
  if [[ "$total" -gt 0 ]]; then
    pct=$((completed * 100 / total))
  fi
  
  echo ""
  echo "╔════════════════════════════════════════════════════╗"
  echo "║               RALPH STATUS                         ║"
  echo "╠════════════════════════════════════════════════════╣"
  printf "║  Completed:   %-5s   Pending:    %-5s            ║\n" "$completed" "$pending"
  printf "║  In Progress: %-5s   Failed:     %-5s            ║\n" "$in_progress" "$failed"
  printf "║  Total:       %-5s   Progress:   %3d%%             ║\n" "$total" "$pct"
  printf "║  Tool:        %-40s ║\n" "$TOOL"
  printf "║  Tasks:       %-40s ║\n" "$task_source"
  echo "╚════════════════════════════════════════════════════╝"
  echo ""
}

# Main loop
main() {
  parse_args "$@"
  check_prerequisites
  init_progress

  # Track session start for learning injection
  # We want ALL learnings from THIS session, not just last N
  SESSION_LEARNINGS_START_LINE=0
  if [[ -f "$LEARNINGS_FILE" ]]; then
    SESSION_LEARNINGS_START_LINE=$(wc -l < "$LEARNINGS_FILE" | tr -d ' ')
  fi

  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║              RALPH LOOP - AUTONOMOUS EXECUTION                 ║"
  echo "║                                                                ║"
  echo "║  Based on Geoffrey Huntley's Ralph pattern                     ║"
  echo "║  Fresh context each iteration • Memory via git + progress.txt ║"
  echo "╠════════════════════════════════════════════════════════════════╣"
  echo "║  WATCH LOGS:                                                   ║"
  echo "║    tail -f .beads/logs/*.log     # All tasks                   ║"
  echo "║    tail -f progress.txt          # Summary                     ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  log_info "Tool mode: $TOOL"
  if [[ "$TOOL" == "smart" ]]; then
    log_info "  Backend tasks  → $BACKEND_TOOL"
    log_info "  Frontend tasks → $FRONTEND_TOOL"
  fi
  if [[ "$USE_BEADS" == "true" ]]; then
    log_info "Task source: beads (br ready)"
  else
    log_info "Task source: $TASK_GRAPH"
  fi
  log_info "Max iterations: $MAX_ITERATIONS"
  
  print_status
  
  for ((i=1; i<=MAX_ITERATIONS; i++)); do
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "ITERATION $i of $MAX_ITERATIONS"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # SELF-HEAL: Check for stalled tasks and recover them
    if [[ "${SELF_HEAL:-true}" == "true" ]]; then
      local heal_attempt
      while IFS= read -r stalled_task_id; do
        [[ -z "$stalled_task_id" ]] && continue
        if check_task_stalled "$stalled_task_id"; then
          # Get current heal attempt count
          heal_attempt=1
          if [[ "$USE_BEADS" != "true" ]]; then
            heal_attempt=$(jq -r --arg id "$stalled_task_id" '.tasks[] | select(.id == $id) | .healAttempt // 0' "$TASK_GRAPH" 2>/dev/null || echo "0")
            heal_attempt=$((heal_attempt + 1))
          fi
          
          if [[ "$heal_attempt" -le 3 ]]; then
            handle_stalled_task "$stalled_task_id" "$heal_attempt"
          else
            log_error "Task $stalled_task_id has failed self-heal 3 times - marking as failed"
            mark_task_failed "$stalled_task_id"
            clear_task_tracking "$stalled_task_id"
          fi
        fi
      done < <(get_tracked_tasks)
    fi
    
    # Get next task
    local task_json=$(get_next_task)
    
    if [[ -z "$task_json" || "$task_json" == "null" ]]; then
      # Check if all done or all blocked
      local pending=$(count_tasks "pending")
      local completed=$(count_tasks "completed")
      
      if [[ "$pending" -eq 0 ]]; then
        echo ""
        log_success "╔════════════════════════════════════════════════════╗"
        log_success "║          🎉 ALL TASKS COMPLETED! 🎉                ║"
        log_success "╚════════════════════════════════════════════════════╝"
        print_status

        # Final summary to progress file
        {
          echo ""
          echo "---"
          echo "## Session Complete - $(date -Iseconds)"
          echo ""
          echo "- All tasks completed successfully!"
          echo "- Iterations used: $i"
          echo "- Total completed: $(count_tasks 'completed')"
          echo "- Build failures during session: $BUILD_FAIL_COUNT"
          echo ""
        } >> "$PROGRESS_FILE"

        echo "<promise>COMPLETE</promise>"
        exit 0
      else
        log_warn "All remaining tasks are blocked. Check dependencies."
        print_status

        # Log to progress
        {
          echo ""
          echo "---"
          echo "## Session Blocked - $(date -Iseconds)"
          echo ""
          echo "- Status: All remaining tasks are blocked"
          echo "- Completed: $(count_tasks 'completed')"
          echo "- Pending (blocked): $pending"
          echo "- Build failures: $BUILD_FAIL_COUNT"
          echo ""
          echo "Check task dependencies and failed tasks."
        } >> "$PROGRESS_FILE"

        exit 1
      fi
    fi
    
    local task_id=$(echo "$task_json" | jq -r '.id')
    local subject=$(echo "$task_json" | jq -r '.subject')
    local tags=$(echo "$task_json" | jq -r '(.tags // []) | join(", ")')
    
    log_info "Task: $task_id"
    log_info "Subject: $subject"
    log_info "Tags: $tags"
    
    # Determine which tool to use
    local selected_tool=$(get_tool_for_task "$task_json")
    
    # Mark as in progress and record start time for stall detection
    mark_task_in_progress "$task_id"
    record_task_start "$task_id"
    
    # Generate prompt
    local prompt=$(generate_prompt "$task_json")
    
    # Save prompt for debugging
    echo "$prompt" > "/tmp/ralph-prompt-$task_id.md"
    
    # Set current task for logging
    CURRENT_TASK_ID="$task_id"
    
    # Run with selected tool
    log_info "Spawning $selected_tool instance..."
    log_info "Log file: $LOGS_DIR/${task_id}.log"
    
    set +e
    OUTPUT=$(run_with_tool "$selected_tool" "$prompt")
    set -e
    
    # Clear current task ID
    CURRENT_TASK_ID=""
    
    # Check for completion signal
    if echo "$OUTPUT" | grep -q "<promise>TASK_COMPLETE</promise>"; then
      log_info "Agent reports task complete. Verifying build..."

      # CRITICAL: Verify build BEFORE any reviews
      # This catches TypeScript errors, broken imports, and integration issues
      if ! verify_build "$task_id"; then
        # Build failed - task is NOT complete despite agent's claim
        log_error "Build verification FAILED - task is NOT complete!"
        log_error "The agent said TASK_COMPLETE but the code doesn't compile."

        # Mark task as failed (not completed!)
        mark_task_failed "$task_id"

        # Clear stall tracking
        clear_task_tracking "$task_id"

        # Log to progress
        {
          echo ""
          echo "### Iteration $i - $(date -Iseconds)"
          echo "- Task: $task_id - $subject"
          echo "- Tool: $selected_tool"
          echo "- Status: ❌ FAILED (build verification)"
          echo "- Agent said: TASK_COMPLETE"
          echo "- But: Build/typecheck/tests failed"
        } >> "$PROGRESS_FILE"

        # Check if too many consecutive build failures
        if [[ "$BUILD_FAIL_COUNT" -ge 3 ]]; then
          log_error "WARNING: $BUILD_FAIL_COUNT consecutive build failures!"
          log_error "The codebase may be in a broken state."
          log_error "Consider manual intervention."
        fi

        # Skip reviews and auto-PR for failed tasks
        print_status
        sleep 2
        continue
      fi

      log_success "Initial build verification passed!"

      # REVIEWS RUN BEFORE MARKING COMPLETE
      # Reviews may modify code (Healer), so we re-verify after

      # COUNCIL OF SUBAGENTS REVIEW (if enabled)
      # Uses specialized subagents: Analyst (quality), Sentinel (anti-patterns), Designer (UI), Healer (fixes)
      local ran_reviews=false
      if [[ "${COUNCIL_REVIEW:-false}" == "true" ]]; then
        ran_reviews=true
        local review_tool="${REVIEW_TOOL:-$selected_tool}"
        log_info "Running Council of Subagents review..."
        if ! run_council_review "$task_id" "$review_tool" "$tags"; then
          log_error "Council review found unfixable issues!"
          log_warn "Consider manual review of council findings"
        fi
      fi

      # FRESH EYES REVIEW (if enabled)
      if [[ "${FRESH_EYES:-false}" == "true" ]]; then
        ran_reviews=true
        local review_tool="${REVIEW_TOOL:-$selected_tool}"
        if [[ -n "$REVIEW_TOOL" && "$REVIEW_TOOL" != "$selected_tool" ]]; then
          log_info "Cross-model review: coded with $selected_tool, reviewing with $review_tool"
        else
          log_info "Running fresh eyes code review..."
        fi
        run_fresh_eyes_review "$review_tool"
      fi

      # RE-VERIFY after reviews (Healer may have modified code)
      if [[ "$ran_reviews" == "true" ]]; then
        log_info "Re-verifying build after reviews..."
        if ! verify_build "$task_id"; then
          log_error "Post-review verification FAILED!"
          log_error "Reviews may have introduced issues."
          mark_task_failed "$task_id"
          clear_task_tracking "$task_id"
          {
            echo ""
            echo "### Iteration $i - $(date -Iseconds)"
            echo "- Task: $task_id - $subject"
            echo "- Tool: $selected_tool"
            echo "- Status: ❌ FAILED (post-review verification)"
          } >> "$PROGRESS_FILE"
          print_status
          sleep 2
          continue
        fi
        log_success "Post-review verification passed!"
      fi

      # ALL CHECKS PASSED - Now mark task as completed
      mark_task_completed "$task_id"

      # Clear stall tracking
      clear_task_tracking "$task_id"

      # Log to progress
      {
        echo ""
        echo "### Iteration $i - $(date -Iseconds)"
        echo "- Task: $task_id - $subject"
        echo "- Tool: $selected_tool"
        echo "- Status: ✅ COMPLETED"
        echo "- Build: ✅ VERIFIED"
      } >> "$PROGRESS_FILE"

      log_success "Task completed and all verifications passed!"

      # Capture learnings from task execution
      capture_learnings "$task_id" "$subject" "$selected_tool" "$OUTPUT"

      # AUTO-PR: Create PR for completed task
      if [[ "${AUTO_PR:-true}" == "true" ]]; then
        create_auto_pr "$task_id" "$subject"
      fi
      
    elif echo "$OUTPUT" | grep -q "<promise>TASK_BLOCKED</promise>"; then
      # Agent reported task is blocked (needs clarification, external dependency, etc.)
      mark_task_failed "$task_id"

      # Clear stall tracking
      clear_task_tracking "$task_id"

      # Log to progress
      {
        echo ""
        echo "### Iteration $i - $(date -Iseconds)"
        echo "- Task: $task_id - $subject"
        echo "- Tool: $selected_tool"
        echo "- Status: ⛔ BLOCKED (agent reported)"
      } >> "$PROGRESS_FILE"

      log_warn "Task blocked. Agent needs clarification or external dependency."
      log_warn "Check agent output for what is needed to proceed."

    elif echo "$OUTPUT" | grep -q "<promise>TASK_FAILED</promise>"; then
      mark_task_failed "$task_id"

      # Clear stall tracking
      clear_task_tracking "$task_id"

      # Log to progress
      {
        echo ""
        echo "### Iteration $i - $(date -Iseconds)"
        echo "- Task: $task_id - $subject"
        echo "- Tool: $selected_tool"
        echo "- Status: ❌ FAILED (agent reported)"
      } >> "$PROGRESS_FILE"

      log_error "Task failed. See output above for details."
      
    else
      # No clear signal - assume incomplete, retry next iteration
      log_warn "No completion signal. Will retry if iterations remain."

      # Log to progress
      {
        echo ""
        echo "### Iteration $i - $(date -Iseconds)"
        echo "- Task: $task_id - $subject"
        echo "- Tool: $selected_tool"
        echo "- Status: ⚠️ NO SIGNAL (will retry)"
      } >> "$PROGRESS_FILE"

      # Reset to pending/open for retry
      if [[ "$USE_BEADS" == "true" ]]; then
        br update "$task_id" --status open 2>/dev/null || true
      else
        local tmp=$(mktemp)
        jq --arg id "$task_id" '
          .tasks = [.tasks[] | if .id == $id then .status = "pending" else . end]
        ' "$TASK_GRAPH" > "$tmp" && mv "$tmp" "$TASK_GRAPH"
      fi
    fi
    
    print_status
    
    # Brief pause between iterations
    sleep 2
  done
  
  echo ""
  log_warn "Max iterations ($MAX_ITERATIONS) reached."
  print_status

  # Final summary to progress file
  {
    echo ""
    echo "---"
    echo "## Session Summary - $(date -Iseconds)"
    echo ""
    echo "- Iterations run: $MAX_ITERATIONS"
    echo "- Completed: $(count_tasks 'completed')"
    echo "- Failed: $(count_tasks 'failed')"
    echo "- Pending: $(count_tasks 'pending')"
    echo "- Build failures: $BUILD_FAIL_COUNT"
    echo ""
    echo "Session ended: max iterations reached"
  } >> "$PROGRESS_FILE"

  exit 1
}

main "$@"
