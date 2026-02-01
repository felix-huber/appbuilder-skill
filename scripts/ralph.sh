#!/usr/bin/env bash
set -euo pipefail

# Ralph Loop for Oracle Swarm Extension
# Autonomous execution of task graph using fresh AI agent contexts.
#
# Based on Geoffrey Huntley's Ralph pattern and snarktank/ralph
# https://github.com/snarktank/ralph
#
# Supports multiple AI coding tools:
#   - Claude Code: claude -p --dangerously-skip-permissions --no-session-persistence
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
#   Claude Code: claude -p --dangerously-skip-permissions --no-session-persistence "<prompt>"
#   Codex CLI:   codex exec --yolo "<prompt>"
#
# Examples:
#   ./scripts/ralph.sh 50                    # 50 iterations with Claude Code
#   ./scripts/ralph.sh --tool codex 50       # Use Codex for all tasks
#   ./scripts/ralph.sh --tool smart 50       # Smart routing by task type
#   ./scripts/ralph.sh --ask 50              # Ask for each task
#   ./scripts/ralph.sh --beads 50            # Use beads for task tracking
#   ./scripts/ralph.sh --auto-push 50        # Push after each commit (recommended for CI sync)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_GRAPH="$PROJECT_ROOT/artifacts/04-task-graph.json"
PROGRESS_FILE="$PROJECT_ROOT/progress.txt"
LEARNINGS_FILE="$PROJECT_ROOT/learnings.md"
LOGS_DIR="$PROJECT_ROOT/.beads/logs"
CURRENT_TASK_ID=""  # Set during execution for logging
SESSION_START_TS=0

# Lockfile to prevent multiple ralph instances from running concurrently
RALPH_LOCK="$PROJECT_ROOT/.ralph.lock"
OVERRIDE_LOCK_PID=""

# Pre-parse --override-lock before acquiring lock (so agents can override without deleting files)
_args=("$@")
for ((i=0; i<${#_args[@]}; i++)); do
  if [[ "${_args[i]}" == "--override-lock" ]] && [[ -n "${_args[i+1]:-}" ]]; then
    OVERRIDE_LOCK_PID="${_args[i+1]}"
    break
  fi
done
unset _args

cleanup_lock() { rm -f "$RALPH_LOCK" 2>/dev/null; }
handle_signal() { exit 130; }  # 130 = 128 + SIGINT(2); EXIT trap handles cleanup
acquire_lock() {
  if [[ -f "$RALPH_LOCK" ]]; then
    local lock_pid
    lock_pid=$(cat "$RALPH_LOCK" 2>/dev/null || echo "")

    # Allow override if user specifies the correct PID
    if [[ -n "$OVERRIDE_LOCK_PID" ]] && [[ "$lock_pid" == "$OVERRIDE_LOCK_PID" ]]; then
      echo "INFO: Overriding lock from PID $lock_pid (--override-lock)" >&2
    elif [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
      echo "ERROR: Another ralph instance is running (PID $lock_pid)" >&2
      echo "Options:" >&2
      echo "  1. Remove lock: rm $RALPH_LOCK" >&2
      echo "  2. Override:    ./scripts/ralph.sh --override-lock $lock_pid [other args]" >&2
      exit 1
    else
      echo "WARN: Removing stale lock from dead process $lock_pid" >&2
    fi
    rm -f "$RALPH_LOCK"
  fi
  echo $$ > "$RALPH_LOCK"
  trap cleanup_lock EXIT
  trap handle_signal INT TERM
}
acquire_lock

# Defaults
MAX_ITERATIONS=20
TOOL="smart"           # smart = route by task type (codex for backend, claude for frontend)
ASK_MODE=false
BACKEND_TOOL="codex"   # Backend/core/api tasks → Codex (fast iteration)
FRONTEND_TOOL="claude" # Frontend/UI/design tasks → Claude Code (nuanced)
USE_BEADS=""  # Empty = auto-detect/interactive, "true" = beads, "false" = task-graph
FRESH_EYES="false"     # Set to "true" for post-task review
REVIEW_TOOL=""         # Empty = same as coding tool, "codex" or "claude" = cross-model review
ALLOW_SAME_REVIEW_TOOL="false"
MIN_REVIEW_PASSES=2
ALLOW_NO_VERIFY="false"
DEFAULT_VERIFY=""
HAS_CLAUDE="false"
HAS_CODEX="false"

# Strict mode features (enabled via --strict or individual flags)
STRICT_MODE="false"    # Enable all strict features at once
CONTINUE_ON_ERROR="false"  # Continue loop even if a task fails
MAX_TASKS=0            # Max tasks to process (0=unlimited)
ALLOW_NO_TESTS="true"  # Allow tasks without test changes (use --strict or --require-tests to enforce)
STALL_MINUTES=45       # Max minutes per tool run (used with timeout)
CURRENT_SUBJECT=""     # Current task subject for loop state tracking
AUTO_COMMIT="true"     # Auto-commit after successful review
AUTO_PUSH="false"      # Push after each commit
COMMIT_PREFIX="feat"   # Commit message prefix
MAX_TASK_ATTEMPTS=3    # Max retry attempts per task
LOOP_STATE_FILE=""     # JSON state file for tracking
SUMMARY_FILE=""        # Markdown summary file

# Self-healing (from task-orchestrator pattern)
SELF_HEAL="true"       # Auto-recover stuck tasks
STALL_THRESHOLD=20     # Minutes before considering a task stuck

# Auto-PR feature
AUTO_PR="true"         # Auto-create PRs when tasks complete (requires gh CLI)
PR_BASE_BRANCH="main"  # Base branch for PRs

# Build verification (CRITICAL for catching broken code)
VERIFY_BUILD="true"    # Run build command after each task (default: true)
VERIFY_TYPECHECK="true" # Run typecheck command after each task (default: true)
VERIFY_LINT="true"     # Run lint command after each task (default: true)
VERIFY_TESTS="true"    # Run npm test after each task (default: true)
SCOPED_TESTS_ONLY="false"  # Skip global npm test if task has scoped verification
BUILD_FAIL_COUNT=0     # Track consecutive build failures
LAST_FAIL_SIGNATURE=""  # Hash of last failure for flaky detection
LAST_FAIL_TASK_ID=""    # Task ID of last failure
SAME_FAIL_COUNT=0       # Count of identical consecutive failures
FLAKY_FAIL_THRESHOLD=3  # Skip task after this many identical failures

# Final E2E regression suite (runs once at end after all tasks complete)
FINAL_E2E="true"       # Run full E2E suite before declaring success (catches regressions)

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
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
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
      --allow-same-review-tool)
        ALLOW_SAME_REVIEW_TOOL="true"
        shift
        ;;
      --allow-no-verify)
        ALLOW_NO_VERIFY="true"
        shift
        ;;
      --default-verify)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--default-verify requires commands (semicolon or newline separated)"
          exit 1
        fi
        DEFAULT_VERIFY="$2"
        shift 2
        ;;
      --min-review-passes)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--min-review-passes requires a numeric value"
          exit 1
        fi
        MIN_REVIEW_PASSES="$2"
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
      --override-lock)
        # Already pre-parsed before acquire_lock, just consume the argument
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--override-lock requires a PID value"
          exit 1
        fi
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
      --scoped-tests-only)
        SCOPED_TESTS_ONLY="true"
        shift
        ;;
      --no-final-e2e)
        FINAL_E2E="false"
        shift
        ;;
      --final-e2e)
        FINAL_E2E="true"
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
      --strict)
        STRICT_MODE="true"
        FRESH_EYES="true"
        ALLOW_NO_TESTS="false"
        AUTO_COMMIT="true"
        shift
        ;;
      --continue-on-error)
        CONTINUE_ON_ERROR="true"
        shift
        ;;
      --max-tasks)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--max-tasks requires a numeric value"
          exit 1
        fi
        MAX_TASKS="$2"
        shift 2
        ;;
      --allow-no-tests)
        ALLOW_NO_TESTS="true"
        shift
        ;;
      --require-tests)
        ALLOW_NO_TESTS="false"
        shift
        ;;
      --stall-minutes)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--stall-minutes requires a numeric value"
          exit 1
        fi
        STALL_MINUTES="$2"
        shift 2
        ;;
      --auto-push)
        AUTO_PUSH="true"
        shift
        ;;
      --no-commit)
        AUTO_COMMIT="false"
        shift
        ;;
      --commit-prefix)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--commit-prefix requires a value"
          exit 1
        fi
        COMMIT_PREFIX="$2"
        shift 2
        ;;
      --max-attempts)
        if [[ -z "${2:-}" || "$2" == -* ]]; then
          log_error "--max-attempts requires a numeric value"
          exit 1
        fi
        MAX_TASK_ATTEMPTS="$2"
        shift 2
        ;;
      --loop)
        # Explicit loop mode flag (ralph.sh loops by default, this is for CLI compatibility)
        shift
        ;;
      --allow-dirty)
        # Skip clean working tree check (for testing)
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          MAX_ITERATIONS="$1"
        else
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

  # Validate numeric arguments
  if ! [[ "$MIN_REVIEW_PASSES" =~ ^[0-9]+$ ]]; then
    log_error "--min-review-passes must be a non-negative integer"
    exit 1
  fi
  if ! [[ "$MAX_TASKS" =~ ^[0-9]+$ ]]; then
    log_error "--max-tasks must be a non-negative integer"
    exit 1
  fi
  if ! [[ "$STALL_MINUTES" =~ ^[1-9][0-9]*$ ]]; then
    log_error "--stall-minutes must be a positive integer (> 0)"
    exit 1
  fi
  if ! [[ "$STALL_THRESHOLD" =~ ^[1-9][0-9]*$ ]]; then
    log_error "--stall-threshold must be a positive integer (> 0)"
    exit 1
  fi
  if ! [[ "$MAX_TASK_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
    log_error "--max-attempts must be a positive integer (> 0)"
    exit 1
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
  --allow-same-review-tool     Allow review tool to match implementation tool
  --allow-no-verify            Allow tasks without verification commands
  --default-verify <cmds>      Default verification commands if task is missing them
  --min-review-passes <n>      Minimum fresh-eyes passes before accepting clean (default: 2)
  --no-self-heal               Disable auto-recovery of stuck tasks
  --stall-threshold <min>      Minutes before task is considered stuck (default: 20)
  --override-lock <pid>        Override stale lockfile from specified PID (for agents that can't delete files)
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
  --scoped-tests-only          Skip global npm test if task has scoped verification
  --final-e2e                  Run full E2E suite at end (default: true if e2e exists)
  --no-final-e2e               Skip final E2E regression suite
  --council-review             Enable Council of Subagents review (Analyst/Sentinel/Designer/Healer)
  --no-council-review          Disable council review (default)

Strict Mode Options:
  --strict                     Enable all strict features (TDD, cross-review, auto-commit)
  --continue-on-error          Continue loop even if a task fails
  --max-tasks <n>              Max tasks to process (0=unlimited)
  --allow-no-tests             Skip TDD test-change requirement (default)
  --require-tests              Enforce TDD test-change requirement
  --stall-minutes <n>          Max minutes per tool run before timeout (default: 45)
  --auto-push                  Push after each successful commit
  --no-commit                  Disable auto-commit after task completion
  --commit-prefix <type>       Commit message prefix (default: feat)
  --max-attempts <n>           Max retry attempts per task (default: 3)

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
  1. Run lint command      → Catch code quality issues
  2. Run typecheck command → Catch type errors
  3. Run build command     → Catch build errors
  4. Run test command      → Verify tests pass
  5. Detect anti-patterns  → Disabled lint rules, suspicious changes
  Commands are auto-detected: Makefile targets, npm scripts, cargo, pytest, etc.
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
  Claude Code: claude -p --dangerously-skip-permissions --no-session-persistence "<prompt>"
  Codex CLI:   codex exec --yolo "<prompt>"

  Note: Commands run with stdin redirected from /dev/null to ensure synchronous execution.

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

  HAS_CLAUDE="$has_claude"
  HAS_CODEX="$has_codex"
  
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

  # Review tool availability (if reviews enabled)
  if [[ "${FRESH_EYES:-false}" == "true" || "${COUNCIL_REVIEW:-false}" == "true" ]]; then
    if [[ -n "$REVIEW_TOOL" ]]; then
      if ! command -v "$REVIEW_TOOL" &> /dev/null; then
        log_error "Review tool '$REVIEW_TOOL' not found in PATH."
        exit 1
      fi
    else
      if [[ "$ALLOW_SAME_REVIEW_TOOL" != "true" ]]; then
        if [[ "$has_claude" != "true" || "$has_codex" != "true" ]]; then
          log_error "Fresh-eyes review requires both Claude and Codex."
          log_error "Install the missing tool(s) or use --review-tool <available> --allow-same-review-tool."
          exit 1
        fi
      fi
    fi
  fi
  
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
    if [[ ! -d "$PROJECT_ROOT/.beads" ]]; then
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

format_duration() {
  local total_seconds="$1"
  if [[ "$total_seconds" -lt 0 ]]; then
    total_seconds=0
  fi
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))
  printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
}

# TDD enforcement: Check if task tags require test changes
should_require_tests() {
  local tags="$1"
  if [[ -z "$tags" ]]; then
    return 0  # Default: require tests
  fi
  # Tags that require tests
  if echo "$tags" | grep -E -qi '(core|api|ui|component|worker|data|feature|backend|frontend|db)'; then
    return 0  # Require tests
  fi
  # Tags that don't require tests
  if echo "$tags" | grep -E -qi '(docs?|chore|setup|config|infra|ops|verify)'; then
    return 1  # Don't require tests
  fi
  return 0  # Default: require tests
}

# TDD enforcement: Verify test files were changed
require_test_changes() {
  if [[ "$ALLOW_NO_TESTS" == "true" ]]; then
    return 0
  fi
  local tags="${1:-}"
  if ! should_require_tests "$tags"; then
    log_info "Skipping test-change requirement for non-test task tags: $tags"
    return 0
  fi
  local files
  files=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "")
  local test_pattern='(^|/)(tests?|__tests__|__test__|specs?)/|\.test\.|\.spec\.|_test\.(py|go|rs|rb|php)$|_spec\.rb$|test_.*\.py$|\.bats$'
  if ! echo "$files" | grep -E -q "$test_pattern"; then
    log_error "No test changes detected. Add real tests or pass --allow-no-tests for non-test tasks."
    return 1
  fi
  return 0
}

# Update loop state JSON file (for monitoring/debugging)
update_loop_state() {
  local status="$1"
  local phase="$2"
  local attempt="$3"
  local note="${4:-}"

  if [[ -z "$LOOP_STATE_FILE" ]]; then
    return 0
  fi

  local loop_json=false
  local beads_json=false
  [[ "$MAX_ITERATIONS" -gt 1 ]] && loop_json=true
  [[ "$USE_BEADS" == "true" ]] && beads_json=true

  jq -n \
    --arg runId "$(date -Iseconds)" \
    --arg updatedAt "$(date -Iseconds)" \
    --arg taskId "${CURRENT_TASK_ID:-}" \
    --arg subject "${CURRENT_SUBJECT:-}" \
    --arg status "$status" \
    --arg phase "$phase" \
    --arg note "$note" \
    --arg implementer "$TOOL" \
    --arg reviewer "${REVIEW_TOOL:-$TOOL}" \
    --argjson attempt "$attempt" \
    --argjson loop "$loop_json" \
    --argjson beads "$beads_json" \
    '{
      runId: $runId,
      updatedAt: $updatedAt,
      mode: { loop: $loop, beads: $beads },
      task: { id: $taskId, subject: $subject, status: $status, phase: $phase, attempt: $attempt },
      tools: { implementer: $implementer, reviewer: $reviewer },
      note: $note
    }' > "$LOOP_STATE_FILE"
}

# Commit task changes with optional push
commit_task_changes() {
  local task_id="$1"
  local subject="$2"

  if [[ "$AUTO_COMMIT" != "true" ]]; then
    return 0
  fi

  git add -A
  local message="$COMMIT_PREFIX($task_id): $subject"
  git commit -m "$message" || {
    log_warn "Commit failed (possibly no changes)"
    return 0
  }

  if [[ "$AUTO_PUSH" == "true" ]]; then
    if ! git push 2>/dev/null; then
      log_warn "Push failed. Attempting pull --rebase and retry..."
      if ! git pull --rebase 2>/dev/null; then
        log_error "Rebase failed. Manual intervention may be needed."
        return 1
      fi
      if ! git push; then
        log_error "Push failed after rebase. Continuing anyway."
        return 1
      fi
    fi
  fi
  return 0
}

# Initialize state/summary files for strict mode
init_strict_files() {
  if [[ "$STRICT_MODE" == "true" || "$AUTO_COMMIT" == "true" ]]; then
    LOOP_STATE_FILE="$PROJECT_ROOT/artifacts/08-loop_state.json"
    SUMMARY_FILE="$PROJECT_ROOT/artifacts/08-execution-summary.md"

    mkdir -p "$PROJECT_ROOT/artifacts"

    if [[ ! -f "$SUMMARY_FILE" ]]; then
      cat <<EOF > "$SUMMARY_FILE"
# Execution Summary (ralph)

Run Started: $(date -Iseconds)

| Task ID | Subject | Status | Commit | Notes |
|--------|---------|--------|--------|-------|
EOF
    fi
  fi
}

# Append to summary file
append_summary() {
  if [[ -z "$SUMMARY_FILE" || ! -f "$SUMMARY_FILE" ]]; then
    return 0
  fi
  local id="$1"
  local subject="$2"
  local status="$3"
  local commit="$4"
  local notes="$5"
  printf '| %s | %s | %s | %s | %s |\n' "$id" "$subject" "$status" "$commit" "$notes" >> "$SUMMARY_FILE"
}

# Log task progress to progress file (consolidates repeated pattern)
# Usage: log_task_progress <iteration> <task_id> <subject> <tool> <status> [extra_lines...]
log_task_progress() {
  local iteration="$1"
  local task_id="$2"
  local subject="$3"
  local tool="$4"
  local status="$5"
  shift 5

  {
    echo ""
    echo "### Iteration $iteration - $(date -Iseconds)"
    echo "- Task: $task_id - $subject"
    echo "- Tool: $tool"
    echo "- Status: $status"
    # Any additional lines passed as arguments
    for line in "$@"; do
      echo "- $line"
    done
  } >> "$PROGRESS_FILE"
}

# Handle task failure consistently
# Usage: handle_task_failure <task_id> <subject> <tool> <iteration> <reason> <summary_note>
handle_task_failure() {
  local task_id="$1"
  local subject="$2"
  local tool="$3"
  local iteration="$4"
  local reason="$5"
  local summary_note="$6"

  mark_task_failed "$task_id"
  clear_task_tracking "$task_id"
  append_summary "$task_id" "$subject" "FAILED" "-" "$summary_note"
  log_task_progress "$iteration" "$task_id" "$subject" "$tool" "❌ FAILED ($reason)"
}

# Interactive task source selection
select_task_source() {
  local has_beads=false
  local has_graph=false
  
  # Check what's available
  [[ -d "$PROJECT_ROOT/.beads" ]] && command -v br &> /dev/null && has_beads=true
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

extract_section() {
  local text="$1"
  local header_regex="$2"
  printf '%s\n' "$text" | awk -v re="$header_regex" '
    BEGIN{found=0}
    $0 ~ re {found=1; next}
    found && /^[A-Z][A-Za-z ]+:/ {exit}
    found {print}
  ' | sed -e 's/^[ -]*//'
}

build_task_json_from_bead() {
  local bead_json="$1"
  local id title desc labels_json
  # Use here-strings (<<<) instead of echo to preserve backslashes and special characters in JSON
  id=$(jq -r '.id' <<< "$bead_json")
  title=$(jq -r '.title' <<< "$bead_json")
  desc=$(jq -r '.description // ""' <<< "$bead_json")
  labels_json=$(jq -c '.labels // [] | map(ascii_downcase)' <<< "$bead_json")

  local verification
  local llm_verification
  local allowed_paths
  verification=$(extract_section "$desc" '^(Verification:|VERIFICATION:)')
  llm_verification=$(extract_section "$desc" '^(LLM Verification:|LLM VERIFY:|Subjective Checks:|SUBJECTIVE CHECKS:)')
  allowed_paths=$(extract_section "$desc" '^(Allowed Paths:|ALLOWED PATHS:|Files to modify:|FILES TO MODIFY:)')

  jq -n \
    --arg id "$id" \
    --arg subject "$title" \
    --arg description "$desc" \
    --arg verification "$verification" \
    --arg llmVerification "$llm_verification" \
    --arg allowedPaths "$allowed_paths" \
    --argjson tags "$labels_json" \
    '{
      id: $id,
      subject: $subject,
      description: $description,
      tags: $tags,
      allowedPaths: ($allowedPaths | split("\n") | map(select(length>0))),
      verification: ($verification | split("\n") | map(select(length>0))),
      llmVerification: ($llmVerification | split("\n") | map(select(length>0)))
    }'
}

get_review_tool_for_task() {
  local selected_tool="$1"
  if [[ -n "$REVIEW_TOOL" ]]; then
    echo "$REVIEW_TOOL"
    return
  fi

  case "$selected_tool" in
    claude) echo "codex" ;;
    codex) echo "claude" ;;
    *) echo "$selected_tool" ;;
  esac
}

load_default_verification() {
  local default_value="${DEFAULT_VERIFY:-${RALPH_DEFAULT_VERIFY:-}}"

  # Check verification.txt file
  if [[ -z "$default_value" && -f "$PROJECT_ROOT/verification.txt" ]]; then
    default_value=$(grep -v '^[[:space:]]*#' "$PROJECT_ROOT/verification.txt" | sed '/^[[:space:]]*$/d')
  fi

  # Auto-detect verification command from project stack (package.json, Cargo.toml, etc.)
  if [[ -z "$default_value" ]]; then
    local test_cmd build_cmd
    test_cmd=$(get_cmd "test" 2>/dev/null) || true
    build_cmd=$(get_cmd "build" 2>/dev/null) || true
    if [[ -n "$test_cmd" ]]; then
      default_value="$test_cmd"
      log_info "Auto-detected verification from stack: $test_cmd"
    elif [[ -n "$build_cmd" ]]; then
      default_value="$build_cmd"
      log_info "Auto-detected verification from stack: $build_cmd"
    fi
  fi

  printf '%s\n' "$default_value"
}

get_task_verification() {
  local task_json="$1"
  echo "$task_json" | jq -r '
    (.verification // [])
    | if type=="array" then join("\n")
      elif type=="string" then .
      else "" end
  '
}

get_task_llm_verification() {
  local task_json="$1"
  echo "$task_json" | jq -r '
    (.llmVerification // [])
    | if type=="array" then join("\n")
      elif type=="string" then .
      else "" end
  '
}

# Refresh task verification by re-reading from source (bead file or task-graph.json)
# This allows picking up verification commands that were added/fixed during iteration
refresh_task_verification() {
  local task_id="$1"
  local task_json
  task_json=$(get_task_by_id "$task_id")
  if [[ -n "$task_json" ]]; then
    get_task_verification "$task_json"
  fi
}

ensure_task_verification() {
  local task_json="$1"
  local task_id
  task_id=$(echo "$task_json" | jq -r '.id')
  local verification
  verification=$(get_task_verification "$task_json")
  local llm_verification
  llm_verification=$(get_task_llm_verification "$task_json")

  if [[ -z "$verification" ]]; then
    local default_verify
    default_verify=$(load_default_verification)
    if [[ -n "$default_verify" ]]; then
      log_warn "Task $task_id missing verification. Using default verification."
      task_json=$(echo "$task_json" | jq --arg v "$default_verify" '.verification = ($v | split("\n") | map(select(length>0)))')
      verification="$default_verify"
    elif [[ -n "$llm_verification" ]]; then
      log_warn "Task $task_id has no verification commands; using LLM verification only."
    elif [[ "$ALLOW_NO_VERIFY" == "true" ]]; then
      log_warn "Task $task_id missing verification. Continuing due to --allow-no-verify."
      printf '%s\n' "$task_json"
      return 0
    else
      log_error "Task $task_id missing verification/backpressure."
      log_error "Add task verification, set RALPH_DEFAULT_VERIFY, or use --default-verify."
      return 1
    fi
  fi

  printf '%s\n' "$task_json"
}

# Check if a string looks like an executable command (not descriptive text)
looks_like_command() {
  local cmd="$1"
  # Skip empty lines
  [[ -z "$cmd" ]] && return 1

  # Skip lines that look like markdown or documentation
  [[ "$cmd" =~ ^[#*-][[:space:]] ]] && return 1
  [[ "$cmd" =~ ^[0-9]+\.[[:space:]] ]] && return 1

  # Known command prefixes - definitely commands
  if [[ "$cmd" =~ ^(npm|npx|node|python|pip|pytest|cargo|go|make|bash|sh|curl|wget|docker|git|ruby|bundle|yarn|pnpm|bun|deno|flask|django|uvicorn|gunicorn|ruff|mypy|black|eslint|prettier|tsc|vitest|jest|playwright|cypress|cat|echo|ls|cd|mv|cp|rm|touch|mkdir|grep|sed|awk|find|test|\[|\./) ]]; then
    return 0
  fi

  # Starts with uppercase = likely English sentence, not a command
  # (Unix commands are lowercase)
  if [[ "$cmd" =~ ^[A-Z] ]]; then
    return 1
  fi

  # Starts with lowercase = probably a command
  return 0
}

run_task_verification() {
  local task_id="$1"
  local verification="$2"

  if [[ -z "$verification" ]]; then
    return 0
  fi

  log_info "Running task-specific verification..."
  while IFS= read -r cmd; do
    # Trim whitespace using parameter expansion (xargs would strip quotes from commands)
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    cmd="${cmd%"${cmd##*[![:space:]]}"}"
    [[ -z "$cmd" ]] && continue

    # Skip lines that don't look like commands
    if ! looks_like_command "$cmd"; then
      log_warn "Skipping non-command: $cmd"
      continue
    fi

    # Auto-fix Vitest CLI syntax: Vitest uses -t for test name filtering, not --grep
    # Skip this fix for E2E tests since Playwright correctly uses --grep
    if [[ "$cmd" != *"e2e"* ]] && [[ "$cmd" == *"npm"*"test"*"--grep"* ]] && [[ -f "$PROJECT_ROOT/package.json" ]] && grep -q '"vitest"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
      local fixed_cmd="${cmd//--grep/-t}"
      log_warn "Auto-fixing Vitest syntax: --grep → -t"
      cmd="$fixed_cmd"
    fi

    log_info "Verify: $cmd"
    if ! (cd "$PROJECT_ROOT" && bash -lc "$cmd"); then
      log_error "Task verification failed: $cmd"
      {
        echo ""
        echo "### VERIFICATION FAILURE - $(date -Iseconds)"
        echo "- Task: $task_id"
        echo "- Command: $cmd"
      } >> "$PROGRESS_FILE"
      return 1
    fi
  done <<< "$verification"

  return 0
}

select_llm_review_tool() {
  if [[ -n "$REVIEW_TOOL" ]]; then
    echo "$REVIEW_TOOL"
    return 0
  fi
  if [[ "$HAS_CLAUDE" == "true" ]]; then
    echo "claude"
    return 0
  fi
  if [[ "$HAS_CODEX" == "true" ]]; then
    echo "codex"
    return 0
  fi
  return 1
}

run_llm_verification() {
  local task_id="$1"
  local criteria="$2"

  if [[ -z "$criteria" ]]; then
    return 0
  fi

  local tool
  if ! tool=$(select_llm_review_tool); then
    log_error "No LLM review tool available for subjective verification."
    return 1
  fi

  local diff_content=""
  local changed_files="unknown"
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    diff_content=$(git diff HEAD 2>/dev/null || git diff 2>/dev/null || echo "")
    changed_files=$(git diff --name-status HEAD 2>/dev/null || git diff --name-status 2>/dev/null || echo "unknown")
  elif git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    diff_content=$(git show --pretty="" HEAD 2>/dev/null || echo "")
    changed_files=$(git show --name-status --pretty="" HEAD 2>/dev/null || echo "unknown")
  fi

  local diff_note=""
  if [[ -n "$diff_content" ]]; then
    local diff_line_count
    diff_line_count=$(printf '%s\n' "$diff_content" | wc -l | tr -d ' ')
    if (( diff_line_count > 500 )); then
      diff_content=$(printf '%s\n' "$diff_content" | head -n 500)
      diff_note="NOTE: Diff truncated to first 500 lines."
    fi
  fi

  local prompt="You are a strict QA judge verifying subjective acceptance criteria.
Evaluate the criteria below based on the code changes and repository state.
If criteria are satisfied, output exactly: LLM_PASS
If criteria are NOT satisfied or cannot be verified, output exactly: LLM_FAIL and a one-line reason.

CRITERIA:
$criteria

CHANGED FILES:
$changed_files

DIFF:
$diff_note
$diff_content"

  local output
  set +e
  output=$(run_with_tool "$tool" "$prompt" 2>&1)
  set -e

  if echo "$output" | grep -qx "LLM_PASS"; then
    log_success "LLM verification passed"
    return 0
  fi

  log_error "LLM verification failed"
  echo "$output" | head -20
  {
    echo ""
    echo "### LLM VERIFICATION FAILURE - $(date -Iseconds)"
    echo "- Task: $task_id"
    echo "- Tool: $tool"
  } >> "$PROGRESS_FILE"
  return 1
}

# Execute a command with optional timeout, capturing output and exit code correctly
# Usage: _exec_with_timeout <tmp_output_file> <log_file_or_empty> <cmd...>
# Sets global _EXEC_RC with the exit code
#
# Avoid piping through tee which causes PTY buffering issues with interactive CLIs.
# Instead, write directly to file then display contents afterward.
# For real-time monitoring, use `tail -f log_file` in a separate terminal.
_exec_with_timeout() {
  local tmp_output="$1"
  local log_file="$2"
  shift 2
  local cmd=("$@")

  # Detect timeout command
  local timeout_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout"
  fi

  # Execute with direct file redirection (avoids PTY buffering issues)
  # Output goes to tmp_output, which is later copied to log_file
  # Redirect stdin from /dev/null to prevent CLI from waiting for input
  if [[ -n "$timeout_cmd" ]]; then
    "$timeout_cmd" --kill-after=30s "${STALL_MINUTES}m" "${cmd[@]}" < /dev/null > "$tmp_output" 2>&1
  else
    "${cmd[@]}" < /dev/null > "$tmp_output" 2>&1
  fi
  _EXEC_RC=$?

  # Ensure file buffers are flushed after potential timeout/kill
  sync 2>/dev/null || true

  # Append to log file if specified (with explicit error handling)
  if [[ -n "$log_file" ]]; then
    if [[ -s "$tmp_output" ]]; then
      cat "$tmp_output" >> "$log_file"
    else
      echo "[WARNING] Command produced no output (tmp file empty)" >> "$log_file"
    fi
  fi

  # Note: Output is returned via the file, not stdout - caller reads tmp_output
}

# Run a task with the specified tool
# Returns: 0 on success, 124 on timeout, other non-zero on failure
run_with_tool() {
  local tool="$1"
  local prompt="$2"
  local log_file=""
  local tmp_output=""

  # Create log file for this task if we have a task ID
  if [[ -n "$CURRENT_TASK_ID" ]]; then
    log_file="$LOGS_DIR/${CURRENT_TASK_ID}.log"
    mkdir -p "$LOGS_DIR"
    {
      echo ""
      echo "=== $(date -Iseconds) ==="
      echo "tool: $tool"
      echo "prompt:"
      echo "$prompt"
      echo "--- output ---"
    } >> "$log_file"
    log_info "Logging to: $log_file"
    log_info "Watch with: tail -f $log_file"
  fi

  log_tool "Using: $tool"

  # Create temp file to capture output (needed for correct exit code capture)
  tmp_output=$(mktemp) || {
    log_error "Failed to create temp file for output capture"
    return 1
  }
  trap "rm -f '$tmp_output'" RETURN

  # Get the command for the tool
  local cmd=""
  case "$tool" in
    claude)
      # Claude Code CLI: -p for print mode, --dangerously-skip-permissions for YOLO
      # --no-session-persistence ensures synchronous execution when stdout is redirected
      cmd="${CLAUDE_CMD:-claude -p --dangerously-skip-permissions --no-session-persistence}"
      ;;
    codex)
      # Codex CLI: exec for execution mode, --yolo for no approvals
      cmd="${CODEX_CMD:-codex exec --yolo}"
      ;;
    *)
      log_error "Unknown tool: $tool. Valid tools: claude, codex"
      return 1
      ;;
  esac

  # Execute with timeout and capture exit code
  # Note: cmd is intentionally unquoted to allow word splitting
  _exec_with_timeout "$tmp_output" "$log_file" $cmd "$prompt"
  local rc=$_EXEC_RC

  # Read output from temp file with robust error handling
  local output=""
  if [[ -f "$tmp_output" ]]; then
    if [[ -s "$tmp_output" ]]; then
      output=$(cat "$tmp_output")
    else
      log_warn "Tool output file exists but is empty: $tmp_output"
      if [[ -n "$log_file" ]]; then
        echo "[DEBUG] tmp_output=$tmp_output exists but empty" >> "$log_file"
        echo "[DEBUG] Checking for stray temp files with TASK_COMPLETE:" >> "$log_file"
        # Check both Linux (/tmp) and macOS (/var/folders) temp locations
        local tmpdir="${TMPDIR:-/tmp}"
        find "$tmpdir" -maxdepth 1 -name 'tmp.*' -mmin -5 -exec grep -l "TASK_COMPLETE" {} \; 2>/dev/null >> "$log_file" || true
      fi
    fi
  else
    log_warn "Tool output file missing: $tmp_output"
  fi

  # Log completion status
  if [[ -n "$log_file" ]]; then
    echo "" >> "$log_file"
    local output_size=${#output}
    if [[ "$rc" -eq 124 ]] || [[ "$rc" -eq 137 ]] || [[ "$rc" -eq 143 ]]; then
      echo "=== TIMEOUT after ${STALL_MINUTES}m (rc=$rc, output_size=$output_size): $(date -Iseconds) ===" >> "$log_file"
    else
      echo "=== Finished (rc=$rc, output_size=$output_size): $(date -Iseconds) ===" >> "$log_file"
    fi
  fi

  echo "$output"
  return "$rc"
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
    elif git rev-parse HEAD~1 &>/dev/null; then
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
  local min_review_passes="${MIN_REVIEW_PASSES:-2}"
  local pass=1

  if (( min_review_passes > max_review_passes )); then
    min_review_passes="$max_review_passes"
  fi
  
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

    while [[ $pass -le $max_review_passes ]]; do
      log_info "  Codex review pass $pass/$max_review_passes (min $min_review_passes)..."

      # Check if there are uncommitted changes
      local has_uncommitted=true
      if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
        has_uncommitted=false
      fi

      # Generate diff for Codex to review
      local diff_content=""
      local staged_diff=""
      local changed_files="unknown"
      if [[ "$has_uncommitted" == "true" ]]; then
        diff_content=$(git diff HEAD 2>/dev/null || git diff 2>/dev/null || echo "")
        staged_diff=$(git diff --cached 2>/dev/null || echo "")
        changed_files=$(git diff --name-status HEAD 2>/dev/null || git diff --name-status 2>/dev/null || echo "unknown")
      else
        if ! git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
          log_info "  No uncommitted changes and no prior commit to review"
          return 0
        fi
        diff_content=$(git show --pretty="" HEAD 2>/dev/null || echo "")
        changed_files=$(git show --name-status --pretty="" HEAD 2>/dev/null || echo "unknown")
      fi

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
        if [[ $pass -lt $min_review_passes ]]; then
          log_info "  No issues found, running another pass to satisfy minimum review passes"
          pass=$((pass + 1))
          continue
        fi
        log_success "  Codex review complete - no issues found"
        return 0
      fi

      local issue_lines
      issue_lines=$(echo "$review_output" | grep -E '^\[P[123]\]' || true)
      if [[ -z "$issue_lines" ]]; then
        log_warn "  Codex review output contained no parsable issues"
        if [[ $pass -lt $min_review_passes ]]; then
          pass=$((pass + 1))
          continue
        fi
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

      pass=$((pass + 1))
    done

    log_warn "  Reached max review passes ($max_review_passes), continuing..."
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
    log_info "  Fresh eyes review pass $pass/$max_review_passes (min $min_review_passes)..."
    
    local review_output
    set +e
    review_output=$(run_with_tool "$tool" "$review_prompt" 2>&1)
    set -e
    
    if echo "$review_output" | grep -q "<review>NO_ISSUES</review>"; then
      if [[ $pass -lt $min_review_passes ]]; then
        log_info "  No issues found, running another pass to satisfy minimum review passes"
        pass=$((pass + 1))
        continue
      fi
      log_success "  Fresh eyes review complete - no issues found"
      return 0
    elif echo "$review_output" | grep -q "<review>FOUND_ISSUES</review>"; then
      log_info "  Issues found and fixed, running another pass..."
      pass=$((pass + 1))
    else
      # No clear signal, assume done unless minimum passes not met
      if [[ $pass -lt $min_review_passes ]]; then
        pass=$((pass + 1))
        continue
      fi
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
  local bead_json
  bead_json=$(jq -c '.[0]' <<< "$ready_tasks")
  if [[ -z "$bead_json" || "$bead_json" == "null" ]]; then
    echo ""
    return
  fi
  build_task_json_from_bead "$bead_json"
}

# Reset stale IN_PROGRESS beads from previous failed runs.
# When Ralph crashes or is interrupted, beads may be left in IN_PROGRESS state.
# This function resets them to open so they can be retried.
reset_stale_in_progress_beads() {
  [[ "$USE_BEADS" != "true" ]] && return 0

  # Get all beads that are currently in_progress
  local in_progress
  in_progress=$(br list --status in_progress --json 2>/dev/null || echo "[]")

  if [[ "$in_progress" == "[]" || -z "$in_progress" ]]; then
    return 0
  fi

  local count
  count=$(jq 'length' <<< "$in_progress")
  if [[ "$count" -gt 0 ]]; then
    log_warn "Found $count stale IN_PROGRESS beads from previous run"
    # Reset each to open status
    jq -r '.[].id' <<< "$in_progress" | while read -r bead_id; do
      log_info "Resetting stale bead $bead_id to open"
      br update "$bead_id" --status open --comment "Reset by Ralph (stale IN_PROGRESS)" 2>/dev/null || true
    done
  fi
}

# Get task by ID
get_task_by_id() {
  local task_id="$1"
  if [[ "$USE_BEADS" == "true" ]]; then
    local bead_json
    bead_json=$(br show "$task_id" --json 2>/dev/null || echo "")
    if [[ -z "$bead_json" || "$bead_json" == "null" ]]; then
      echo ""
      return
    fi
    # Normalize response: br show may return an array or a single object
    bead_json=$(jq 'if type == "array" then .[0] else . end' <<< "$bead_json")
    build_task_json_from_bead "$bead_json"
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

# Compute a signature from error output for flaky detection
# Returns a short hash of the error's key characteristics
compute_fail_signature() {
  local error_output="$1"
  # Extract key error identifiers: test names, file:line, error messages
  local filtered
  filtered=$(echo "$error_output" | grep -iE "fail|error|timeout|✗" | head -10)
  # Cross-platform hash (md5sum on Linux, md5 on macOS)
  if command -v md5sum &>/dev/null; then
    echo "$filtered" | md5sum | cut -c1-8
  elif command -v md5 &>/dev/null; then
    echo "$filtered" | md5 | cut -c1-8
  else
    # Fallback: use first 8 chars of base64-encoded content
    echo "$filtered" | head -c 100 | base64 | cut -c1-8
  fi
}

# Check if this is a repeated flaky failure and should be skipped
# Returns 0 if should skip, 1 if should continue retrying
# Tracks both task ID and error signature to detect:
# 1. Same task failing repeatedly with same error (flaky test)
# 2. Different tasks failing with same error (global breakage)
check_flaky_skip() {
  local task_id="$1"
  local error_output="$2"

  local signature
  signature=$(compute_fail_signature "$error_output")

  # Check if same task AND same signature
  if [[ "$task_id" == "$LAST_FAIL_TASK_ID" && "$signature" == "$LAST_FAIL_SIGNATURE" ]]; then
    SAME_FAIL_COUNT=$((SAME_FAIL_COUNT + 1))
    log_warn "Same task failing with same error ($SAME_FAIL_COUNT/$FLAKY_FAIL_THRESHOLD)"
  elif [[ "$signature" == "$LAST_FAIL_SIGNATURE" ]]; then
    # Different task, same error - might be global issue
    SAME_FAIL_COUNT=$((SAME_FAIL_COUNT + 1))
    log_warn "Different task, same error pattern ($SAME_FAIL_COUNT/$FLAKY_FAIL_THRESHOLD)"
  else
    # Different error - reset counter
    LAST_FAIL_TASK_ID="$task_id"
    LAST_FAIL_SIGNATURE="$signature"
    SAME_FAIL_COUNT=1
  fi

  if [[ "$SAME_FAIL_COUNT" -ge "$FLAKY_FAIL_THRESHOLD" ]]; then
    log_error "╔════════════════════════════════════════════════════════════════╗"
    log_error "║  REPEATED FAILURE DETECTED - Skipping after $SAME_FAIL_COUNT identical failures   ║"
    log_error "╚════════════════════════════════════════════════════════════════╝"
    mark_task_blocked_flaky "$task_id" "$signature"
    # Reset for next task
    LAST_FAIL_TASK_ID=""
    LAST_FAIL_SIGNATURE=""
    SAME_FAIL_COUNT=0
    return 0  # Should skip
  fi
  return 1  # Should continue retrying
}

# Mark task as blocked due to flaky test
mark_task_blocked_flaky() {
  local task_id="$1"
  local signature="$2"
  if [[ "$USE_BEADS" == "true" ]]; then
    br update "$task_id" --status blocked --comment "Blocked: flaky test (signature: $signature). Needs manual investigation." 2>/dev/null || true
    log_warn "Marked beads task $task_id as blocked (flaky test)"
  else
    local tmp=$(mktemp)
    jq --arg id "$task_id" --arg sig "$signature" '
      .tasks = [.tasks[] | if .id == $id then .status = "blocked" | .blockedReason = "flaky_test" | .failSignature = $sig else . end]
    ' "$TASK_GRAPH" > "$tmp" && mv "$tmp" "$TASK_GRAPH"
    log_warn "Marked task $task_id as blocked (flaky test)"
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

# Check if a task has stalled (exceeded STALL_THRESHOLD or no log activity)
# Uses both wall-clock time AND log file heartbeat for accurate detection
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

  # Check 1: Total time threshold
  if [[ "$elapsed_minutes" -ge "$STALL_THRESHOLD" ]]; then
    log_warn "Task $task_id has been tracked for $elapsed_minutes minutes (threshold: $STALL_THRESHOLD)"
    return 0  # Stalled
  fi

  # Check 2: Log file heartbeat (no output for 5+ minutes = likely stuck)
  local log_file="$LOGS_DIR/${task_id}.log"
  if [[ -f "$log_file" ]]; then
    # Get mtime: try macOS format, then Linux, fallback to now
    local log_mtime
    log_mtime=$(stat -f %m "$log_file" 2>/dev/null) || \
    log_mtime=$(stat -c %Y "$log_file" 2>/dev/null) || \
    log_mtime=$now
    local log_age_minutes=$(( (now - log_mtime) / 60 ))
    if [[ "$log_age_minutes" -ge 5 ]] && [[ "$elapsed_minutes" -ge 5 ]]; then
      log_warn "Task $task_id log has no output for ${log_age_minutes}m (heartbeat check)"
      return 0  # Stalled - no log activity
    fi
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
  local review_tool="${5:-}"
  local ran_reviews="${6:-false}"
  
  # Extract any learnings/notes from the output
  local learnings=""
  
  # Look for learning markers in output
  if echo "$output" | grep -q "LEARNING:\|NOTE:\|INSIGHT:\|TIP:"; then
    learnings=$(echo "$output" | grep -E "LEARNING:|NOTE:|INSIGHT:|TIP:" | head -10)
  fi
  
  # Build verification summary (only called after verification succeeds)
  local verification_parts=()
  if [[ "${VERIFY_LINT:-true}" == "true" ]]; then
    verification_parts+=("lint=pass")
  fi
  if [[ "${VERIFY_TYPECHECK:-true}" == "true" ]]; then
    verification_parts+=("typecheck=pass")
  fi
  if [[ "${VERIFY_BUILD:-true}" == "true" ]]; then
    verification_parts+=("build=pass")
  fi
  if [[ "${VERIFY_TESTS:-true}" == "true" ]]; then
    verification_parts+=("tests=pass")
  fi
  local verification_summary
  verification_summary=$(IFS=", "; echo "${verification_parts[*]}")

  # Record to learnings file
  {
    echo ""
    echo "## $(date -Iseconds) - $task_id"
    echo ""
    echo "**Task:** $subject"
    echo ""
    echo "**Tool:** $tool"
    echo ""
    if [[ "$ran_reviews" == "true" ]]; then
      echo "**Review:** ran (tool: ${review_tool:-unknown})"
    else
      echo "**Review:** skipped"
    fi
    echo ""
    if [[ -n "$verification_summary" ]]; then
      echo "**Verification:** $verification_summary"
      echo ""
    fi
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
  [[ -f "$PROJECT_ROOT/package.json" ]] || return 1
  command -v node &>/dev/null || return 1
  # Pass path as argument to avoid issues with special characters in path
  node -e 'const p=require(process.argv[1]); const s=process.argv[2]; process.exit(((p.scripts||{})[s])?0:1)' "$PROJECT_ROOT/package.json" "$script" 2>/dev/null
}

# Get the command for a given task type (lint, test, build, typecheck)
# Supports multiple tech stacks with Makefile as universal override
get_cmd() {
  local cmd_type="$1"  # lint, test, build, typecheck, dev

  # Makefile is the universal override - check first
  if [[ -f "$PROJECT_ROOT/Makefile" ]] && grep -q "^${cmd_type}:" "$PROJECT_ROOT/Makefile" 2>/dev/null; then
    echo "make $cmd_type"
    return 0
  fi

  # Project-type detection (priority order: Node > Python > Rust > Go > Ruby)
  if [[ -f "$PROJECT_ROOT/package.json" ]]; then
    # Node.js - check if script exists
    if has_npm_script "$cmd_type"; then
      echo "npm run $cmd_type"
      return 0
    fi
    # Fallback for common script name variations
    case "$cmd_type" in
      typecheck)
        has_npm_script "type-check" && echo "npm run type-check" && return 0
        has_npm_script "types" && echo "npm run types" && return 0
        [[ -f "$PROJECT_ROOT/tsconfig.json" ]] && command -v tsc &>/dev/null && echo "tsc --noEmit" && return 0
        ;;
    esac
  elif [[ -f "$PROJECT_ROOT/pyproject.toml" ]] || [[ -f "$PROJECT_ROOT/setup.py" ]] || [[ -f "$PROJECT_ROOT/requirements.txt" ]]; then
    # Python
    case "$cmd_type" in
      lint) echo "ruff check ."; return 0 ;;
      test) echo "pytest -v"; return 0 ;;
      typecheck) echo "mypy ."; return 0 ;;
      build) echo "pip install -e ."; return 0 ;;
      dev)
        if [[ -f "$PROJECT_ROOT/app.py" ]] || [[ -f "$PROJECT_ROOT/application.py" ]]; then
          echo "flask run --debug"; return 0
        elif command -v uvicorn &>/dev/null && [[ -f "$PROJECT_ROOT/main.py" ]]; then
          echo "uvicorn main:app --reload"; return 0
        elif [[ -f "$PROJECT_ROOT/main.py" ]]; then
          echo "python main.py"; return 0
        fi ;;
    esac
  elif [[ -f "$PROJECT_ROOT/Cargo.toml" ]]; then
    # Rust
    case "$cmd_type" in
      lint) echo "cargo clippy -- -D warnings"; return 0 ;;
      test) echo "cargo test"; return 0 ;;
      typecheck) echo "cargo check"; return 0 ;;
      build) echo "cargo build --release"; return 0 ;;
      dev) echo "cargo run"; return 0 ;;
    esac
  elif [[ -f "$PROJECT_ROOT/go.mod" ]]; then
    # Go
    case "$cmd_type" in
      lint)
        if command -v golangci-lint &>/dev/null; then
          echo "golangci-lint run"
        else
          echo "go vet ./..."
        fi
        return 0 ;;
      test) echo "go test -v ./..."; return 0 ;;
      typecheck) echo "go build ./..."; return 0 ;;
      build) echo "go build -o bin/ ./..."; return 0 ;;
      dev) echo "go run ."; return 0 ;;
    esac
  elif [[ -f "$PROJECT_ROOT/Gemfile" ]]; then
    # Ruby
    case "$cmd_type" in
      lint) echo "bundle exec rubocop"; return 0 ;;
      test) echo "bundle exec rspec"; return 0 ;;
      build) echo "bundle install"; return 0 ;;
    esac
  fi

  # No command found
  return 1
}

# Check if a command exists for given type
has_cmd() {
  local cmd_type="$1"
  get_cmd "$cmd_type" >/dev/null 2>&1
}

# Verify the project builds successfully
# Returns 0 on success, 1 on failure
# Args: task_id [has_scoped_tests]
verify_build() {
  local task_id="$1"
  local has_scoped_tests="${2:-false}"
  local log_file="$LOGS_DIR/${task_id}-build.log"

  # Ensure log directory exists
  mkdir -p "$LOGS_DIR" 2>/dev/null || true

  # Check if any supported stack exists
  if ! has_cmd "lint" && ! has_cmd "test" && ! has_cmd "build"; then
    log_warn "No supported stack detected - skipping build verification"
    return 0
  fi

  log_info "╔════════════════════════════════════════════════════════════════╗"
  log_info "║               BUILD VERIFICATION                               ║"
  log_info "╚════════════════════════════════════════════════════════════════╝"

  local build_passed=true
  local typecheck_passed=true
  local lint_passed=true
  local tests_passed=true
  local build_output=""
  local typecheck_output=""
  local lint_output=""

  # Step 0: Lint (catches code quality issues early)
  if [[ "${VERIFY_LINT:-true}" == "true" ]]; then
    log_info "Running lint..."

    local lint_cmd
    if lint_cmd=$(get_cmd "lint"); then
      set +e
      lint_output=$(eval "$lint_cmd" 2>&1)
      local lint_exit=$?
      set -e

      if [[ $lint_exit -eq 0 ]]; then
        log_success "✅ Lint PASSED"
      else
        # Lint failed - count errors from various linter formats
        # ESLint: "file:line:col  error  message" or "X errors"
        # Ruff/Pylint: "file.py:line:col: E501 message" or "Found X errors"
        # Clippy: "error[E0001]: message"
        local error_count=0

        # Try multiple patterns to extract error count from various linter formats
        # ESLint/standard style: "X error(s)" in summary line
        local summary_match=$(echo "$lint_output" | grep -oE "[0-9]+ errors?" | head -1 | grep -oE "[0-9]+" || echo "")
        if [[ -n "$summary_match" ]]; then
          error_count=$summary_match
        fi

        # Ruff/Python style: "Found X error(s)" summary
        if [[ $error_count -eq 0 ]]; then
          summary_match=$(echo "$lint_output" | grep -oE "Found [0-9]+ error" | grep -oE "[0-9]+" || echo "")
          [[ -n "$summary_match" ]] && error_count=$summary_match
        fi

        # Fallback: count lines matching file:line:col format (works with most linters)
        if [[ $error_count -eq 0 ]]; then
          # Count lines containing file:line patterns (common to all linters)
          error_count=$(echo "$lint_output" | grep -cE "^[^:]+:[0-9]+:" || echo "0")
        fi

        if [[ "$error_count" -gt 0 ]]; then
          log_error "❌ Lint FAILED ($error_count errors)"
          lint_passed=false
          # Show first few error lines
          echo "$lint_output" | grep -E "^[^:]+:[0-9]+:|error|Error" | head -5 | while read -r line; do
            log_error "   $line"
          done
        else
          # Lint failed but couldn't parse error count
          log_error "❌ Lint FAILED"
          lint_passed=false
          echo "$lint_output" | head -5 | while read -r line; do
            log_error "   $line"
          done
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

    local typecheck_cmd
    if typecheck_cmd=$(get_cmd "typecheck"); then
      set +e
      typecheck_output=$(eval "$typecheck_cmd" 2>&1)
      local typecheck_exit=$?
      set -e

      if [[ $typecheck_exit -eq 0 ]]; then
        log_success "✅ TypeCheck PASSED"
      else
        log_error "❌ TypeCheck FAILED"
        typecheck_passed=false
        # Count lines containing "error" (case-insensitive) - works for TypeScript and most type checkers
        local error_count
        error_count=$(echo "$typecheck_output" | grep -ciE "error" || echo "0")
        log_error "   Type errors: $error_count"
        # Show first few errors
        echo "$typecheck_output" | grep -iE "error" | head -5 | while read -r line; do
          log_error "   $line"
        done
      fi

      # Log full output
      {
        echo "=== TypeCheck Output ==="
        echo "$typecheck_output"
        echo ""
      } >> "$log_file"
    else
      log_info "⏭️ TypeCheck skipped (no typecheck command)"
    fi
  fi

  # Step 2: Full Build
  if [[ "${VERIFY_BUILD:-true}" == "true" ]]; then
    log_info "Running build..."

    local build_cmd
    if build_cmd=$(get_cmd "build"); then
      set +e
      build_output=$(eval "$build_cmd" 2>&1)
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
      log_info "⏭️ Build skipped (no build command)"
    fi
  fi

  # Step 3: Run Tests (CRITICAL for TDD verification)
  # Skip global tests if --scoped-tests-only and task has its own test verification
  if [[ "${SCOPED_TESTS_ONLY:-false}" == "true" && "$has_scoped_tests" == "true" ]]; then
    log_info "⏭️ Skipping global tests (task has scoped test verification)"
  elif [[ "${VERIFY_TESTS:-true}" == "true" ]]; then
    log_info "Running tests..."

    local test_cmd
    if test_cmd=$(get_cmd "test"); then
      set +e
      local test_output
      test_output=$(eval "$test_cmd" 2>&1)
      local test_exit=$?
      set -e

      if [[ $test_exit -eq 0 ]]; then
        # Sanity check: verify tests actually ran (prevents false positives from empty test suites)
        local tests_ran
        tests_ran=$(echo "$test_output" | grep -oE '[0-9]+ (passed|passing)' | grep -oE '^[0-9]+' | head -1 || echo "")
        if [[ -z "$tests_ran" || "$tests_ran" -eq 0 ]]; then
          log_warn "⚠️ Tests passed but 0 tests detected - check verification command"
          log_warn "   This may indicate a misconfigured test command"
        else
          log_success "✅ Tests PASSED ($tests_ran tests)"
        fi
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

  if [[ "${VERIFY_LINT:-true}" == "true" ]] && has_cmd "lint"; then
    ran_lint=true
  fi

  if [[ "${VERIFY_TYPECHECK:-true}" == "true" ]] && has_cmd "typecheck"; then
    ran_typecheck=true
  fi

  if [[ "${VERIFY_BUILD:-true}" == "true" ]] && has_cmd "build"; then
    ran_build=true
  fi

  if [[ "${VERIFY_TESTS:-true}" == "true" ]] && has_cmd "test"; then
    ran_tests=true
  fi

  if [[ "$ran_lint" == "false" && "$ran_typecheck" == "false" && "$ran_build" == "false" && "$ran_tests" == "false" ]]; then
    log_warn "⚠️ No verification was performed (no lint, typecheck, build, or test commands found)"
    log_warn "   Consider adding a Makefile with lint/test/build targets"
  fi

  # Step 4: Check for suspicious changes (anti-pattern detection)
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
  local llm_verification
  llm_verification=$(get_task_llm_verification "$task_json")
  local llm_verification_block=""
  if [[ -n "$llm_verification" ]]; then
    local formatted_llm
    formatted_llm=$(printf '%s\n' "$llm_verification" | sed 's/^/- /')
    llm_verification_block=$(printf '\n## Subjective Verification (LLM)\n%s\n' "$formatted_llm")
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
$llm_verification_block

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
4. **MANDATORY: Run task verification and build verification** (see below)
5. **MANDATORY: Self-review with fresh eyes** - re-read your code, fix any issues (see below)
6. If all verifications pass, output <promise>TASK_COMPLETE</promise>
   (Do NOT commit or push - Ralph handles branching/commits/PRs)

## Critical Rules

- Only modify files in allowed paths
- Run ALL verification commands before marking complete
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
- Output <promise>TASK_BLOCKED</promise> with an explanation

The orchestrator will detect these patterns and REJECT the task.

## ⚠️ MANDATORY TASK + BUILD VERIFICATION ⚠️

Before outputting TASK_COMPLETE, you MUST run the task verification
commands listed in this task's Verification section and they MUST pass.

Before outputting TASK_COMPLETE, you MUST run the project's verification commands.
Check for a Makefile (make lint, make test, make build) or use the project's native tools:
- Node.js: npm run lint, npm run typecheck, npm run build, npm test
- Python: ruff check ., mypy ., pytest -v
- Rust: cargo clippy, cargo check, cargo build, cargo test
- Go: go vet ./..., go build ./..., go test ./...

**If ANY command fails, DO NOT output TASK_COMPLETE.**
Instead, fix the errors and re-run until all pass.

Common issues to watch for:
- Type mismatches or missing type annotations
- Imports from non-existent files
- Interface/signature changes that break callers
- Failing tests

The orchestrator will verify the build after you report completion.
If the build fails, your task will be marked as FAILED even if you said TASK_COMPLETE.

## 👀 SELF-REVIEW WITH FRESH EYES (MANDATORY - 4 PASSES)

Before outputting TASK_COMPLETE, you MUST review your own code with "fresh eyes".
**This is an iterative loop - do 4 passes minimum: look → fix → look → fix → look → fix → look → verify clean.**

Each pass:
1. **Re-read all code you wrote or modified** - look at it as if seeing it for the first time
2. **Check for obvious bugs** - off-by-one errors, null checks, edge cases
3. **Check for logic errors** - does the code actually do what it's supposed to?
4. **Check for missing error handling** - what happens when things fail?
5. **Check for inconsistencies** - naming, patterns, style matching existing code
6. **Fix anything you find** - don't just note it, actually fix it
7. **Go back to step 1** - repeat until pass 4 finds nothing to fix

Only output TASK_COMPLETE after completing 4 passes. This self-review is cheap (same context)
and catches many issues before the expensive external review.

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

If you are blocked (need clarification, missing dependency, etc.):
Output exactly: <promise>TASK_BLOCKED</promise>
And explain what you need to proceed.
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
  local eta="--"
  local elapsed="--"
  
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

  if [[ "$SESSION_START_TS" -gt 0 ]]; then
    local now
    now=$(date +%s)
    local elapsed_seconds=$((now - SESSION_START_TS))
    elapsed=$(format_duration "$elapsed_seconds")
    if [[ "$completed" -gt 0 && "$total" -gt "$completed" ]]; then
      local avg=$((elapsed_seconds / completed))
      local remaining=$((total - completed))
      eta=$(format_duration $((avg * remaining)))
    fi
  fi
  
  echo ""
  echo "╔════════════════════════════════════════════════════╗"
  echo "║               RALPH STATUS                         ║"
  echo "╠════════════════════════════════════════════════════╣"
  printf "║  Completed:   %-5s   Pending:    %-5s            ║\n" "$completed" "$pending"
  printf "║  In Progress: %-5s   Failed:     %-5s            ║\n" "$in_progress" "$failed"
  printf "║  Total:       %-5s   Progress:   %3d%%             ║\n" "$total" "$pct"
  printf "║  Elapsed:     %-8s ETA: %-15s ║\n" "$elapsed" "$eta"
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
  init_strict_files
  SESSION_START_TS=$(date +%s)

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
  if [[ "$MAX_TASKS" -gt 0 ]]; then
    log_info "Max tasks: $MAX_TASKS"
  fi
  if [[ "$STRICT_MODE" == "true" ]]; then
    log_info "Strict mode: ENABLED (TDD, cross-review, auto-commit)"
  fi

  print_status

  # Reset any stale IN_PROGRESS beads left over from previous crashed/aborted runs
  reset_stale_in_progress_beads

  local tasks_completed=0
  for ((i=1; i<=MAX_ITERATIONS; i++)); do
    # Check MAX_TASKS limit
    if [[ "$MAX_TASKS" -gt 0 && "$tasks_completed" -ge "$MAX_TASKS" ]]; then
      log_info "Reached max tasks limit ($MAX_TASKS). Stopping."
      break
    fi

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "ITERATION $i of $MAX_ITERATIONS"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Sync external fixes before each iteration
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
      # No staged or unstaged changes - safe to pull
      git pull --rebase origin "$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null || true
    fi

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
      # Check if all done, all blocked, or some failed
      local pending=$(count_tasks "pending")
      local completed=$(count_tasks "completed")
      local failed=$(count_tasks "failed")

      if [[ "$pending" -eq 0 ]]; then
        # No pending tasks - either all completed or some failed
        if [[ "$failed" -eq 0 ]]; then
          # Run full E2E regression suite before declaring success
          if [[ "$FINAL_E2E" == "true" ]]; then
            local e2e_cmd=""
            if has_npm_script "test:e2e"; then
              e2e_cmd="npm run test:e2e"
            elif has_npm_script "e2e"; then
              e2e_cmd="npm run e2e"
            elif [[ -f "$PROJECT_ROOT/playwright.config.ts" ]] || [[ -f "$PROJECT_ROOT/playwright.config.js" ]]; then
              e2e_cmd="npx playwright test"
            fi

            if [[ -n "$e2e_cmd" ]]; then
              echo ""
              log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              log_info "FINAL E2E REGRESSION SUITE"
              log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              log_info "Running: $e2e_cmd"
              echo ""

              set +e
              eval "$e2e_cmd"
              local e2e_rc=$?
              set -e

              if [[ $e2e_rc -ne 0 ]]; then
                echo ""
                log_error "╔════════════════════════════════════════════════════╗"
                log_error "║     FINAL E2E SUITE FAILED - REGRESSIONS FOUND     ║"
                log_error "╚════════════════════════════════════════════════════╝"
                log_error "All tasks completed but full E2E suite found regressions."
                log_error "Fix E2E failures before pushing."

                {
                  echo ""
                  echo "---"
                  echo "## Session Failed E2E - $(date -Iseconds)"
                  echo ""
                  echo "- Tasks completed: $completed"
                  echo "- Final E2E suite: FAILED"
                  echo "- Regressions detected in full test suite"
                  echo ""
                } >> "$PROGRESS_FILE"

                exit 1
              fi
              log_success "Full E2E regression suite passed!"
            fi
          fi

          echo ""
          log_success "╔════════════════════════════════════════════════════╗"
          log_success "║          ALL TASKS COMPLETED SUCCESSFULLY          ║"
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
            echo "- Total completed: $completed"
            echo "- Build failures during session: $BUILD_FAIL_COUNT"
            echo ""
          } >> "$PROGRESS_FILE"

          echo "<promise>COMPLETE</promise>"
          exit 0
        else
          # Some tasks failed, no pending tasks left
          echo ""
          log_warn "╔════════════════════════════════════════════════════╗"
          log_warn "║          SESSION ENDED - SOME TASKS FAILED         ║"
          log_warn "╚════════════════════════════════════════════════════╝"
          print_status

          # Final summary to progress file
          {
            echo ""
            echo "---"
            echo "## Session Ended - $(date -Iseconds)"
            echo ""
            echo "- Status: Some tasks failed"
            echo "- Completed: $completed"
            echo "- Failed: $failed"
            echo "- Iterations used: $i"
            echo "- Build failures during session: $BUILD_FAIL_COUNT"
            echo ""
            echo "Review failed tasks before retrying."
          } >> "$PROGRESS_FILE"

          exit 1
        fi
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
          echo "- Completed: $completed"
          echo "- Failed: $failed"
          echo "- Pending (blocked): $pending"
          echo "- Build failures: $BUILD_FAIL_COUNT"
          echo ""
          echo "Check task dependencies and failed tasks."
        } >> "$PROGRESS_FILE"

        exit 1
      fi
    fi
    
    task_json=$(ensure_task_verification "$task_json") || {
      local failed_id
      failed_id=$(echo "$task_json" | jq -r '.id // "unknown"')
      mark_task_failed "$failed_id"
      log_warn "Task $failed_id missing verification. Marked failed."
      print_status
      sleep 2
      continue
    }

    local task_id=$(echo "$task_json" | jq -r '.id')
    local subject=$(echo "$task_json" | jq -r '.subject')
    local tags=$(echo "$task_json" | jq -r '(.tags // []) | join(", ")')
    local task_verification
    task_verification=$(get_task_verification "$task_json")
    local task_llm_verification
    task_llm_verification=$(get_task_llm_verification "$task_json")
    
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
    echo "$prompt" > "${TMPDIR:-/tmp}/ralph-prompt-$task_id.md"
    
    # Set current task for logging
    CURRENT_TASK_ID="$task_id"
    
    # Set subject for loop state tracking
    CURRENT_SUBJECT="$subject"

    # Run with selected tool
    log_info "Spawning $selected_tool instance..."
    log_info "Log file: $LOGS_DIR/${task_id}.log"
    update_loop_state "running" "implement" 1 "started"

    local start_time=$(date +%s)
    set +e
    OUTPUT=$(run_with_tool "$selected_tool" "$prompt")
    local tool_rc=$?
    set -e
    local end_time=$(date +%s)
    local elapsed_total_seconds=$((end_time - start_time))
    local elapsed_minutes=$((elapsed_total_seconds / 60))
    local elapsed_seconds=$((elapsed_total_seconds % 60))

    # Handle tool failures (including timeouts)
    if [[ "$tool_rc" -ne 0 ]]; then
      local fail_reason="tool exit code $tool_rc"
      local output_size=${#OUTPUT}

      # Check if output contains TASK_COMPLETE despite error exit code
      # This can happen if process is killed after completing work
      if echo "$OUTPUT" | grep -q "<promise>TASK_COMPLETE</promise>"; then
        log_warn "Process exited with rc=$tool_rc but output contains TASK_COMPLETE"
        log_warn "Elapsed: ${elapsed_minutes}m ${elapsed_seconds}s - attempting to process as success"
        # Don't treat as failure - fall through to success handling below
      else
        # Detect signal-based exit codes
        # 124 = GNU timeout command exit code
        # 137 = 128+9 = SIGKILL
        # 143 = 128+15 = SIGTERM
        if [[ "$tool_rc" -eq 124 ]]; then
          # Exit code 124 is specifically from the timeout command
          fail_reason="timeout after ${elapsed_minutes}m ${elapsed_seconds}s (rc=124)"
          log_error "Tool timed out after ${elapsed_minutes}m ${elapsed_seconds}s (timeout command)"
          update_loop_state "timeout" "implement" 1 "timed out"
        elif [[ "$tool_rc" -eq 137 ]] || [[ "$tool_rc" -eq 143 ]]; then
          # Signal-based termination - could be timeout OR external kill
          local timeout_threshold=$(( STALL_MINUTES * 60 - 60 ))  # Within 1 min of timeout
          if [[ "$elapsed_total_seconds" -ge "$timeout_threshold" ]]; then
            fail_reason="timeout after ${elapsed_minutes}m ${elapsed_seconds}s (signal, rc=$tool_rc)"
            log_error "Tool likely timed out after ${elapsed_minutes}m ${elapsed_seconds}s (exit code $tool_rc)"
            update_loop_state "timeout" "implement" 1 "timed out"
          else
            fail_reason="killed by signal after ${elapsed_minutes}m ${elapsed_seconds}s (rc=$tool_rc)"
            log_error "Tool killed by signal after ${elapsed_minutes}m ${elapsed_seconds}s (exit code $tool_rc)"
            log_error "This was NOT a timeout - process was killed externally or crashed"
            update_loop_state "failed" "implement" 1 "killed by signal"
          fi

          # Check if output is empty/minimal
          if [[ "$output_size" -lt 100 ]]; then
            log_error "EMPTY OUTPUT DETECTED - CLI may have hung during startup"
            fail_reason="${fail_reason}, no output"
          fi
        else
          log_error "Tool failed with exit code $tool_rc after ${elapsed_minutes}m ${elapsed_seconds}s"
          update_loop_state "failed" "implement" 1 "tool failed (rc=$tool_rc)"
        fi

        handle_task_failure "$task_id" "$subject" "$selected_tool" "$i" "$fail_reason" "tool failed (rc=$tool_rc)"

        if [[ "$CONTINUE_ON_ERROR" == "true" ]]; then
          log_warn "Task failed. Waiting 30s before next task..."
          sleep 30
          CURRENT_TASK_ID=""
          continue
        else
          log_error "Stopping due to tool failure. Use --continue-on-error to keep going."
          exit 1
        fi
      fi
    fi

    # Keep CURRENT_TASK_ID set through reviews for logging

    # Check for completion signal
    if echo "$OUTPUT" | grep -q "<promise>TASK_COMPLETE</promise>"; then
      log_info "Agent reports task complete. Verifying build..."

      # CRITICAL: Run task-specific verification BEFORE any reviews
      # Re-read verification commands in case they were updated during iteration
      local fresh_verification
      fresh_verification=$(refresh_task_verification "$task_id")
      if [[ -n "$fresh_verification" ]]; then
        task_verification="$fresh_verification"
      fi

      if ! run_task_verification "$task_id" "$task_verification"; then
        log_error "Task-specific verification FAILED"
        handle_task_failure "$task_id" "$subject" "$selected_tool" "$i" "task verification" "verification failed"
        print_status
        sleep 2
        continue
      fi

      # CRITICAL: Verify build BEFORE any reviews
      # This catches TypeScript errors, broken imports, and integration issues
      local has_scoped_tests="false"
      if [[ -n "$task_verification" ]] && echo "$task_verification" | grep -qiE "test|spec|jest|vitest|playwright"; then
        has_scoped_tests="true"
      fi
      if ! verify_build "$task_id" "$has_scoped_tests"; then
        # Build failed - task is NOT complete despite agent's claim
        log_error "Build verification FAILED - task is NOT complete!"
        log_error "The agent said TASK_COMPLETE but the code doesn't compile."

        # Check for flaky test pattern (same failure repeated)
        local build_log="$LOGS_DIR/${task_id}-build.log"
        local error_output=""
        [[ -f "$build_log" ]] && error_output=$(cat "$build_log")

        if check_flaky_skip "$task_id" "$error_output"; then
          # Flaky failure detected - task marked as blocked, skip to next
          clear_task_tracking "$task_id"
          {
            echo ""
            echo "### Iteration $i - $(date -Iseconds)"
            echo "- Task: $task_id - $subject"
            echo "- Status: ⚠️ BLOCKED (flaky test - $FLAKY_FAIL_THRESHOLD identical failures)"
          } >> "$PROGRESS_FILE"
          print_status
          sleep 2
          continue
        fi

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
        CURRENT_TASK_ID=""
        sleep 2
        continue
      fi

      log_success "Initial build verification passed!"

      # REVIEWS RUN BEFORE MARKING COMPLETE
      # Reviews may modify code (Healer), so we re-verify after

      # COUNCIL OF SUBAGENTS REVIEW (if enabled)
      # Uses specialized subagents: Analyst (quality), Sentinel (anti-patterns), Designer (UI), Healer (fixes)
      local ran_reviews=false
      local review_tool=""
      if [[ "${COUNCIL_REVIEW:-false}" == "true" || "${FRESH_EYES:-false}" == "true" ]]; then
        review_tool=$(get_review_tool_for_task "$selected_tool")
        if [[ "$ALLOW_SAME_REVIEW_TOOL" != "true" && "$review_tool" == "$selected_tool" ]]; then
          log_error "Fresh-eyes review requires an independent reviewer."
          log_error "Use --review-tool or --allow-same-review-tool to proceed."
          exit 1
        fi
      fi
      if [[ "${COUNCIL_REVIEW:-false}" == "true" ]]; then
        ran_reviews=true
        log_info "Running Council of Subagents review..."
        if ! run_council_review "$task_id" "$review_tool" "$tags"; then
          log_error "Council review found unfixable issues!"
          log_warn "Consider manual review of council findings"
        fi
      fi

      # FRESH EYES REVIEW (if enabled)
      if [[ "${FRESH_EYES:-false}" == "true" ]]; then
        ran_reviews=true
        if [[ "$review_tool" != "$selected_tool" ]]; then
          log_info "Cross-model review: coded with $selected_tool, reviewing with $review_tool"
        else
          log_info "Running fresh eyes code review..."
        fi
        run_fresh_eyes_review "$review_tool"
      fi

      # RE-VERIFY after reviews (Healer may have modified code)
      if [[ "$ran_reviews" == "true" ]]; then
        log_info "Re-verifying build after reviews..."
        if ! verify_build "$task_id" "$has_scoped_tests"; then
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
          CURRENT_TASK_ID=""
          sleep 2
          continue
        fi
        log_success "Post-review verification passed!"
      fi

      # LLM-as-judge verification for subjective criteria (if provided)
      if [[ -n "$task_llm_verification" ]]; then
        log_info "Running LLM verification (subjective checks)..."
        if ! run_llm_verification "$task_id" "$task_llm_verification"; then
          log_error "LLM verification FAILED"
          mark_task_failed "$task_id"
          clear_task_tracking "$task_id"
          {
            echo ""
            echo "### Iteration $i - $(date -Iseconds)"
            echo "- Task: $task_id - $subject"
            echo "- Tool: $selected_tool"
            echo "- Status: ❌ FAILED (LLM verification)"
          } >> "$PROGRESS_FILE"
          print_status
          CURRENT_TASK_ID=""
          sleep 2
          continue
        fi
      fi

      # TDD ENFORCEMENT: Verify test files were changed (strict mode)
      if [[ "$STRICT_MODE" == "true" || "$ALLOW_NO_TESTS" == "false" ]]; then
        if ! require_test_changes "$tags"; then
          mark_task_failed "$task_id"
          clear_task_tracking "$task_id"
          append_summary "$task_id" "$subject" "FAILED" "-" "no test changes"
          {
            echo ""
            echo "### Iteration $i - $(date -Iseconds)"
            echo "- Task: $task_id - $subject"
            echo "- Tool: $selected_tool"
            echo "- Status: ❌ FAILED (TDD: no test changes)"
          } >> "$PROGRESS_FILE"
          print_status
          CURRENT_TASK_ID=""
          sleep 2
          continue
        fi
      fi

      # ALL CHECKS PASSED - Now mark task as completed
      mark_task_completed "$task_id"

      # Clear stall tracking
      clear_task_tracking "$task_id"

      # Commit changes if auto-commit is enabled
      local commit_hash=""
      if [[ "$AUTO_COMMIT" == "true" ]]; then
        if commit_task_changes "$task_id" "$subject"; then
          commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
          log_success "Changes committed: $commit_hash"
        fi
      fi

      # Log to progress
      {
        echo ""
        echo "### Iteration $i - $(date -Iseconds)"
        echo "- Task: $task_id - $subject"
        echo "- Tool: $selected_tool"
        echo "- Status: ✅ COMPLETED"
        echo "- Build: ✅ VERIFIED"
        if [[ -n "$commit_hash" ]]; then
          echo "- Commit: $commit_hash"
        fi
      } >> "$PROGRESS_FILE"

      log_success "Task completed and all verifications passed!"
      append_summary "$task_id" "$subject" "DONE" "${commit_hash:-manual}" "clean"
      update_loop_state "completed" "done" 1 "all checks passed"

      # Increment tasks completed counter
      tasks_completed=$((tasks_completed + 1))
      log_info "Tasks completed this run: $tasks_completed"

      # Capture learnings from task execution
      capture_learnings "$task_id" "$subject" "$selected_tool" "$OUTPUT" "$review_tool" "$ran_reviews"

      # Commit any state files modified after task commit (beads, loop state, etc.)
      if [[ "$AUTO_COMMIT" == "true" && -n "$(git status --porcelain 2>/dev/null)" ]]; then
        git add -A
        git commit -m "chore: update state after $task_id" --no-verify 2>/dev/null || true
        if [[ "$AUTO_PUSH" == "true" ]]; then
          git push 2>/dev/null || true
        fi
      fi

      # AUTO-PR: Create PR for completed task
      if [[ "${AUTO_PR:-true}" == "true" ]]; then
        create_auto_pr "$task_id" "$subject"
      fi

      # Clear current task ID after all agent activity
      CURRENT_TASK_ID=""
      
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
      CURRENT_TASK_ID=""

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
      CURRENT_TASK_ID=""
      
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
      CURRENT_TASK_ID=""
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
