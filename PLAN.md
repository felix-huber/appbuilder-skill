# Plan: Strengthen Ralph Loops Based on wasm-sqlite-editor Run Analysis

## Core Insight

**Current (broken):**
```
Task → Fail → Block → Next task → Fail → Block → ... → 17 blocked beads → Batch fix
```

**Target (inline fix):**
```
Task → Fail → Categorize → Auto-fix inline → Re-review → Pass or Block-with-context
```

The fix loop must be **INSIDE** ralph, not a separate cleanup process.

---

## Analysis Summary

### Run Statistics (5h 40min)
- **Completed**: 11 tasks
- **Blocked (failed review)**: 17 tasks
- **Open (waiting on blocked)**: 21 tasks
- **Completion rate**: ~2 tasks/hour with review iterations

### Key Observations

1. **Review is catching real issues** - tasks fail because:
   - Code written but not wired to handlers
   - Tests that don't actually test behavior
   - Unrelated changes mixed into commits
   - Missing E2E coverage

2. **But review feedback is lost** - when task fails:
   - `br update $task_id --status blocked --comment "Failed during Ralph execution"`
   - Actual review findings NOT stored
   - Agent can't retry with feedback

3. **Cascading blocks** - 17 blocked tasks → 21 open tasks can't proceed

4. **Learning capture broke** - after Jan 29, only placeholder "Add learnings here if needed"

5. **Long stalls** - bd-hws took 63 min before failing, no checkpoints

---

## Proposed Improvements

### P0: Critical (Must Have)

#### 1. Store Review Feedback in Beads
**Problem**: Review agent finds issues but feedback is lost.
**Solution**: Capture review output and store as bead comment.

```bash
# In ralph.sh, after review fails:
review_output=$(run_review "$task_id")
if [[ $? -ne 0 ]]; then
  br update "$task_id" --status blocked --comment "Review failed:
$review_output"
fi
```

**Files**: `scripts/ralph.sh`, `scripts/ralph.sh`

#### 2. Retry with Feedback Before Blocking
**Problem**: Tasks block immediately on review failure.
**Solution**: Inject review feedback and retry once before blocking.

```
Iteration 1: Implement → Review fails with feedback
Iteration 2: Re-implement with feedback injected → Review
If fails again → Block with full context
```

**Files**: `scripts/ralph.sh`, `scripts/ralph.sh`

#### 3. Fix Learning Capture
**Problem**: Learnings stopped being captured after Jan 29.
**Solution**: Ensure LEARNING: markers are extracted and appended properly.

**Files**: `scripts/ralph.sh` (get_recent_learnings function)

---

### P1: Important

#### 4. Inline Fix Loop (NOT Batch Cleanup)
**Problem**: Tasks fail and block, accumulating 17 blocked beads for later batch fix.
**Solution**: When review fails, fix **inline during the same task** before moving on.

```
┌─────────────────────────────────────────────────────────────┐
│  INLINE FIX LOOP (inside ralph, per-task)                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Task → Implement → Review                                  │
│                        │                                    │
│                        ├── PASS → Complete, next task       │
│                        │                                    │
│                        └── FAIL → Categorize failure:       │
│                                   │                         │
│     ┌────────────────────────────┼────────────────────────┐│
│     │                            ▼                        ││
│     │  A: UNWIRED_CODE    → Claude quick wire             ││
│     │  B: BAD_TESTS       → Claude rewrite tests          ││
│     │  C: ARCHITECTURE    → Oracle analyze → Claude fix   ││
│     │  D: MISSING_E2E     → Claude write E2E              ││
│     │  E: EDGE_CASE       → Claude focused fix            ││
│     └─────────────────────────────────────────────────────┘│
│                            │                                │
│                            ▼                                │
│                       Re-implement with fix                 │
│                            │                                │
│                            ▼                                │
│                       Re-review                             │
│                            │                                │
│                   PASS ────┴──── FAIL                       │
│                     │              │                        │
│                     ▼              ▼                        │
│                 Complete     Block with full context        │
│                              (after 5 total attempts)       │
└─────────────────────────────────────────────────────────────┘
```

**Failure Categories** (from wasm-sqlite-editor analysis):
| Category | Pattern | Fix Strategy | Model |
|----------|---------|--------------|-------|
| A: UNWIRED_CODE | Code exists, not connected | Wire to handlers | Claude |
| B: BAD_TESTS | Tests don't test behavior | Rewrite tests | Claude |
| C: ARCHITECTURE | Complex, needs understanding | Oracle → Claude | Multi |
| D: MISSING_E2E | No E2E coverage | Write E2E tests | Claude |
| E: EDGE_CASE | Specific edge case missed | Focused fix | Claude |

**Key difference from current approach:**
- Current: block → accumulate → batch fix later
- New: fail → categorize → fix inline → re-review → only block if fix fails

**Files**: `scripts/ralph.sh`, `scripts/ralph.sh`

#### 5. Dependency-Aware Task Prioritization
**Problem**: All tasks treated equally, blockers cascade.
**Solution**: Prioritize tasks that unblock the most other tasks.

```bash
# Count how many tasks depend on each task
# Pick task with highest "unblock count" first
```

**Files**: `scripts/ralph.sh` (get_next_task functions)

#### 6. Stall Detection with Checkpoints
**Problem**: bd-hws ran 63 min before failing, no intermediate saves.
**Solution**: Periodic checkpoints during long tasks.

```bash
# Every 10 min during implementation:
# - Save partial work to stash
# - Log progress marker
# - Check if still making progress
```

**Files**: `scripts/ralph.sh`

---

### P2: Nice to Have

#### 7. Review Issue Categorization
Categorize review failures to enable smarter retry:
- `UNWIRED_CODE` → Healer can likely fix
- `WRONG_LOGIC` → Needs human review
- `MISSING_TEST` → Can auto-generate test

#### 8. (Removed - Batch retry contradicts inline fix approach)

#### 9. Real-time Progress Dashboard
Enhance swarm_status.js with:
- Live iteration progress
- Review pass/fail rate
- Blocker dependency graph

---

## Implementation Order

| Phase | Items | Effort |
|-------|-------|--------|
| Phase 1 | Store feedback, Fix learnings | Small |
| Phase 2 | Council prompts (Oracle/Gemini/Codex/Claude) | Medium |
| Phase 3 | Council loop in ralph.sh + context synthesis | Medium-Large |
| Phase 4 | Dependency prioritization, Stall detection | Medium |
| Phase 5 | Dashboard enhancements | Small |

---

## Success Metrics

After implementing P0+P1:
- **Completion rate**: 3-4 tasks/hour (vs current 2)
- **Block rate**: <30% (vs current ~60%)
- **Learnings captured**: 100% of completed tasks
- **Review feedback retention**: 100%

---

## Full Fix Loop Design (Smart, Speed-Aware, Confidence-Driven)

**Model Characteristics:**
| Model | Speed | Context Window | Best For |
|-------|-------|----------------|----------|
| Claude | Fast | 200K | Implementation, synthesis |
| Gemini | Fast | 1M+ | Long context analysis, alternatives |
| Codex | Fast | 128K | Surgical patches |
| Oracle (GPT-5.2) | Slow | 128K | Deep reasoning, root cause (use strategically) |

**Key Insights:**
- Don't call Oracle every round - it's slow. Call when confidence is LOW.
- Gemini has 1M+ context - feed it FULL source files, not just diffs
- Always ask for **confidence score** (0-100) - drives escalation
- Use **smart context tool** to gather relevant source for long-context models

### Smart Loop Structure (Confidence-Driven)

```
┌─────────────────────────────────────────────────────────────────┐
│  ATTEMPT 1: Claude Implements (fast)                            │
│  → Review                                                       │
│  → PASS? Done. FAIL? Continue...                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓ fails
┌─────────────────────────────────────────────────────────────────┐
│  ATTEMPT 2: Fast Dual Analysis (Claude + Gemini parallel)       │
│                                                                 │
│  ┌────────────────────┐  ┌────────────────────┐                │
│  │ CLAUDE (fast)      │  │ GEMINI (fast, 1M)  │                │
│  │ - Retry with       │  │ - Full source ctx  │                │
│  │   feedback         │  │ - Alternatives     │                │
│  │ - Confidence: ??%  │  │ - Confidence: ??%  │                │
│  └─────────┬──────────┘  └─────────┬──────────┘                │
│            └──────────┬────────────┘                            │
│                       ↓                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ IF both confidence >= 70%                               │   │
│  │   → Pick higher confidence, implement, review           │   │
│  │                                                         │   │
│  │ IF either confidence < 70%                              │   │
│  │   → ESCALATE TO ORACLE immediately (don't waste time)   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓ fails or low confidence
┌─────────────────────────────────────────────────────────────────┐
│  ATTEMPT 3: Oracle Deep Analysis (slow but wise)                │
│                                                                 │
│  Context for Oracle:                                            │
│  - Task + acceptance criteria                                   │
│  - ALL relevant source files (use smart context tool)           │
│  - All previous attempts and failures                           │
│  - Claude's and Gemini's analyses                               │
│                                                                 │
│  Oracle outputs:                                                │
│  - Root cause (THE real issue)                                  │
│  - Confidence: ??%                                              │
│  - Specific fix recommendation                                  │
│                                                                 │
│  → Codex generates patch based on Oracle's analysis             │
│  → Claude implements and verifies                               │
│  → Review                                                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓ fails
┌─────────────────────────────────────────────────────────────────┐
│  ATTEMPT 4: Full Council (Oracle insight + all models)          │
│                                                                 │
│  Now we have Oracle's root cause. All models work from it:      │
│                                                                 │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐                           │
│  │ GEMINI  │ │ CODEX   │ │ CLAUDE  │  (parallel, fast)         │
│  │ Alt.    │ │ Patch   │ │ Impl.   │                           │
│  └────┬────┘ └────┬────┘ └────┬────┘                           │
│       └──────────┬────────────┘                                 │
│                  ↓                                              │
│  Claude synthesizes best approach, implements                   │
│  → Review                                                       │
│  → Capture learnings                                            │
└─────────────────────────────────────────────────────────────────┘
                              ↓ fails
┌─────────────────────────────────────────────────────────────────┐
│  ATTEMPT 5: Oracle Re-analysis + Final Council                  │
│                                                                 │
│  Oracle re-analyzes with ALL accumulated context:               │
│  - Why did Attempt 4 fail given my previous analysis?           │
│  - What did I miss?                                             │
│  - Updated root cause                                           │
│                                                                 │
│  → Full council with updated analysis                           │
│  → PASS? Done. FAIL? Block with full context                    │
└─────────────────────────────────────────────────────────────────┘
                              ↓ fails
┌─────────────────────────────────────────────────────────────────┐
│  BLOCK with Full Context                                        │
│                                                                 │
│  - 5 attempts with all feedback                                 │
│  - 2 Oracle deep analyses                                       │
│  - All Gemini alternatives                                      │
│  - Confidence scores from each attempt                          │
│  - Clear recommendation for human                               │
└─────────────────────────────────────────────────────────────────┘
```

### Smart Context Tool (For Long-Context Models)

```bash
# gather_task_context.sh
# Provides rich context for Gemini (1M) and Oracle

gather_task_context() {
  local task_id="$1"
  local task_files="$2"  # files mentioned in task

  # 1. Direct files from task
  for f in $task_files; do
    echo "=== FILE: $f ==="
    cat "$f"
  done

  # 2. Import chain (what these files import)
  for f in $task_files; do
    grep -h "^import\|^from" "$f" 2>/dev/null | \
      extract_paths | \
      while read imported; do
        echo "=== IMPORTED: $imported ==="
        cat "$imported" 2>/dev/null
      done
  done

  # 3. Files that import these (dependents)
  for f in $task_files; do
    grep -rl "$(basename $f .ts)" src/ 2>/dev/null | \
      head -5 | \
      while read dependent; do
        echo "=== DEPENDENT: $dependent ==="
        cat "$dependent"
      done
  done

  # 4. Related test files
  for f in $task_files; do
    test_file="${f%.ts}.test.ts"
    if [[ -f "$test_file" ]]; then
      echo "=== TEST: $test_file ==="
      cat "$test_file"
    fi
  done

  # 5. Similar patterns in codebase (for reference)
  # Use grep to find similar code patterns
}
```

### Confidence Score Requirement

Every model MUST output a confidence score:

```markdown
## Your Analysis

[analysis here]

## Confidence: XX%

**Why this confidence level:**
- [reason 1]
- [reason 2]

**What would increase confidence:**
- [if we knew X, confidence would be higher]
```

### Escalation Rules

```
Confidence >= 80%  → Proceed with this approach
Confidence 60-79%  → Proceed but flag for extra review scrutiny
Confidence 40-59%  → Escalate to Oracle before implementing
Confidence < 40%   → Escalate to Oracle, pause implementation
```

---

## CRITICAL: Context Evolution (Don't Repeat Same Prompt)

**The loop MUST evolve. Never run the same prompt with same context twice.**

### The "If We Knew X" Pattern

Every model outputs what would increase their confidence:
```markdown
**What would increase confidence:**
- If we knew how the worker handles this message type
- If we saw the test that's failing
- If we understood the state machine transitions
```

**The next iteration MUST address these:**

```
┌─────────────────────────────────────────────────────────────────┐
│  ITERATION N: Model says "if we knew X, Y, Z"                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  BEFORE ITERATION N+1: Context Gatherer Agent                   │
│                                                                 │
│  For each "if we knew X":                                       │
│    → Search codebase for X                                      │
│    → Read relevant files                                        │
│    → Summarize findings                                         │
│    → Add to context for N+1                                     │
│                                                                 │
│  Example:                                                       │
│  "If we knew how worker handles this message type"              │
│    → grep for message type in worker/                           │
│    → Read worker/index.ts, find handler                         │
│    → Add handler code to context                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  ITERATION N+1: New context with X, Y, Z answered               │
│                                                                 │
│  Prompt now includes:                                           │
│  "Previously you asked about X. Here's what we found: ..."      │
└─────────────────────────────────────────────────────────────────┘
```

### Context Gatherer Agent

Spawned between iterations to fill knowledge gaps:

```bash
gather_missing_context() {
  local questions="$1"  # from "what would increase confidence"
  local output_file=$(mktemp)

  # Parse each question (use process substitution to avoid subshell)
  while IFS= read -r question; do
    case "$question" in
      *"worker"*"message"*|*"handler"*)
        echo "### Worker Message Handlers" >> "$output_file"
        grep -r "onmessage\|postMessage" src/worker/ >> "$output_file" 2>/dev/null
        ;;
      *"test"*"failing"*)
        echo "### Failing Test" >> "$output_file"
        npm test 2>&1 | tail -50 >> "$output_file"
        ;;
      *"state"*|*"transitions"*)
        echo "### State Definitions" >> "$output_file"
        grep -r "useState\|createStore\|state:" src/ >> "$output_file" 2>/dev/null
        ;;
      *)
        # Generic search for keywords in the question
        local keywords=$(echo "$question" | tr -cs '[:alnum:]' ' ' | xargs)
        echo "### Search: $keywords" >> "$output_file"
        grep -ri "$keywords" src/ 2>/dev/null | head -20 >> "$output_file"
        ;;
    esac
  done <<< "$questions"

  cat "$output_file"
  rm -f "$output_file"
}
```

### Evolving Prompt Structure

Each iteration's prompt includes:

```markdown
## Iteration {{N}}

### What Changed Since Last Iteration

**Questions You Asked (Iteration {{N-1}}):**
{{previous_questions}}

**Answers Found:**
{{#each answers}}
**Q: {{question}}**
**A:**
```
{{answer_code}}
```
{{/each}}

### New Context Added
{{new_context}}

### Previous Attempt Summary
- Approach: {{previous_approach}}
- Result: {{previous_result}}
- Why it failed: {{failure_reason}}

### Your Task This Iteration
Don't repeat what was tried. Use the new information.
```

### Test-Driven Evolution

**Ultimate goal: tests green**

After each implementation attempt:
```bash
# Run tests, capture output
test_output=$(npm test 2>&1)
test_exit=$?

if [[ $test_exit -ne 0 ]]; then
  # Extract failing test info
  failing_tests=$(echo "$test_output" | grep -A5 "FAIL\|Error\|✗")

  # This becomes context for next iteration
  echo "### Failing Tests"
  echo "$failing_tests"
  echo ""
  echo "### Full Test Output"
  echo "$test_output" | tail -100
fi
```

This test output becomes PRIMARY context for next iteration - not just "it failed" but "here's exactly what's failing and why".

### Context Accumulation Between Rounds

After each council round, synthesize:

```markdown
## Council Round N Summary

### Approaches Tried
- [specific approaches attempted]

### Failures & Why
- [what failed and root cause]

### Oracle's Analysis
- [deep reasoning on why]

### Gemini's Unused Ideas
- [alternatives not yet tried - for next round]

### Key Learnings
- [insights gained]

### Recommended Next Step
- [what R(N+1) should try differently]
```

This summary gets **prepended** to the next round's context.

---

## Model-Specific Prompts (Optimized for Each Model's Strengths)

### Oracle (GPT-5.2) - Deep Reasoning, Called Strategically

**When to call Oracle:** Confidence < 60% from fast models, or after 2 failed attempts.

```markdown
# ORACLE: Deep Root Cause Analysis

You are the Oracle, the wisest reasoner. You are called when the fast models
are stuck. Your job is to find the TRUE ROOT CAUSE that others missed.

## Full Context (we give you everything)

### Task Requirements
{{task_description}}
{{acceptance_criteria}}

### All Previous Attempts
{{#each attempts}}
**Attempt {{@index}}:**
- Approach: {{approach}}
- Result: {{result}}
- Review Feedback: {{feedback}}
- Confidence at time: {{confidence}}%
{{/each}}

### Source Code (Full Files)
{{#each source_files}}
=== {{path}} ===
{{content}}
{{/each}}

### Import Chain
{{import_chain}}

## Your Mission

You have time. Think deeply. The fast models missed something.

1. **What pattern did they miss?** - Read the source carefully
2. **Why do the fixes keep failing?** - What's the recurring gap?
3. **What's the REAL root cause?** - Not symptoms, the cause
4. **What would definitely work?** - Be specific

## Output Format

### Root Cause (One Sentence)
[THE core issue in one clear sentence]

### Evidence From Source Code
```
[quote specific lines that prove this]
```

### Why Previous Attempts Failed
| Attempt | What They Tried | Why It Failed |
|---------|-----------------|---------------|
{{#each attempts}}
| {{@index}} | {{approach}} | {{why_failed}} |
{{/each}}

### The Fix (Specific)
[Exactly what needs to change, in which files, why]

### Confidence: XX%

**Why this confidence level:**
- [evidence 1]
- [evidence 2]

**What could still go wrong:**
- [risk 1]
```

---

### Gemini - Long Context Analysis (1M+ tokens)

**Strengths:** Can see ENTIRE codebase. Use for pattern finding and alternatives.

```markdown
# GEMINI: Full Codebase Analysis + Alternatives

You have access to the FULL source code. Use your 1M+ context to see patterns
that others miss.

## Full Source Context

### Direct Files (Task Mentions These)
{{#each task_files}}
=== {{path}} ({{lines}} lines) ===
{{content}}
{{/each}}

### Files That Import These (Dependents)
{{#each dependents}}
=== {{path}} ===
{{content}}
{{/each}}

### Similar Patterns in Codebase (For Reference)
{{#each similar_patterns}}
=== {{path}} - Similar to task ===
{{content}}
{{/each}}

### Test Files
{{#each test_files}}
=== {{path}} ===
{{content}}
{{/each}}

## Task
{{task_description}}

## Failed Approaches (Don't Repeat These)
{{#each failed_approaches}}
- {{approach}}: Failed because {{reason}}
{{/each}}

## Your Mission

1. **Search the full context** - What patterns exist that could help?
2. **Find similar solved problems** - How were they handled?
3. **Propose 3 alternatives** - DIFFERENT from what was tried
4. **Rank by confidence** - Which is most likely to work?

## Output Format

### Patterns Found in Codebase
[relevant patterns you noticed that could help]

### Alternative 1 (Highest Confidence)
**Approach**: [description]
**Similar Pattern Found At**: [file:line]
**Implementation**: [specific steps]
**Confidence: XX%**

### Alternative 2
[same format]

### Alternative 3
[same format]

### What Definitely Won't Work
[approaches to avoid and why]

### Overall Confidence: XX%

**What would increase confidence:**
- [if we knew X]
- [if we had Y]
```

---

### Codex - Fast Surgical Patches

**Strengths:** Fast, precise, good at targeted changes. Give minimal context.

```markdown
# CODEX: Surgical Patch

Generate a MINIMAL patch. No refactoring. Just fix the issue.

## The Problem
{{root_cause}}

## Files to Modify
{{#each files_to_modify}}
=== {{path}} ===
{{content}}
{{/each}}

## What To Do
{{fix_instruction}}

## Output Format

### Patch
```diff
{{generate_patch}}
```

### Verification
```bash
{{verification_command}}
```

### Confidence: XX%
```

---

### Claude (Synthesizer) - Fast Implementation

**Strengths:** Fast, good at synthesis, reliable implementation.

```markdown
# CLAUDE: Synthesize and Implement

You have input from the council. Pick the best approach and IMPLEMENT it.

## Council Input

### Oracle's Root Cause (if available)
{{oracle_analysis}}
Confidence: {{oracle_confidence}}%

### Gemini's Alternatives
{{#each gemini_alternatives}}
**Option {{@index}}**: {{approach}}
Confidence: {{confidence}}%
{{/each}}

### Codex's Patch (if available)
```diff
{{codex_patch}}
```
Confidence: {{codex_confidence}}%

## Your Decision

Pick the approach with highest confidence that addresses the root cause.

If confidences are close, prefer:
1. Codex patch (if surgical and correct)
2. Gemini alternative (if novel approach)
3. Oracle's recommendation (if deep insight)

## Output Format

### Chosen Approach
[which and why]

### My Confidence in This Choice: XX%

### Implementation
[actual code - complete, not partial]

### Verification
```bash
{{run_verification}}
```

### If This Fails, Try Next:
[backup plan for next round]
```

---

## Synthesis Between Rounds

After each round, generate:

```markdown
# Council Round {{N}} Synthesis

## What Was Tried
{{chosen_approach}}

## Result
{{pass_or_fail}}

## If Failed, Why
{{failure_reason}}

## Oracle's Updated Analysis
{{oracle_refinement}}

## Untried Alternatives
{{gemini_unused_ideas}}

## Key Insight Gained
{{learning}}

## Recommendation for Round {{N+1}}
{{next_step}}
```

This becomes part of the context for the next round, ensuring learnings compound.

---

## Decisions Made

| Question | Decision |
|----------|----------|
| Retry-with-feedback | **DEFAULT** (always on) |
| Multi-model council | **AUTOMATIC** (no flag) |
| Attempts before block | **5 total** (see smart loop) |
| Oracle usage | **STRATEGIC** - only when confidence < 60% or after 2 fails |
| Gemini context | **FULL SOURCE** - leverage 1M+ context window |
| Confidence scoring | **MANDATORY** - every model outputs 0-100% |
| Escalation | **CONFIDENCE-DRIVEN** - low confidence → Oracle |

### Model Call Patterns

| Scenario | Models Called | Rationale |
|----------|---------------|-----------|
| Attempt 1 fails, Claude confident | Claude retry only | Fast, likely to work |
| Attempt 2 fails, both confident | Claude+Gemini parallel | Two fast perspectives |
| Either confidence < 60% | Escalate to Oracle | Need deep analysis |
| Oracle analyzed, still failing | Full council | All perspectives |

### Context Strategy

| Model | Context Given |
|-------|---------------|
| Oracle | Full source files, all attempts, all feedback |
| Gemini | Full codebase (1M), similar patterns, all tests |
| Codex | Minimal - just files to change + instruction |
| Claude | Synthesized council output + implementation focus |

### Model Invocation (How to Call Each Model)

```bash
# Claude (default - already available)
claude --print "$prompt" > output.md

# Oracle (GPT-5.2 via API or browser automation)
# Option A: API call
curl -X POST "https://api.openai.com/v1/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model": "gpt-5.2", "messages": [{"role": "user", "content": "'"$prompt"'"}]}'

# Option B: Browser automation (oracle_converge.sh pattern)
./scripts/oracle_converge.sh council "$prompt_file" "$context_file"

# Gemini (via API)
curl -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent" \
  -H "x-goog-api-key: $GEMINI_API_KEY" \
  -d '{"contents": [{"parts": [{"text": "'"$prompt"'"}]}]}'

# Codex (via OpenAI API or GitHub Copilot CLI)
# Using OpenAI API with code-focused model
curl -X POST "https://api.openai.com/v1/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{"model": "gpt-4-turbo", "messages": [{"role": "user", "content": "'"$prompt"'"}]}'
```

**Wrapper function for ralph.sh:**

```bash
call_model() {
  local model="$1"
  local prompt_file="$2"
  local output_file="$3"

  case "$model" in
    claude)
      claude --print "$(cat "$prompt_file")" > "$output_file"
      ;;
    oracle)
      # Use oracle_converge.sh or direct API
      ./scripts/oracle_converge.sh council "$prompt_file" > "$output_file"
      ;;
    gemini)
      # API call with full context (1M window)
      call_gemini_api "$prompt_file" > "$output_file"
      ;;
    codex)
      # Focused code generation
      call_codex_api "$prompt_file" > "$output_file"
      ;;
  esac
}
```

## Next Steps

1. [ ] Create `scripts/gather_task_context.sh` - smart context collection
2. [ ] Create `scripts/gather_missing_context.sh` - answers "if we knew X" questions
3. [ ] Create `prompts/ralph/council/` directory with model-specific prompts
4. [ ] Add confidence-driven loop to `scripts/ralph.sh`
5. [ ] Add context evolution logic (each iteration gets NEW info)
6. [ ] Add test output capture (failing tests become primary context)
7. [ ] Test on one blocked bead from wasm-sqlite-editor
8. [ ] Iterate on prompts based on results

## Files to Create/Modify

| File | Purpose |
|------|---------|
| `scripts/ralph.sh` | Main loop with confidence-driven escalation |
| `scripts/gather_task_context.sh` | Collect full context for long-context models |
| `scripts/gather_missing_context.sh` | Answer "if we knew X" between iterations |
| `prompts/ralph/council/oracle.md` | Oracle deep analysis (strategic use) |
| `prompts/ralph/council/gemini.md` | Gemini full-context alternatives |
| `prompts/ralph/council/codex.md` | Codex surgical patch |
| `prompts/ralph/council/synthesizer.md` | Claude synthesis + implementation |
| `prompts/ralph/council/context_gatherer.md` | Agent that fills knowledge gaps |
