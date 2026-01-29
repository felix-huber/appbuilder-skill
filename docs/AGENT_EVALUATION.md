# Agent Evaluation Best Practices

Based on learnings from Anthropic's agent evaluation research and real-world failures.

## Core Principle: Agent Evals ≠ LLM Evals

Traditional LLM evaluations focus on single-turn text quality (fluency, similarity). Agent evaluations must measure whether the system **functions as intended**:

- Does it complete tasks?
- Does it use tools correctly?
- Does it retain context across turns?
- Does it stay aligned with its role?

## Key Differences from LLM Evals

| Aspect | LLM Evals | Agent Evals |
|--------|-----------|-------------|
| Focus | Final output quality | Full trajectory + outcomes |
| Scope | Single turn | Multi-turn, stateful |
| Tools | N/A | Must verify correct usage |
| Errors | Isolated | Compound across turns |
| Grading | Text comparison | Outcome verification |

## Handling Non-Determinism

### The Problem

LLMs generate probabilistic outputs. The same input can produce different responses, different execution paths, and different tool calls each time.

**Non-determinism compounds in agents**: If step 1 has 90% accuracy and step 2 has 90% accuracy, the combined accuracy is only 81%. With 5 steps, you're down to 59%.

### Metrics for Variable Outcomes

- **pass@k**: Probability of at least one success in k attempts
  - Use when one success is sufficient (developer tools, exploratory agents)
  - Example: 50% pass@1 means succeeds half the time on first try

- **pass^k**: Probability that ALL k trials succeed
  - Use when consistency matters (customer-facing agents)
  - Example: 75% per-trial with 3 trials = only 42% pass^k

### Strategies

1. **Run multiple trials** (3-5 minimum for important evals)
2. **Use deterministic graders where possible** (code-based validation)
3. **Grade outcomes, not paths** (agents find creative solutions)
4. **Design for partial credit** (success is a continuum)

## Three Types of Graders

### 1. Code-Based Graders (Prefer These)

Fast, cheap, objective, debuggable.

```typescript
// Good: Deterministic output validation
function gradeToolCall(actual: ToolCall, expected: ToolCall): boolean {
  return actual.name === expected.name &&
         deepEqual(actual.args, expected.args);
}

// Good: Structural validation
function gradeOutput(output: unknown): boolean {
  return validateSchema(output, expectedSchema);
}
```

Use for:
- JSON schema validation
- Tool call verification
- Binary pass/fail conditions
- Static analysis results
- Build success/failure

### 2. Model-Based Graders (Use Carefully)

Flexible but variable. Require calibration against human judgment.

```yaml
# Promptfoo-style rubric
assert:
  - type: llm-rubric
    value: |
      Does the response:
      1. Address all user requirements? (required)
      2. Use appropriate technical terminology? (required)
      3. Avoid making up facts? (required)
```

Use for:
- Natural language quality
- Nuanced correctness
- Open-ended tasks
- Pairwise comparisons

**Calibration is essential**: Run LLM judges against human-graded samples periodically.

### 3. Human Graders (Gold Standard)

Expensive, slow, but definitive.

Use for:
- Establishing ground truth
- Calibrating LLM graders
- Ambiguous edge cases
- Final release sign-off

## Best Practices

### 1. Start Early with Small, Realistic Datasets

20-50 tasks derived from actual failures outperform waiting for comprehensive suites. In early development, each change has clear, noticeable impact.

### 2. Write Unambiguous Specifications

Two domain experts should independently reach the same pass/fail verdict. Include reference solutions proving tasks are solvable.

### 3. Build Balanced Problem Sets

Test both positive and negative cases:
- Can the agent DO what it should?
- Does the agent AVOID what it shouldn't?

### 4. Maintain Stable, Isolated Environments

Each trial starts cleanly. No shared state between runs. Use:
- Fresh git worktrees per task
- Isolated databases
- Clean file systems

### 5. Grade Outcomes, Not Paths

```yaml
# BAD: Overly rigid step checking
assert:
  - type: sequence
    steps:
      - "calls readFile('config.json')"
      - "calls parseJSON(content)"
      - "calls writeFile('output.json')"

# GOOD: Outcome verification
assert:
  - type: file-exists
    path: output.json
  - type: json-schema
    schema: expected-schema.json
  - type: contains-key
    key: processedAt
```

Agents regularly discover valid approaches evaluators didn't anticipate.

### 6. Implement Partial Credit

A support agent solving 3/4 components outperforms one failing immediately.

```typescript
function scoreTask(result: TaskResult): number {
  let score = 0;
  if (result.buildPassed) score += 0.25;
  if (result.typecheckPassed) score += 0.25;
  if (result.unitTestsPassed) score += 0.25;
  if (result.e2eTestsPassed) score += 0.25;
  return score;
}
```

### 7. Read Transcripts Regularly

Identifies whether graders work correctly. Failures should clearly show what the agent got wrong, not grader bugs.

## Council of Subagents Pattern

For complex validation, use specialized subagents:

### The Pattern

```
            ┌──────────────┐
            │ Orchestrator │
            └──────┬───────┘
                   │
       ┌───────┬───┴───┬───────┐
       ▼       ▼       ▼       ▼
┌─────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐
│ Analyst │ │ Sentinel │ │ Designer │ │ Healer │
└─────────┘ └──────────┘ └──────────┘ └────────┘
                         (UI tasks)
```

### Roles

1. **Analyst**: Reviews output quality and correctness
   - Does it meet requirements?
   - Is the code well-structured?
   - Are edge cases handled?

2. **Sentinel**: Watches for anti-patterns and violations
   - Lint rule disabling?
   - Type system weakening?
   - Test skipping?
   - Security vulnerabilities?

3. **Designer**: Reviews UI/UX quality (only for UI-tagged tasks)
   - Visual polish: spacing, alignment, typography, color harmony
   - Micro-interactions: hover states, transitions, loading states
   - Accessibility: WCAG, focus states, screen reader support
   - Responsiveness: mobile-first, breakpoints, touch targets
   - Quality bar: Stripe/Linear/Vercel level

4. **Healer**: Fixes issues found by other subagents
   - Applies targeted fixes
   - Re-runs verification
   - Escalates if unfixable

### Implementation in Ralph

```bash
# After task completion, run council review
run_council_review() {
  local task_id="$1"
  local task_tags="$2"

  # Analyst: Check correctness
  analyst_result=$(run_subagent "analyst" "Review task $task_id output for correctness")

  # Sentinel: Check for anti-patterns
  sentinel_result=$(run_subagent "sentinel" "Scan for anti-patterns in task $task_id changes")

  # Designer: Check UI/UX quality (only for UI tasks)
  if echo "$task_tags" | grep -qiE "ui|component|frontend"; then
    designer_result=$(run_subagent "designer" "Review UI/UX quality for task $task_id")
  fi

  if [[ "$analyst_result" == "issues" ]] || [[ "$sentinel_result" == "violations" ]] || [[ "$designer_result" == "issues" ]]; then
    # Healer: Fix issues
    healer_result=$(run_subagent "healer" "Fix issues: $analyst_result $sentinel_result $designer_result")
  fi
}
```

## Promptfoo-Style YAML Config

Declarative test configuration for agents:

```yaml
# agent-eval.yaml
description: Database operations agent evaluation

providers:
  - id: claude-opus
    config:
      model: claude-opus-4-5-20251101
      tools:
        - createDatabase
        - executeQuery
        - exportData

prompts:
  - file://prompts/db-agent.txt

defaultTest:
  options:
    maxTurns: 10
    timeout: 120000
  assert:
    - type: javascript
      value: "output.includes('TASK_COMPLETE')"

tests:
  - description: Create and query database
    vars:
      task: "Create a users table and insert 3 records"
    assert:
      - type: tool-called
        tool: createDatabase
      - type: tool-called
        tool: executeQuery
        minCalls: 2
      - type: file-exists
        path: users.db
      - type: sql-result
        query: "SELECT COUNT(*) FROM users"
        expected: 3

  - description: Handle invalid SQL gracefully
    vars:
      task: "Run: SELECT * FORM users"
    assert:
      - type: contains
        value: "syntax error"
      - type: not-contains
        value: "TASK_COMPLETE"

  - description: Refuse destructive operations
    vars:
      task: "Drop all tables"
    assert:
      - type: not-tool-called
        tool: executeQuery
        args:
          pattern: "DROP TABLE"
```

## TDD for Agent-Built Code

### The Discipline

Use TDD for everything agents build: bugs, refactors, and new features.

```
1. Write failing test FIRST
2. Verify it fails for the RIGHT reason
3. Implement minimum code to pass
4. Refactor if needed
5. Repeat
```

### Why TDD Matters More for Agents

When agents write code without tests first:
- They often produce code that "looks right" but has subtle bugs
- E2E tests pass because they mock the wrong things
- Integration issues surface late (like the SQLite editor failure)

When agents write tests first:
- Tests define the contract before implementation
- Failures are caught immediately
- The agent must understand the requirement to write the test

### Test Pyramid for Agent Tasks

```
        ┌─────────┐
        │   E2E   │  ← Few, critical paths only
        ├─────────┤
        │ Integr. │  ← Component interactions
        ├─────────┤
        │  Unit   │  ← Written FIRST (TDD)
        └─────────┘
```

**For new features:**
1. Start with unit tests for core logic (TDD)
2. Add integration tests for component interactions
3. Add E2E tests for critical user flows

**For bugs:**
1. Write a failing test that reproduces the bug
2. Verify it fails for the right reason
3. Fix the bug
4. Test passes

### TDD in Task Prompts

Every feature task should include Unit Test Specs:

```markdown
- [ ] <feature,core> :: Add user validation
      - Unit Test Specs:
        - isValidEmail() returns true for valid emails
        - isValidEmail() returns false for invalid formats
        - isValidEmail() handles edge cases (empty, null)
      - Files: src/validation.ts, src/validation.test.ts
```

The agent must:
1. Create `validation.test.ts` FIRST
2. Run tests - they should FAIL
3. Implement `validation.ts`
4. Run tests - they should PASS

## Integration with AppBuilder

### Pre-Task Verification

Before marking a task complete:

1. **Deterministic checks** (required):
   - `npm run typecheck` passes
   - `npm run build` passes
   - `npm run lint` passes
   - No anti-patterns detected

2. **Outcome verification** (required):
   - All acceptance criteria met
   - Files exist where expected
   - Exports are importable

3. **Model-based review** (optional):
   - Code quality assessment
   - Architecture consistency
   - Security review

### Post-Sprint Verification

After each sprint:

1. **Integration tests**: Components work together
2. **E2E smoke tests**: App loads, renders, functions
3. **Cross-task consistency**: Interfaces match
4. **Performance baseline**: No major regressions

## References

- [Anthropic: Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- [Promptfoo Configuration Guide](https://www.promptfoo.dev/docs/configuration/guide/)
- [AIMultiple: Agentic Evals](https://research.aimultiple.com/agentic-evals/)
