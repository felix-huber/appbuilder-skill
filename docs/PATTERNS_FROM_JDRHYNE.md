# Patterns Stolen from jdrhyne/agent-skills

This document maps patterns from jdrhyne/agent-skills to their Oracle Swarm integration.

## Source Skills Analyzed

| Skill | Purpose | Most Valuable Pattern |
|-------|---------|----------------------|
| `task-orchestrator` | Multi-agent coordination with tmux+Codex | Self-healing heartbeat, status tracking |
| `parallel-task` | Parse plans, launch parallel subagents | Loop pattern, task prompt template |
| `planner` | Create orchestrator-ready plans | Task atomicity, sprint demo checklists |
| `frontend-design` | UI design guidelines | ASCII wireframes, oklch colors |

---

## Pattern 1: Self-Healing Heartbeat (task-orchestrator)

### Original Pattern
```bash
# Check every 15 minutes via cron
# If no progress for 20+ min → restart with context
cron action:add job:{
  "schedule": "*/15 * * * *",
  "prompt": "Check orchestration progress..."
}
```

### Oracle Swarm Integration
- **File**: `scripts/ralph.sh`
- **Config**: `SELF_HEAL=true`, `STALL_THRESHOLD=20`
- **Skill**: `skills/parallel-execution/SKILL.md`

```bash
# Ralph now tracks lastProgress and can self-heal
if task stalled > 20min:
  capture_error_context()
  increment_attempt()
  restart_with_context()
```

---

## Pattern 2: Rich Status Tracking (task-orchestrator)

### Original Pattern
```
pending → blocked → running → stuck → error → complete → pr_open → merged
```

### Oracle Swarm Integration
- **File**: `docs/TASK_GRAPH_SCHEMA.md`
- **Schema**: Enhanced task-graph.json with:
  - `status`: pending/blocked/running/stuck/error/complete/committed/skipped
  - `attempt`: Current retry count
  - `lastProgress`: Timestamp for stall detection
  - `error`: Captured error message

---

## Pattern 3: Dependency Rules (task-orchestrator)

### Original Pattern
```
Same file = sequential
Different files = parallel
Explicit depends = wait
Phase gates = barrier
```

### Oracle Swarm Integration
- **Skill**: `skills/parallel-execution/SKILL.md`
- **Logic**: `isUnblocked()` function checks:
  1. All dependsOn tasks complete
  2. No running task shares files
  3. Status is pending

---

## Pattern 4: Loop Until Done (parallel-task)

### Original Pattern
```
Step 3: Launch parallel agents
Step 4: Monitor & Log
Step 5: Read plan again, find unblocked tasks
Step 6: Repeat until plan complete
"Do not stop until the plan is fully completed"
```

### Oracle Swarm Integration
- **File**: `scripts/ralph.sh`
- **Behavior**: Ralph already loops, but now with explicit "continue until done" instruction
- **Skill**: `skills/parallel-execution/SKILL.md` documents the loop

---

## Pattern 5: Task Prompt Template (parallel-task)

### Original Pattern
```markdown
You are implementing a specific task from a development plan.
## Context
- Plan: [filename]
- Sprint/phase: [name]
- Dependencies: [prerequisites]
## Your Task
**Task [ID]: [Name]**
Location: [File paths]
Description: [Full description]
Acceptance Criteria: [List]
## Instructions
1. Examine plan and files
2. Implement changes
3. Keep work atomic
4. Run validation
```

### Oracle Swarm Integration
- **File**: `prompts/ralph/task_prompt.md`
- **Used by**: Ralph when launching agents
- **Variables**: `{{task_id}}`, `{{subject}}`, `{{files}}`, etc.

---

## Pattern 6: Execution Summary (parallel-task)

### Original Pattern
```markdown
# Sprint/Phase Execution Summary
## Tasks Assigned: [N]
### Completed
- Task [ID]: [Name] - [Brief summary]
### Issues
- Task [ID]: Issue: [What] Resolution: [How]
### Blocked
- Task [ID]: Blocker: [What] Next Steps: [What]
```

### Oracle Swarm Integration
- **File**: `templates/EXECUTION_SUMMARY.template.md`
- **Generated**: After each Ralph run or sprint completion

---

## Pattern 7: Task Atomicity (planner)

### Original Pattern
```
❌ Bad: "Implement Google OAuth"
✓ Good:
  - "Add Google OAuth config to environment variables"
  - "Install passport-google-oauth20 package"
  - "Create OAuth callback route handler"
  - "Add Google sign-in button to login UI"
```

### Oracle Swarm Integration
- **File**: `templates/PLAN.template.md`
- **Section**: "Task Atomicity Principles"
- **Guidance**: Each task must be atomic, specific, testable, located

---

## Pattern 8: Sprint Demo Checklist (planner)

### Original Pattern
```markdown
## Sprint 1: [Name]
**Goal**: [What this accomplishes]
**Demo/Validation**:
- [How to run/demo]
- [What to verify]
```

### Oracle Swarm Integration
- **File**: `templates/PLAN.template.md`
- **Schema**: `phases[].demoValidation` array in task-graph.json
- **Verification**: Phase gates check demo before advancing

---

## Pattern 9: Complexity Ratings (planner)

### Original Pattern
```
- **Perceived Complexity**: [1-10]
```

### Oracle Swarm Integration
- **File**: `templates/PLAN.template.md`
- **Schema**: `tasks[].complexity` field in task-graph.json
- **Use**: Sort tasks, estimate sprint duration

---

## Pattern 10: ASCII Wireframes (frontend-design)

### Original Pattern
```
┌─────────────────────────────────────┐
│           HEADER / NAV              │
├─────────────────────────────────────┤
│           HERO SECTION              │
├───────────┬───────────┬─────────────┤
│  FEATURE  │  FEATURE  │  FEATURE    │
└───────────┴───────────┴─────────────┘
```

### Oracle Swarm Integration
- **Skill**: `skills/frontend-design/SKILL.md`
- **Workflow**: Layout → Theme → Animation → Implementation
- **Requirement**: Sketch ASCII before coding

---

## Pattern 11: Modern Color System (frontend-design)

### Original Pattern
```css
/* NEVER use #007bff (bootstrap blue) */
/* Use oklch() for modern color definitions */
:root {
  --primary: oklch(0.7 0.15 250);
}
```

### Oracle Swarm Integration
- **Skill**: `skills/frontend-design/SKILL.md`
- **Themes**: Dark mode, light mode, neo-brutalism, glassmorphism
- **Rule**: oklch() over hex, semantic variables

---

## Pattern 12: Animation Micro-Syntax (frontend-design)

### Original Pattern
```
button:     150ms [S1→0.95→1] press
hover:      200ms [Y0→-2, shadow↗]
fadeIn:     400ms ease-out [Y+20→0, α0→1]
```

### Oracle Swarm Integration
- **Skill**: `skills/frontend-design/SKILL.md`
- **Use**: Plan animations before implementing
- **Timing table**: Entry (300-500ms), hover (150-200ms), etc.

---

## Summary: Files Created/Modified

| File | Type | From Pattern |
|------|------|--------------|
| `skills/parallel-execution/SKILL.md` | New | task-orchestrator, parallel-task |
| `skills/frontend-design/SKILL.md` | New | frontend-design |
| `docs/TASK_GRAPH_SCHEMA.md` | New | task-orchestrator |
| `prompts/ralph/task_prompt.md` | New | parallel-task |
| `templates/EXECUTION_SUMMARY.template.md` | New | parallel-task |
| `templates/PLAN.template.md` | Updated | planner |
| `scripts/ralph.sh` | Updated | task-orchestrator (self-heal config) |

---

## Not Yet Integrated (Future Work)

| Pattern | Source | Reason |
|---------|--------|--------|
| Git worktree per task | task-orchestrator | Requires significant Ralph changes |
| tmux session management | task-orchestrator | Ralph uses Claude Code directly |
| Auto PR creation | task-orchestrator | Would need GitHub integration |
| Cron heartbeat | task-orchestrator | User runs Ralph interactively |

These could be added later for more advanced multi-agent scenarios.
