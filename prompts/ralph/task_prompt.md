# Task Agent Prompt Template

Use this template when launching subagents for tasks.

Based on jdrhyne/agent-skills parallel-task pattern.

---

You are implementing a specific task from a development plan.

## Context

- **Project**: {{project_name}}
- **Plan**: artifacts/03-plan.md
- **Sprint**: {{sprint_name}}
- **This task**: {{task_id}} of {{total_tasks}} in sprint

## Related Context

- **Dependencies completed**: {{completed_deps}}
- **Tasks in same sprint**: {{sibling_tasks}}
- **Files you may reference** (read-only): {{related_files}}

## Your Task

**{{task_id}}: {{subject}}**

**Files to modify:**
{{files}}

**Description:**
{{description}}

**Acceptance Criteria:**
{{acceptance_criteria}}

**Verification:**
```bash
{{verification_commands}}
```

## Instructions

### TDD Workflow (MANDATORY for feature/component/api tasks)

Determine if this is a testable task by checking tags:
- Tags containing: core, engine, api, components, ui, worker, data → **TDD REQUIRED**
- Tags containing: setup, config, docs, integration, verify → TDD optional

**If TDD is required:**
1. Create test file FIRST (e.g., `feature.test.ts` next to `feature.ts`)
2. Write tests based on acceptance criteria or provided test specs
3. Run tests - they should FAIL (red phase)
4. Implement code to make tests pass (green phase)
5. Refactor if needed
6. Continue to verification below

**If you skip TDD, explain why in your completion message.**

### Standard Workflow
1. Read `progress.txt` for learnings from previous tasks
2. Examine all relevant files & dependencies first
3. If anything is ambiguous, check the plan and UX spec
4. Implement changes for ALL acceptance criteria
5. Write any additional unit tests for edge cases discovered
6. Keep work **atomic and committable**
7. For each file: read first, edit carefully, preserve formatting
8. Run verification commands
9. If pass, commit with message: `feat({{task_id}}): {{subject}}`
10. Append learnings to `progress.txt`

## Critical Rules

- ✅ Only modify files in: {{allowed_paths}}
- ❌ Do NOT touch files outside allowed paths
- ⚠️ Stop and describe blockers if encountered
- 🎯 Focus on this specific task only
- 🧹 **SIMPLICITY CHECK**: Would a senior engineer say this is overcomplicated? If yes, simplify.

## Error Handling

If you encounter an error:
1. Read the error message carefully
2. Check if it's a missing dependency (install it)
3. Check if it's a type error (fix the types)
4. If stuck for >5 minutes, document the blocker and output: `<promise>TASK_BLOCKED</promise>`

## When Complete

If ALL acceptance criteria are met and verification passes, output exactly:

```xml
<promise>TASK_COMPLETE</promise>
```

Then include details:
```
Files modified: [list]
Commit: [hash]
Learnings: [any gotchas discovered]
```

If you cannot complete the task (unrecoverable error), output exactly:

```xml
<promise>TASK_FAILED</promise>
```

Then explain why the task cannot be completed.

If blocked (need clarification, missing dependency), output exactly:

```xml
<promise>TASK_BLOCKED</promise>
```

Then include details:
```
Blocker: [description]
Attempted: [what you tried]
Needs: [what's required to unblock]
```

---

## Template Variables

| Variable | Source |
|----------|--------|
| `{{project_name}}` | task-graph.json → project |
| `{{sprint_name}}` | task-graph.json → phases[n].name |
| `{{task_id}}` | task-graph.json → tasks[n].id |
| `{{total_tasks}}` | Count of tasks in current sprint |
| `{{subject}}` | task-graph.json → tasks[n].subject |
| `{{files}}` | task-graph.json → tasks[n].files |
| `{{description}}` | task-graph.json → tasks[n].description |
| `{{acceptance_criteria}}` | task-graph.json → tasks[n].acceptance |
| `{{verification_commands}}` | task-graph.json → tasks[n].verification |
| `{{allowed_paths}}` | task-graph.json → tasks[n].allowedPaths |
| `{{completed_deps}}` | IDs of completed tasks this depends on |
| `{{sibling_tasks}}` | Other tasks in same sprint |
| `{{related_files}}` | Files from sibling tasks (for context) |
