#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_GRAPH="$PROJECT_ROOT/artifacts/04-task-graph.json"

TOOL="claude"
REVIEW_TOOL="claude"
MAX_ITERATIONS=3
ALLOW_NO_TESTS="false"
ALLOW_NO_VERIFY="false"
LOOP_MODE="false"
AUTO_COMMIT="true"
AUTO_PUSH="false"
COMMIT_PREFIX="feat"
TASK_ID=""
SUBJECT=""
DESCRIPTION=""
ACCEPTANCE=""
FILES_HINT=""
VERIFY_CMDS=""
TAGS=""

usage() {
  cat <<'USAGE'
Strict Ralph - TDD + Fresh-Instance Review Loop

Usage:
  ./scripts/strict_ralph.sh --task-id <id> [options]

Options:
  --task-id <id>           Task ID from artifacts/04-task-graph.json
  --task-graph <path>      Path to task-graph.json (default: artifacts/04-task-graph.json)
  --tool <claude|codex>    Tool for implementation (default: claude)
  --review-tool <claude|codex|manual> Tool for review (default: claude)
  --verification <cmds>    Semicolon-separated verification commands
  --max-iterations <n>     Max review loops (default: 3)
  --allow-no-tests         Allow tasks with no test changes
  --allow-no-verify        Allow tasks with no verification commands
  --loop                   Auto-pick next unblocked task until done
  --no-commit              Do not auto-commit after successful review
  --auto-push              Push after each commit (requires clean upstream)
  --commit-prefix <type>   Commit prefix (default: feat)
  -h, --help               Show help

Notes:
- Requires a clean task definition in task-graph.json.
- Fails if no tests are added unless --allow-no-tests is set.
- Fails if no verification commands are found unless --allow-no-verify is set.
USAGE
}

log() { echo "[strict-ralph] $*"; }
fail() { echo "[strict-ralph] ERROR: $*" >&2; exit 1; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task-id)
        TASK_ID="$2"; shift 2 ;;
      --task-graph)
        TASK_GRAPH="$2"; shift 2 ;;
      --tool)
        TOOL="$2"; shift 2 ;;
      --review-tool)
        REVIEW_TOOL="$2"; shift 2 ;;
      --verification)
        VERIFY_CMDS="$2"; shift 2 ;;
      --max-iterations)
        MAX_ITERATIONS="$2"; shift 2 ;;
      --allow-no-tests)
        ALLOW_NO_TESTS="true"; shift ;;
      --allow-no-verify)
        ALLOW_NO_VERIFY="true"; shift ;;
      --loop)
        LOOP_MODE="true"; shift ;;
      --no-commit)
        AUTO_COMMIT="false"; shift ;;
      --auto-push)
        AUTO_PUSH="true"; shift ;;
      --commit-prefix)
        COMMIT_PREFIX="$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        fail "Unknown argument: $1" ;;
    esac
  done
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_clean_worktree() {
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    fail "Working tree is not clean. Commit or stash changes before running strict loop."
  fi
}

select_next_task() {
  require_cmd jq
  local next
  next=$(jq -r '
    def doneIds:
      [ .phases[].tasks[]
        | select((.status // "pending") == "complete" or (.status // "pending") == "committed")
        | .id ];
    def isUnblocked($done):
      ((.status // "pending") == "pending")
      and (((.dependsOn // []) | length) == 0
           or ((.dependsOn // []) | all(. as $d | $done | index($d))));

    doneIds as $done
    | .phases
    | map(.tasks | map(select(isUnblocked($done))))
    | map(select(length > 0) | .[0])
    | .[0].id // empty
  ' "$TASK_GRAPH")
  if [[ -z "$next" ]]; then
    return 1
  fi
  TASK_ID="$next"
}

update_task_status() {
  local id="$1"
  local status="$2"
  local commit_hash="${3:-}"
  local now
  now=$(date -Iseconds)
  local tmp
  tmp=$(mktemp)

  jq --arg id "$id" --arg status "$status" --arg now "$now" --arg ch "$commit_hash" '
    .phases |= map(
      .tasks |= map(
        if .id == $id then
          .status = $status
          | .lastProgress = $now
          | (if $status == "running" then .startedAt = $now else . end)
          | (if $status == "committed" or $status == "complete" then .completedAt = $now else . end)
          | (if $status == "committed" and ($ch | length) > 0 then .commitHash = $ch else . end)
        else
          .
        end
      )
    )
  ' "$TASK_GRAPH" > "$tmp" && mv "$tmp" "$TASK_GRAPH"
}

should_require_tests() {
  local tags="$1"
  if [[ -z "$tags" ]]; then
    return 0
  fi
  if echo "$tags" | grep -E -qi '(core|api|ui|component|worker|data|feature|backend|frontend|db)'; then
    return 0
  fi
  if echo "$tags" | grep -E -qi '(docs?|chore|setup|config|infra|ops|verify)'; then
    return 1
  fi
  return 0
}

load_task() {
  if [[ -z "$TASK_ID" ]]; then
    fail "--task-id is required"
  fi
  if [[ ! -f "$TASK_GRAPH" ]]; then
    fail "Task graph not found at $TASK_GRAPH"
  fi
  require_cmd jq

  SUBJECT=$(jq -r --arg id "$TASK_ID" '.tasks[] | select(.id==$id) | .subject // ""' "$TASK_GRAPH")
  DESCRIPTION=$(jq -r --arg id "$TASK_ID" '.tasks[] | select(.id==$id) | .description // ""' "$TASK_GRAPH")
  FILES_HINT=$(jq -r --arg id "$TASK_ID" '.tasks[] | select(.id==$id) | .files // [] | if type=="array" then join(", ") else . end' "$TASK_GRAPH")
  ACCEPTANCE=$(jq -r --arg id "$TASK_ID" '.tasks[] | select(.id==$id) | .acceptance // [] | if type=="array" then join("\n") else . end' "$TASK_GRAPH")
  TAGS=$(jq -r --arg id "$TASK_ID" '.tasks[] | select(.id==$id) | .tags // [] | if type=="array" then join(",") else . end' "$TASK_GRAPH")

  if [[ -z "$VERIFY_CMDS" ]]; then
    VERIFY_CMDS=$(jq -r --arg id "$TASK_ID" '.tasks[] | select(.id==$id) | .verification // [] | if type=="array" then join(";") else . end' "$TASK_GRAPH")
  fi

  if [[ -z "$SUBJECT" ]]; then
    fail "Task $TASK_ID not found in $TASK_GRAPH"
  fi
}

run_with_tool() {
  local tool="$1"
  local prompt="$2"

  case "$tool" in
    claude)
      require_cmd claude
      claude -p --dangerously-skip-permissions "$prompt"
      ;;
    codex)
      require_cmd codex
      codex exec --yolo "$prompt"
      ;;
    manual)
      echo "----- PROMPT START -----"
      echo "$prompt"
      echo "----- PROMPT END -----"
      echo "Run the prompt in a fresh instance, then paste output and end with 'END_REVIEW'."
      local out=""
      while IFS= read -r line; do
        if [[ "$line" == "END_REVIEW" ]]; then
          break
        fi
        out+="$line"$'\n'
      done
      printf "%s" "$out"
      ;;
    *)
      fail "Unsupported tool: $tool"
      ;;
  esac
}

collect_diff() {
  local diff
  diff=$(git diff HEAD 2>/dev/null || git diff 2>/dev/null || echo "")
  if [[ -z "$diff" ]]; then
    printf "%s" "$diff"
    return 0
  fi
  local line_count
  line_count=$(printf "%s\n" "$diff" | wc -l | tr -d ' ')
  if [[ "$line_count" -gt 500 ]]; then
    printf "%s\n" "$(printf "%s\n" "$diff" | head -n 500)"
    printf "\n[diff truncated to 500 lines]\n"
    return 0
  fi
  printf "%s" "$diff"
}

changed_files() {
  git diff --name-status HEAD 2>/dev/null || git diff --name-status 2>/dev/null || echo ""
}

require_changes() {
  local diff
  diff=$(collect_diff)
  if [[ -z "$diff" ]]; then
    fail "No uncommitted changes detected. Run after implementation and before commit."
  fi
}

require_test_changes() {
  if [[ "$ALLOW_NO_TESTS" == "true" ]]; then
    return 0
  fi
  if ! should_require_tests "$TAGS"; then
    log "Skipping test-change requirement for non-test task tags: $TAGS"
    return 0
  fi
  local files
  files=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "")
  local test_pattern='(^|/)(tests?|__tests__|__test__|specs?)/|\.test\.|\.spec\.|_test\.(py|go|rs|rb|php)$|_spec\.rb$|test_.*\.py$|\.bats$'
  if ! echo "$files" | grep -E -q "$test_pattern"; then
    fail "No test changes detected. Add real tests or pass --allow-no-tests for non-test tasks."
  fi
}

run_verification() {
  if [[ -z "$VERIFY_CMDS" ]]; then
    if [[ "$ALLOW_NO_VERIFY" == "true" ]]; then
      log "No verification commands provided. Skipping verification."
      return 0
    fi
    fail "No verification commands provided. Use --verification or set in task graph."
  fi

  IFS=';' read -r -a cmds <<< "$VERIFY_CMDS"
  for cmd in "${cmds[@]}"; do
    cmd=$(echo "$cmd" | xargs)
    if [[ -z "$cmd" ]]; then
      continue
    fi
    log "Running verification: $cmd"
    (cd "$PROJECT_ROOT" && bash -lc "$cmd")
  done
}

build_prompt_impl() {
  cat <<EOF
You are implementing task $TASK_ID: $SUBJECT

Files to modify:
$FILES_HINT

Description:
$DESCRIPTION

Acceptance Criteria:
$ACCEPTANCE

Strict requirements:
- TDD is required for feature work. Write tests first.
- No fake/tautological tests. Every test must exercise real behavior and assert state/output changes.
- If integration is not ready, add a minimal test harness (UI route, CLI fixture, API runner).
- Run the verification commands provided by the plan.

When done, do NOT add extra commentary. Keep changes minimal and correct.
EOF
}

build_prompt_review() {
  local diff="$1"
  local files="$2"

  cat <<EOF
You are a strict code reviewer for task $TASK_ID: $SUBJECT.

Acceptance Criteria:
$ACCEPTANCE

Changed files:
$files

Diff (may be truncated):
$diff

Review requirements:
- Verify acceptance criteria are met.
- Verify tests are real (behavioral) and not tautological.
- Verify no regressions or missing edge cases.

If no issues found, output exactly:
NO_ISSUES_FOUND

If issues found, list each as:
[P1] Issue title - file:line
  Description and suggested fix.
EOF
}

build_prompt_fix() {
  local issues="$1"
  cat <<EOF
You reviewed this task and found issues. Fix ALL issues below.

Task: $TASK_ID - $SUBJECT

Issues:
$issues

Rules:
- Keep tests real and behavioral.
- Run verification commands after fixes.
- Make minimal changes.
EOF
}

commit_task() {
  if [[ "$AUTO_COMMIT" != "true" ]]; then
    return 0
  fi
  git add -A
  local message="$COMMIT_PREFIX($TASK_ID): $SUBJECT"
  git commit -m "$message"
  if [[ "$AUTO_PUSH" == "true" ]]; then
    git push
  fi
}

run_task_loop() {
  local issues=""
  local iter
  for ((iter=1; iter<=MAX_ITERATIONS; iter++)); do
    if [[ $iter -eq 1 ]]; then
      log "Iteration $iter: implementing"
      run_with_tool "$TOOL" "$(build_prompt_impl)" >/tmp/strict_impl_$TASK_ID.log 2>&1
    else
      log "Iteration $iter: fixing issues"
      run_with_tool "$TOOL" "$(build_prompt_fix "$issues")" >/tmp/strict_fix_$TASK_ID.log 2>&1
    fi

    require_changes
    require_test_changes
    run_verification

    local diff
    diff=$(collect_diff)
    local files
    files=$(changed_files)

    local review_output
    review_output=$(run_with_tool "$REVIEW_TOOL" "$(build_prompt_review "$diff" "$files")")

    if echo "$review_output" | grep -qx "NO_ISSUES_FOUND"; then
      log "Review clean. Task complete."
      return 0
    fi

    issues=$(echo "$review_output" | grep -E '^\[P[123]\]' || true)
    if [[ -z "$issues" ]]; then
      log "Review output contained no parsable issues. Failing for safety."
      echo "$review_output"
      return 1
    fi

    log "Issues found. Re-running implementer with fixes."
  done

  fail "Exceeded max iterations ($MAX_ITERATIONS) without clean review."
}

main() {
  parse_args "$@"

  if [[ "$LOOP_MODE" == "true" ]]; then
    require_clean_worktree
    while select_next_task; do
      VERIFY_CMDS=""
      load_task
      log "Next task: $TASK_ID - $SUBJECT"
      update_task_status "$TASK_ID" "running"
      if ! run_task_loop; then
        update_task_status "$TASK_ID" "error"
        fail "Task $TASK_ID failed review."
      fi
      commit_task
      local ch
      ch=$(git rev-parse HEAD 2>/dev/null || echo "")
      update_task_status "$TASK_ID" "committed" "$ch"
      require_clean_worktree
    done
    log "No more unblocked tasks found. Done."
    exit 0
  fi

  load_task
  log "Task: $TASK_ID - $SUBJECT"
  run_task_loop
  exit 0
}

main "$@"
