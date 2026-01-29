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

### TDD Workflow (for feature tasks with Unit Test Specs)
If this task has UNIT TEST SPECS in the description:
1. Create test file FIRST with all specified tests
2. Run tests - they should FAIL (red phase)
3. Implement code to make tests pass (green phase)
4. Refactor if needed
5. Continue to verification below

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
4. If stuck for >5 minutes, document the blocker and output: TASK_BLOCKED

## When Complete

If ALL acceptance criteria are met and verification passes:

```
TASK_COMPLETE
Files modified: [list]
Commit: [hash]
Learnings: [any gotchas discovered]
```

If blocked:

```
TASK_BLOCKED
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
