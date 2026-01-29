# Post-Mortem: wasm-sqlite-editor Ralph Execution Failure

## Executive Summary

The app produced by Ralph doesn't work because **it doesn't even compile**. TypeScript errors prevent the build from succeeding, meaning:
1. E2E tests couldn't have tested real functionality
2. Ralph marked tasks as "complete" without verifying the build worked
3. The app never ran in a browser during execution

---

## Root Cause Analysis

### Critical Finding #1: Build is Completely Broken

```bash
$ npm run build

src/App.tsx(217,5): error TS2353: Object literal may only specify known properties, and 'onNewDatabase' does not exist in type 'KeyboardShortcut[]'.
src/App.tsx(295,49): error TS2741: Property 'onFreeSpaceClick' is missing in type '{}' but required in type 'StorageFullBannerProps'.
src/App.tsx(296,43): error TS2741: Property 'onDetailsClick' is missing in type '{}' but required in type 'PersistenceErrorBannerProps'.
src/App.tsx(410,11): error TS2322: Type '{ isOpen: true; title: string; message: string; confirmLabel: string; onConfirm: () => void; onCancel: () => void; variant: string; }' is not assignable to type 'IntrinsicAttributes & ConfirmDialogProps'.
  Property 'variant' does not exist on type 'IntrinsicAttributes & ConfirmDialogProps'.
src/worker/index.ts(243,23): error TS2322: Type 'RegistryEntry[]' is not assignable to type 'DatabaseEntry[]'.
```

**What happened:**
- Task A created `StorageFullBanner` with required prop `onFreeSpaceClick`
- Task B used `StorageFullBanner` in `App.tsx` without passing that prop
- The two tasks had no awareness of each other's interfaces
- Ralph marked both tasks as "complete" without running a build

### Critical Finding #2: Logs Reveal Nothing

The task logs are almost empty:

```
=== Task: bd-14y ===
=== Tool: claude ===
=== Started: 2026-01-29T03:15:33+01:00 ===

<promise>TASK_COMPLETE</promise>

=== Finished: 2026-01-29T03:20:38+01:00 ===
```

**What's missing:**
- No output from the agent showing what it did
- No verification that verification commands passed
- No build output
- No test output

### Critical Finding #3: Smoke Tests Are Too Weak

```typescript
// e2e/smoke.spec.ts
test('app loads without console errors', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/SQLite Editor/);
  // ...check for console errors
});
```

This test:
- Only checks the page title
- Only checks console errors
- Doesn't verify the app actually renders
- Doesn't verify any functionality

### Critical Finding #4: No Build/Typecheck in Verification

Looking at the task graph, verification commands are weak:

```json
{
  "verification": [
    "`npm run dev` starts; browser shows \"SQLite Editor\" heading"
  ]
}
```

But:
- `npm run dev` doesn't catch TypeScript errors (Vite is lenient)
- "browser shows heading" is manual, not automated
- No `npm run build` or `npm run typecheck` required

### Critical Finding #5: Progress.txt Stopped Updating

The progress file shows iterations 1-12, then blank, suggesting:
- Ralph process continued but logging stopped
- Or iterations completed but didn't append to file
- No evidence of what happened after iteration 12

---

## Why E2E Tests "Passed"

The E2E tests show 508 tests. Looking at the test run:
- All accessibility tests FAILED (expected - broken build)
- DB lifecycle tests PASSED (testing mocked functionality)
- ERD tests PASSED (testing configuration objects, not actual UI)

**Key insight:** Many tests test "configuration" objects or mock data, not actual running app functionality. They pass because they don't require the app to build/run.

---

## Problems with the AppBuilder Workflow

### Problem 1: No Mandatory Build Verification

Ralph should run after each task:
```bash
npm run build && npm run typecheck
```

If these fail, the task is NOT complete.

### Problem 2: Tasks Don't Know About Each Other

When Task A creates:
```typescript
export interface StorageFullBannerProps {
  onFreeSpaceClick: () => void;  // Required!
}
```

And Task B uses:
```typescript
<StorageFullBanner />  // Missing prop!
```

There's no mechanism to catch this.

**Solution needed:** Integration verification tasks that run after groups of related tasks.

### Problem 3: Fresh Eyes Review Doesn't Actually Run Build

The `--fresh-eyes` flag runs a review prompt, but doesn't run:
- `npm run build`
- `npm run typecheck`
- Actual test suites

It's a "thinking" review, not a "running" review.

### Problem 4: Task Logs Are Suppressed

The `run_with_tool` function in ralph.sh pipes output but the logs only contain TASK_COMPLETE. The actual work output is lost.

### Problem 5: Verification Commands Are Suggestions, Not Requirements

Tasks have verification like:
```
- `npm run test` passes
```

But Ralph doesn't actually run these. It relies on the agent to run them and report success.

### Problem 6: Oracle Review Didn't Catch Interface Mismatches

The Oracle review for the plan didn't check for:
- Cross-task interface consistency
- Component prop compatibility
- Integration points

---

## Recommendations for AppBuilder Improvement

### 1. Add Mandatory Build Verification in Ralph

```bash
# In ralph.sh, after task completion:
if echo "$OUTPUT" | grep -q "<promise>TASK_COMPLETE</promise>"; then
  # Verify build before marking complete
  log_info "Verifying build..."
  if ! npm run build --if-present 2>&1; then
    log_error "Build failed - task not complete"
    mark_task_failed "$task_id"
    continue
  fi
  if ! npm run typecheck --if-present 2>&1; then
    log_error "Typecheck failed - task not complete"
    mark_task_failed "$task_id"
    continue
  fi
  mark_task_completed "$task_id"
fi
```

### 2. Add Integration Verification Tasks

After each sprint of related tasks, add an integration task:

```markdown
## S3-INTEGRATION: Verify Sprint 3 Integration

**Verification:**
- [ ] `npm run build` passes
- [ ] `npm run typecheck` passes
- [ ] `npm run test` passes
- [ ] App loads in browser without errors
- [ ] All new components render correctly
```

### 3. Strengthen Smoke Tests

```typescript
// e2e/smoke.spec.ts should verify:
test('app builds and renders core UI', async ({ page }) => {
  await page.goto('/');

  // Verify no React error boundaries triggered
  await expect(page.locator('[data-error-boundary]')).toHaveCount(0);

  // Verify main layout renders
  await expect(page.locator('header')).toBeVisible();
  await expect(page.locator('main')).toBeVisible();

  // Verify no hydration errors
  const hydrationErrors = page.locator('[data-hydration-error]');
  await expect(hydrationErrors).toHaveCount(0);
});
```

### 4. Capture Full Task Output

In ralph.sh, log ALL output:

```bash
run_with_tool() {
  local tool="$1"
  local prompt="$2"
  local log_file="$LOGS_DIR/${CURRENT_TASK_ID}.log"

  # Capture FULL output, not just TASK_COMPLETE
  case "$tool" in
    claude)
      $claude_cmd "$prompt" 2>&1 | tee "$log_file"
      ;;
  esac
}
```

### 5. Add Interface Consistency Checks to Oracle Review

Add to the plan review lenses:

```
## Interface Consistency Check

For each component that exposes a public interface:
1. List all files that import/use this component
2. Verify all required props are passed
3. Flag any TypeScript mismatches
```

### 6. Run Actual Tests, Not Just "Trust"

Ralph should run verification commands itself:

```bash
# In task prompt:
## Verification (MANDATORY - I will verify these myself)
- npm run typecheck  # Will be run by orchestrator
- npm run build      # Will be run by orchestrator
- npm run test       # Will be run by orchestrator

DO NOT output TASK_COMPLETE until you have run these commands
and they all pass.
```

### 7. Add "Sanity Check" After Each Task

Before marking complete:
```bash
# Quick sanity check
git diff --stat HEAD~1  # Show what changed
npm run build 2>&1 | tail -20  # Verify build
```

### 8. Better Bead Dependencies

Tasks that use a component should explicitly depend on the task that creates it:

```
bd-xyz: Use StorageFullBanner in App.tsx
  deps: [bd-abc: Create StorageFullBanner component]
```

This forces the interface to be stable before usage.

---

## Action Items for AppBuilder-Skill

| Priority | Action | File(s) to modify |
|----------|--------|-------------------|
| P0 | Add mandatory `npm run build` after task completion | scripts/ralph.sh |
| P0 | Add mandatory `npm run typecheck` after task completion | scripts/ralph.sh |
| P1 | Capture full agent output in logs | scripts/ralph.sh |
| P1 | Add integration verification tasks to plan template | templates/PLAN.template.md |
| P1 | Strengthen smoke test requirements | prompts/plan/*.txt |
| P2 | Add interface consistency check to Oracle lenses | prompts/code/architecture.txt |
| P2 | Add explicit component dependencies in beads | scripts/generate_beads_setup.js |
| P3 | Add real-time build status to swarm status | scripts/swarm_status.js |

---

## Specific Code Changes

### ralph.sh - Add Build Verification

```bash
# After line ~1383 (task completion check)
verify_build() {
  local project_root="$1"

  # Check if this is a Node project
  if [[ -f "$project_root/package.json" ]]; then
    log_info "Running build verification..."

    # Try typecheck first (faster)
    if npm run typecheck --if-present 2>&1; then
      log_success "Typecheck passed"
    else
      log_error "Typecheck FAILED"
      return 1
    fi

    # Then full build
    if npm run build --if-present 2>&1; then
      log_success "Build passed"
    else
      log_error "Build FAILED"
      return 1
    fi
  fi

  return 0
}

# Use in main loop:
if echo "$OUTPUT" | grep -q "<promise>TASK_COMPLETE</promise>"; then
  if ! verify_build "$PROJECT_ROOT"; then
    log_error "Build verification failed - task incomplete"
    mark_task_failed "$task_id"
    # Add to learnings
    echo "FAILED_BUILD: $task_id at $(date -Iseconds)" >> "$LEARNINGS_FILE"
    continue
  fi
  mark_task_completed "$task_id"
fi
```

### templates/PLAN.template.md - Add Integration Tasks

```markdown
## Sprint Structure

Each sprint MUST end with an integration verification task:

### Sprint N Tasks
- S{N}-T1: Feature A
- S{N}-T2: Feature B
- S{N}-INT: **Integration Verification** (depends on all S{N} tasks)
  - Verification:
    - [ ] `npm run build` passes
    - [ ] `npm run typecheck` passes
    - [ ] `npm run test` passes
    - [ ] Smoke test passes: `npm run test:e2e -- --grep smoke`
```

---

## Summary

The wasm-sqlite-editor failure was not a single point failure but a **systemic workflow issue**:

1. No build verification = broken code marked as complete
2. Weak tests = false confidence
3. Siloed tasks = integration failures
4. Missing logs = no forensics possible

**The fix is not to patch the app, but to improve the workflow so this can't happen again.**

---

## Changes Implemented

### 1. ralph.sh - Mandatory Build Verification

Added `verify_build()` function that:
- Runs `npm run typecheck` (if available)
- Runs `npm run build` (if available)
- Logs full output to `$LOGS_DIR/${task_id}-build.log`
- **Fails the task if build fails** (even if agent said TASK_COMPLETE)
- Tracks consecutive build failures

New flags:
- `--verify-build` / `--no-verify-build`
- `--verify-typecheck` / `--no-verify-typecheck`

### 2. ralph.sh - Updated Task Prompt

The prompt now includes a **MANDATORY BUILD VERIFICATION** section that:
- Tells agents to run `npm run typecheck` and `npm run build`
- Warns that the orchestrator will verify and fail tasks that don't compile
- Lists common issues (missing props, type mismatches, etc.)

### 3. ralph.sh - Improved Logging

All outcomes now logged to progress.txt:
- Task completed + build verified
- Task failed (build verification)
- Task failed (agent said TASK_FAILED)
- No completion signal (will retry)
- Session summary (on completion or max iterations)

### 4. PLAN.template.md - Integration Tasks

Added mandatory integration verification task template:
- Every sprint must end with an integration task
- Runs full build, typecheck, and tests
- Catches cross-task issues

### 5. PLAN.template.md - Build Verification Section

Added explicit build verification requirements to the verification plan.

### 6. ralph.sh - Lint Verification

Added lint verification to the build check:
- Runs `npm run lint` before typecheck/build
- Fails task if lint has errors (not just warnings)
- New flag: `--no-verify-lint` to disable

### 7. ralph.sh - Anti-Pattern Detection

Added automatic detection of suspicious changes:
- Detects when lint rules are disabled (`'off'` added to eslint config)
- Detects when `max-warnings` is increased in package.json
- Detects when TypeScript config is weakened (`skipLibCheck: true`, etc.)
- Logs warnings and flags these changes for review

### 8. ralph.sh - Forbidden Anti-Patterns in Prompt

Updated task prompt to explicitly forbid:
- Disabling lint rules
- Increasing max-warnings
- Weakening TypeScript config
- Modifying tests to skip/mock failures

### 9. PLAN.template.md - Forbidden Anti-Patterns

Added "Forbidden Anti-Patterns" section to the plan template so it's included in every project's plan.

### 10. docs/AGENT_EVALUATION.md - Agent Evaluation Best Practices

New documentation covering:
- Key differences between agent evals and LLM evals
- Handling non-determinism (pass@k vs pass^k metrics)
- Three types of graders (code-based, model-based, human)
- Best practices from Anthropic's agent evaluation research
- Council of Subagents pattern (Analyst, Sentinel, Healer)
- Promptfoo-style YAML configuration examples

### 11. docs/WORKER_CLIENT_PATTERNS.md - Worker Communication Patterns

New documentation for apps using Web Workers:
- Correlation ID pattern for request-response messages
- Distinguishing broadcasts from responses
- Worker initialization handshake
- Progress and status message handling
- TypeScript interface templates
- Testing strategies (unit, integration, e2e)

### 12. ralph.sh - Council of Subagents Review

Added multi-agent verification pattern (`--council-review` flag):
- **Analyst**: Reviews code quality, correctness, architecture
- **Sentinel**: Detects anti-patterns, shortcuts, security issues
- **Healer**: Fixes issues found by Analyst/Sentinel
- Re-runs build verification after healer fixes

### 13. PLAN.template.md - Async Communication Testing

Added section for apps using Workers/IPC:
- Required test coverage for correlation ID matching
- Mandatory patterns checklist
- Link to WORKER_CLIENT_PATTERNS.md

### 14. PLAN.template.md - Test Quality Requirements

Added guidance on agent evaluation:
- Prefer deterministic tests (build, typecheck, schema validation)
- Use outcome-based tests (grade results, not paths)
- Avoid over-mocking that hides real issues

### 15. TDD Discipline Added Throughout

Updated all new documentation to emphasize TDD workflow:
- **AGENT_EVALUATION.md**: Added "TDD for Agent-Built Code" section explaining why TDD matters more for agents, test pyramid, and task prompt format
- **WORKER_CLIENT_PATTERNS.md**: Added TDD guidance in testing section, emphasizing that tests define contracts upfront
- **PLAN.template.md**: Added mandatory TDD discipline to Test Quality Requirements

Key principle: Agents must write failing tests FIRST, verify failure is for the right reason, then implement.

### 16. Learning Injection into Task Prompts

Improved how learnings compound across iterations:
- **Before**: Agents told to "read progress.txt" (often forgotten)
- **After**: Learnings INJECTED directly into task prompt

New functions in ralph.sh:
- `get_recent_learnings()` - Extracts ALL learnings from current session (see #18)
- `get_recent_progress()` - Extracts last N lines from progress.txt

Task prompt now includes:
```
## Context from This Build Session

### Learnings (all from this session)
These are ALL learnings captured during this Ralph run - even early ones may be relevant.

[ALL learnings from current session automatically injected]

### Recent Progress
[Last 15 lines of progress automatically injected]
```

This ensures learnings are always seen without relying on agents to read files.

**Key improvement**: Changed from "last 3 learnings" to "all session learnings" because
early learnings from task 1 might be relevant to task 20 in the same build session.
The session start line is tracked at Ralph startup, so only learnings from THIS run
are injected (not stale learnings from previous days/runs).

### 17. README.md - Post-Build Evolution Section

Added comprehensive section on knowledge compounding:
- How learning injection works during build
- Nightly compound learning pattern for post-build evolution
- Links to compound-engineering and compound-product repos

### 18. Session-Scoped Learning Injection

Changed from "last 3 learnings" to "all session learnings":

**Before**: `get_recent_learnings(3)` - arbitrary limit, early learnings lost
**After**: `SESSION_LEARNINGS_START_LINE` tracked at Ralph startup

New behavior:
- At Ralph start, record current line count of learnings.md
- `get_recent_learnings()` returns only lines added SINCE session start
- All learnings from tasks 1, 2, 3... are visible to task N
- Safeguard: max 200 lines to prevent prompt explosion
- Stale learnings from previous runs are excluded
