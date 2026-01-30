#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_GRAPH="$PROJECT_ROOT/artifacts/04-task-graph.json"

TOOL="claude"
REVIEW_TOOL=""
ALLOW_SAME_REVIEW_TOOL="false"
MAX_ITERATIONS=3
MAX_TASK_ATTEMPTS=3
STALL_MINUTES=45
ALLOW_NO_TESTS="false"
ALLOW_NO_VERIFY="false"
DEFAULT_VERIFY=""
ALLOW_DIRTY="false"
LOOP_MODE="false"
USE_BEADS="false"
AUTO_COMMIT="true"
AUTO_PUSH="false"
COMMIT_PREFIX="feat"
PROGRESS_FILE=""
LEARNINGS_FILE=""
SUMMARY_FILE=""
LOOP_STATE_FILE=""
RUN_ID=""
TASK_ID=""
SUBJECT=""
DESCRIPTION=""
ACCEPTANCE=""
FILES_HINT=""
VERIFY_CMDS=""
LLM_VERIFY=""
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
  --review-tool <claude|codex|manual> Tool for review (default: opposite of --tool)
  --verification <cmds>    Semicolon-separated verification commands
  --default-verify <cmds>  Default verification commands if task is missing them
  --llm-verify <criteria>  LLM-based subjective checks (one per line)
  --max-iterations <n>     Max review loops (default: 3)
  --max-attempts <n>        Max attempts per task (default: 3)
  --stall-minutes <n>       Max minutes per tool run if timeout is available (default: 45)
  --allow-no-tests         Allow tasks with no test changes
  --allow-no-verify        Allow tasks with no verification commands
  --allow-same-review-tool Allow review tool to match implementation tool
  --allow-dirty            Allow running loop with uncommitted changes (not recommended)
  --loop                   Auto-pick next unblocked task until done
  --beads                  Use beads_rust (br) instead of task-graph.json
  --no-commit              Do not auto-commit after successful review
  --auto-push              Push after each commit (requires clean upstream)
  --commit-prefix <type>   Commit prefix (default: feat)
  -h, --help               Show help

Notes:
- Requires a clean task definition in task-graph.json (unless using --beads).
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
      --default-verify)
        DEFAULT_VERIFY="$2"; shift 2 ;;
      --llm-verify)
        LLM_VERIFY="$2"; shift 2 ;;
      --max-iterations)
        MAX_ITERATIONS="$2"; shift 2 ;;
      --max-attempts)
        MAX_TASK_ATTEMPTS="$2"; shift 2 ;;
      --stall-minutes)
        STALL_MINUTES="$2"; shift 2 ;;
      --allow-no-tests)
        ALLOW_NO_TESTS="true"; shift ;;
      --allow-no-verify)
        ALLOW_NO_VERIFY="true"; shift ;;
      --allow-same-review-tool)
        ALLOW_SAME_REVIEW_TOOL="true"; shift ;;
      --allow-dirty)
        ALLOW_DIRTY="true"; shift ;;
      --loop)
        LOOP_MODE="true"; shift ;;
      --beads)
        USE_BEADS="true"; shift ;;
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

load_default_verification() {
  local default_value="${DEFAULT_VERIFY:-${RALPH_DEFAULT_VERIFY:-}}"
  if [[ -z "$default_value" && -f "$PROJECT_ROOT/verification.txt" ]]; then
    default_value=$(grep -v '^[[:space:]]*#' "$PROJECT_ROOT/verification.txt" | sed '/^[[:space:]]*$/d')
  fi
  printf '%s\n' "$default_value"
}

init_run_files() {
  PROGRESS_FILE="$PROJECT_ROOT/progress.txt"
  LEARNINGS_FILE="$PROJECT_ROOT/learnings.md"
  SUMMARY_FILE="$PROJECT_ROOT/artifacts/08-execution-summary.md"
  LOOP_STATE_FILE="$PROJECT_ROOT/artifacts/08-loop_state.json"
  RUN_ID=$(date -Iseconds)

  mkdir -p "$PROJECT_ROOT/artifacts"

  if [[ ! -f "$SUMMARY_FILE" ]]; then
    cat <<EOF > "$SUMMARY_FILE"
# Execution Summary (strict_ralph)

Run Started: $RUN_ID

| Task ID | Subject | Status | Commit | Notes |
|--------|---------|--------|--------|-------|
EOF
  fi
}

resolve_review_tool() {
  case "$TOOL" in
    claude|codex) ;;
    *)
      fail "Unsupported tool: $TOOL"
      ;;
  esac

  if [[ -z "$REVIEW_TOOL" ]]; then
    case "$TOOL" in
      claude) REVIEW_TOOL="codex" ;;
      codex) REVIEW_TOOL="claude" ;;
    esac
  fi

  case "$REVIEW_TOOL" in
    claude|codex|manual) ;;
    *)
      fail "Unsupported review tool: $REVIEW_TOOL"
      ;;
  esac

  if [[ "$ALLOW_SAME_REVIEW_TOOL" != "true" && "$REVIEW_TOOL" == "$TOOL" ]]; then
    fail "Review tool must differ from implementation tool. Use --review-tool or --allow-same-review-tool."
  fi

  if [[ "$REVIEW_TOOL" != "manual" ]]; then
    require_cmd "$REVIEW_TOOL"
  fi
}

update_loop_state() {
  local status="$1"
  local phase="$2"
  local attempt="$3"
  local note="${4:-}"
  local loop_json=false
  local beads_json=false
  [[ "$LOOP_MODE" == "true" ]] && loop_json=true
  [[ "$USE_BEADS" == "true" ]] && beads_json=true

  require_cmd jq
  jq -n \
    --arg runId "$RUN_ID" \
    --arg updatedAt "$(date -Iseconds)" \
    --arg taskId "$TASK_ID" \
    --arg subject "$SUBJECT" \
    --arg status "$status" \
    --arg phase "$phase" \
    --arg note "$note" \
    --arg implementer "$TOOL" \
    --arg reviewer "$REVIEW_TOOL" \
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

log_progress() {
  local msg="$1"
  printf '%s %s\n' "$(date -Iseconds)" "$msg" >> "$PROGRESS_FILE"
}

log_learning() {
  local msg="$1"
  printf '## %s\n- %s\n\n' "$(date -Iseconds)" "$msg" >> "$LEARNINGS_FILE"
}

append_summary() {
  local id="$1"
  local subject="$2"
  local status="$3"
  local commit="$4"
  local notes="$5"
  printf '| %s | %s | %s | %s | %s |\n' "$id" "$subject" "$status" "$commit" "$notes" >> "$SUMMARY_FILE"
}

require_beads() {
  require_cmd br
  if [[ ! -d "$PROJECT_ROOT/.beads" ]]; then
    fail "Beads not initialized. Run: br init"
  fi
}

require_clean_worktree() {
  if [[ "$ALLOW_DIRTY" == "true" ]]; then
    log "Warning: running with dirty worktree (--allow-dirty)."
    return 0
  fi
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    fail "Working tree is not clean. Commit or stash changes before running strict loop."
  fi
}

select_next_task() {
  if [[ "$USE_BEADS" == "true" ]]; then
    require_beads
    require_cmd jq
    local ready
    ready=$(br ready --json 2>/dev/null || echo "[]")
    TASK_ID=$(echo "$ready" | jq -r '.[0].id // empty')
  else
    require_cmd jq
    local next
    next=$(jq -r '
      def isDone:
        ((.status // "pending") == "complete"
         or (.status // "pending") == "completed"
         or (.status // "pending") == "committed");
      def doneIds:
        [ .phases[].tasks[]
          | select(isDone)
          | .id ];
      def isUnblocked($done):
        ((.status // "pending") == "pending")
        and (((.dependsOn // []) | length) == 0
             or ((.dependsOn // []) | all(. as $d | $done | index($d))));

      doneIds as $done
      | .phases
      | map(select(.tasks | any(.; (isDone | not))))
      | .[0] as $phase
      | if $phase == null then "" else
          ($phase.tasks | map(select(isUnblocked($done))) | .[0].id // empty)
        end
    ' "$TASK_GRAPH")
    TASK_ID="$next"
  fi
  if [[ -z "$TASK_ID" ]]; then
    return 1
  fi
}

update_task_status() {
  local id="$1"
  local status="$2"
  local commit_hash="${3:-}"
  local now
  now=$(date -Iseconds)
  if [[ "$USE_BEADS" == "true" ]]; then
    case "$status" in
      running)
        br update "$id" --status in_progress 2>/dev/null || true
        ;;
      committed|complete)
        br close "$id" --reason "completed" 2>/dev/null || true
        ;;
      error)
        br update "$id" --status blocked --comment "Failed during strict loop" 2>/dev/null || true
        ;;
      *)
        br update "$id" --status "$status" 2>/dev/null || true
        ;;
    esac
    return 0
  fi

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
  if [[ "$USE_BEADS" == "true" ]]; then
    require_beads
    require_cmd jq
    local bead
    bead=$(br show "$TASK_ID" --json 2>/dev/null || echo "[]")
    SUBJECT=$(echo "$bead" | jq -r 'if type=="array" then .[0] else . end | .title // ""')
    DESCRIPTION=$(echo "$bead" | jq -r 'if type=="array" then .[0] else . end | .description // ""')
    TAGS=$(echo "$bead" | jq -r 'if type=="array" then .[0] else . end | .labels // [] | if type=="array" then join(",") else . end')
    FILES_HINT=""
    ACCEPTANCE=""
    if [[ -z "$VERIFY_CMDS" ]]; then
      VERIFY_CMDS=""
    fi
    if [[ -n "$DESCRIPTION" ]]; then
      local acc
      local ver
      local llm
      local files
      acc=$(printf '%s\n' "$DESCRIPTION" | awk '
        BEGIN{found=0}
        /^(Acceptance Criteria:|ACCEPTANCE:)/ {found=1; next}
        found && /^[A-Z][A-Za-z ]+:/ {exit}
        found {print}
      ')
      ver=$(printf '%s\n' "$DESCRIPTION" | awk '
        BEGIN{found=0}
        /^(Verification:|VERIFICATION:)/ {found=1; next}
        found && /^[A-Z][A-Za-z ]+:/ {exit}
        found {print}
      ')
      llm=$(printf '%s\n' "$DESCRIPTION" | awk '
        BEGIN{found=0}
        /^(LLM Verification:|LLM VERIFY:|Subjective Checks:|SUBJECTIVE CHECKS:)/ {found=1; next}
        found && /^[A-Z][A-Za-z ]+:/ {exit}
        found {print}
      ')
      files=$(printf '%s\n' "$DESCRIPTION" | awk '
        BEGIN{found=0}
        /^(Files to modify:|ALLOWED PATHS:)/ {found=1; next}
        found && /^[A-Z][A-Za-z ]+:/ {exit}
        found {print}
      ')
      if [[ -n "$acc" ]]; then
        ACCEPTANCE=$(printf '%s\n' "$acc" | sed -e 's/^[ -]*//')
      fi
      if [[ -n "$ver" && -z "$VERIFY_CMDS" ]]; then
        VERIFY_CMDS=$(printf '%s\n' "$ver" | sed -e 's/^[ -]*//' | paste -sd ';' -)
      fi
      if [[ -n "$llm" && -z "$LLM_VERIFY" ]]; then
        LLM_VERIFY=$(printf '%s\n' "$llm" | sed -e 's/^[ -]*//' | paste -sd '\n' -)
      fi
      if [[ -n "$files" ]]; then
        FILES_HINT=$(printf '%s\n' "$files" | sed -e 's/^[ -]*//' | paste -sd ', ' -)
      fi
    fi
  else
    if [[ ! -f "$TASK_GRAPH" ]]; then
      fail "Task graph not found at $TASK_GRAPH"
    fi
    require_cmd jq

    SUBJECT=$(jq -r --arg id "$TASK_ID" '.phases[].tasks[] | select(.id==$id) | .subject // ""' "$TASK_GRAPH")
    DESCRIPTION=$(jq -r --arg id "$TASK_ID" '.phases[].tasks[] | select(.id==$id) | .description // ""' "$TASK_GRAPH")
    FILES_HINT=$(jq -r --arg id "$TASK_ID" '.phases[].tasks[] | select(.id==$id) | .files // [] | if type=="array" then join(", ") else . end' "$TASK_GRAPH")
    ACCEPTANCE=$(jq -r --arg id "$TASK_ID" '.phases[].tasks[] | select(.id==$id) | .acceptance // [] | if type=="array" then join("\n") else . end' "$TASK_GRAPH")
    TAGS=$(jq -r --arg id "$TASK_ID" '.phases[].tasks[] | select(.id==$id) | .tags // [] | if type=="array" then join(",") else . end' "$TASK_GRAPH")

    if [[ -z "$VERIFY_CMDS" ]]; then
      VERIFY_CMDS=$(jq -r --arg id "$TASK_ID" '.phases[].tasks[] | select(.id==$id) | .verification // [] | if type=="array" then join(";") else . end' "$TASK_GRAPH")
    fi
    if [[ -z "$LLM_VERIFY" ]]; then
      LLM_VERIFY=$(jq -r --arg id "$TASK_ID" '.phases[].tasks[] | select(.id==$id) | .llmVerification // [] | if type=="array" then join("\n") else . end' "$TASK_GRAPH")
    fi
  fi

  if [[ -z "$SUBJECT" ]]; then
    fail "Task $TASK_ID not found"
  fi
  if [[ -z "$ACCEPTANCE" ]]; then
    ACCEPTANCE="(not provided - see description)"
  fi

  if [[ -z "$VERIFY_CMDS" ]]; then
    local default_verify
    default_verify=$(load_default_verification)
    if [[ -n "$default_verify" ]]; then
      VERIFY_CMDS=$(printf '%s\n' "$default_verify" | paste -sd ';' -)
    fi
  fi
}

run_with_tool() {
  local tool="$1"
  local prompt="$2"
  local timeout_cmd=""

  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout"
  fi

  case "$tool" in
    claude)
      require_cmd claude
      if [[ -n "$timeout_cmd" ]]; then
        "$timeout_cmd" "${STALL_MINUTES}m" claude -p --dangerously-skip-permissions "$prompt"
      else
        claude -p --dangerously-skip-permissions "$prompt"
      fi
      ;;
    codex)
      require_cmd codex
      if [[ -n "$timeout_cmd" ]]; then
        "$timeout_cmd" "${STALL_MINUTES}m" codex exec --yolo "$prompt"
      else
        codex exec --yolo "$prompt"
      fi
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
    if [[ -n "$LLM_VERIFY" ]]; then
      log "No verification commands provided. Using LLM verification only."
      return 0
    fi
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
    if ! (cd "$PROJECT_ROOT" && bash -lc "$cmd"); then
      return 1
    fi
  done
  return 0
}

run_llm_verification() {
  local criteria="$1"
  if [[ -z "$criteria" ]]; then
    return 0
  fi
  local diff
  diff=$(collect_diff)
  local files
  files=$(changed_files)

  local prompt="You are a strict QA judge for subjective acceptance criteria.
If criteria are satisfied, output exactly: LLM_PASS
If criteria are NOT satisfied or cannot be verified, output exactly: LLM_FAIL and a one-line reason.

CRITERIA:
$criteria

CHANGED FILES:
$files

DIFF:
$diff"

  local output
  set +e
  output=$(run_with_tool "$REVIEW_TOOL" "$prompt")
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    return 1
  fi
  if echo "$output" | grep -qx "LLM_PASS"; then
    log "LLM verification passed."
    return 0
  fi
  log "LLM verification failed."
  echo "$output" | head -20
  return 1
}

build_prompt_impl() {
  cat <<EOF
You are implementing task $TASK_ID: $SUBJECT.
This is a fresh CLI session; do not assume any prior context.

Files to modify:
$FILES_HINT

Description:
$DESCRIPTION

Acceptance Criteria:
$ACCEPTANCE

$(if [[ -n "$LLM_VERIFY" ]]; then
echo "LLM Verification (subjective checks):"
echo "$LLM_VERIFY"
echo ""
fi)

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
Ok can you now turn your attention to reviewing the code written by
your fellow agents and checking for any issues, bugs, errors, problems,
inefficiencies, security problems, reliability issues, etc. and carefully
diagnose their underlying root causes using first-principle analysis.

This is a fresh CLI session; do not assume any prior context.

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
  local attempt=0
  local phase="implement"
  for ((iter=1; iter<=MAX_ITERATIONS; iter++)); do
    attempt=$((attempt + 1))
    update_loop_state "running" "$phase" "$attempt" "iteration $iter"
    if [[ "$attempt" -gt "$MAX_TASK_ATTEMPTS" ]]; then
      log "Max attempts ($MAX_TASK_ATTEMPTS) exceeded for $TASK_ID"
      update_loop_state "failed" "$phase" "$attempt" "max attempts exceeded"
      return 1
    fi
    if [[ "$phase" == "implement" ]]; then
      log "Iteration $iter: implementing"
      set +e
      run_with_tool "$TOOL" "$(build_prompt_impl)" >/tmp/strict_impl_$TASK_ID.log 2>&1
      local impl_rc=$?
      set -e
      if [[ "$impl_rc" -ne 0 ]]; then
        log "Implementation tool failed (rc=$impl_rc)."
        log_progress "Task $TASK_ID attempt $attempt failed during implementation"
        update_loop_state "failed" "$phase" "$attempt" "implementation tool failed"
        continue
      fi
    else
      log "Iteration $iter: fixing issues"
      set +e
      run_with_tool "$TOOL" "$(build_prompt_fix "$issues")" >/tmp/strict_fix_$TASK_ID.log 2>&1
      local fix_rc=$?
      set -e
      if [[ "$fix_rc" -ne 0 ]]; then
        log "Fix tool failed (rc=$fix_rc)."
        log_progress "Task $TASK_ID attempt $attempt failed during fix"
        update_loop_state "failed" "$phase" "$attempt" "fix tool failed"
        continue
      fi
    fi

    require_changes
    require_test_changes
    if ! run_verification; then
      log "Verification failed. Retrying."
      log_progress "Task $TASK_ID attempt $attempt failed verification"
      update_loop_state "verification_failed" "$phase" "$attempt" "verification failed"
      phase="implement"
      continue
    fi

    if [[ -n "$LLM_VERIFY" ]]; then
      if ! run_llm_verification "$LLM_VERIFY"; then
        log "LLM verification failed. Retrying."
        log_progress "Task $TASK_ID attempt $attempt failed LLM verification"
        update_loop_state "verification_failed" "$phase" "$attempt" "llm verification failed"
        phase="implement"
        continue
      fi
    fi

    local diff
    diff=$(collect_diff)
    local files
    files=$(changed_files)

    local review_output
    set +e
    review_output=$(run_with_tool "$REVIEW_TOOL" "$(build_prompt_review "$diff" "$files")")
    local review_rc=$?
    set -e
    if [[ "$review_rc" -ne 0 ]]; then
      log "Review tool failed (rc=$review_rc). Retrying."
      log_progress "Task $TASK_ID attempt $attempt failed review"
      update_loop_state "review_failed" "$phase" "$attempt" "review tool failed"
      phase="implement"
      continue
    fi

    if echo "$review_output" | grep -qx "NO_ISSUES_FOUND"; then
      log "Review clean. Task complete."
      update_loop_state "completed" "review" "$attempt" "clean review"
      return 0
    fi

    issues=$(echo "$review_output" | grep -E '^\[P[123]\]' || true)
    if [[ -z "$issues" ]]; then
      log "Review output contained no parsable issues. Failing for safety."
      echo "$review_output"
      update_loop_state "failed" "$phase" "$attempt" "unparsable review output"
      return 1
    fi

    log "Issues found. Re-running implementer with fixes."
    update_loop_state "needs_fix" "review" "$attempt" "issues found"
    phase="fix"
  done

  fail "Exceeded max iterations ($MAX_ITERATIONS) without clean review."
}

main() {
  parse_args "$@"
  init_run_files
  resolve_review_tool

  if [[ "$LOOP_MODE" == "true" ]]; then
    require_clean_worktree
    while select_next_task; do
      VERIFY_CMDS=""
      load_task
      log "Next task: $TASK_ID - $SUBJECT"
      update_loop_state "starting" "implement" 0 "task selected"
      log_progress "START task $TASK_ID - $SUBJECT"
      update_task_status "$TASK_ID" "running"
      if ! run_task_loop; then
        update_task_status "$TASK_ID" "error"
        append_summary "$TASK_ID" "$SUBJECT" "FAILED" "-" "review/verification failure"
        fail "Task $TASK_ID failed review."
      fi
      commit_task
      local ch
      if [[ "$AUTO_COMMIT" == "true" ]]; then
        ch=$(git rev-parse HEAD 2>/dev/null || echo "")
        update_task_status "$TASK_ID" "committed" "$ch"
        log_progress "COMPLETE task $TASK_ID - $SUBJECT ($ch)"
        append_summary "$TASK_ID" "$SUBJECT" "DONE" "$ch" "clean review"
        require_clean_worktree
      else
        update_task_status "$TASK_ID" "complete"
        log_progress "COMPLETE task $TASK_ID - $SUBJECT (no auto-commit)"
        append_summary "$TASK_ID" "$SUBJECT" "DONE" "-" "clean review (manual commit)"
        log "Auto-commit disabled. Commit your changes, then re-run to continue."
        log_learning "Task $TASK_ID completed. Add learnings here if needed."
        exit 0
      fi
      log_learning "Task $TASK_ID completed. Add learnings here if needed."
    done
    log "No more unblocked tasks found. Done."
    exit 0
  fi

  load_task
  log "Task: $TASK_ID - $SUBJECT"
  update_loop_state "starting" "implement" 0 "task selected"
  log_progress "START task $TASK_ID - $SUBJECT"
  run_task_loop
  log_progress "COMPLETE task $TASK_ID - $SUBJECT (no auto-commit)"
  exit 0
}

main "$@"
