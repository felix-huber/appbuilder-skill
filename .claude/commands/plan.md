# /plan — Generate Implementation Plan

## Goal
Generate `artifacts/03-plan.md` with architecture, risks, and demoable sprints.

## Workflow Position
```
/brief → /prd → Oracle → /ux → Oracle → [/plan] → Oracle → /artifact-tasks
                                         ^^^^^^
                                       YOU ARE HERE
```

## Prerequisites
- `artifacts/01-prd.md` must exist
- `artifacts/02-ux.md` must exist
- Both should have converged

---

## ⚠️ CHECK EXISTING STATE FIRST

**Before generating, check what already exists:**

```bash
# Check if plan already exists
ls -la artifacts/03-plan.md 2>/dev/null

# Check PRD and UX convergence (prerequisites)
cat artifacts/06-oracle/prd/convergence-history.json 2>/dev/null
cat artifacts/06-oracle/ux/convergence-history.json 2>/dev/null

# Check plan Oracle state
cat artifacts/06-oracle/plan/convergence-history.json 2>/dev/null

# Check for unapplied plan feedback
ls -t artifacts/06-oracle/plan/*.md 2>/dev/null | head -3
```

| Situation | Action |
|-----------|--------|
| PRD or UX not converged | → Run Oracle on those first |
| No plan exists | → Generate it (this command) |
| Plan exists, no Oracle feedback | → Run Oracle convergence |
| Plan exists, unapplied Oracle feedback | → Apply feedback first |
| Plan converged (0 blockers, ≤2 majors) | → Skip to `/artifact-tasks` |

---

## What This Command Does
1. Reads PRD and UX spec
2. Generates implementation plan with sprints
3. Writes to `artifacts/03-plan.md`
4. **AUTO-LAUNCHES Oracle convergence** (unless --no-oracle flag)

## CRITICAL: Demoable Sprints

Each sprint MUST be:
- **Demoable**: Something works after completion
- **Buildable**: Builds on previous sprint
- **Testable**: Clear verification criteria

## CRITICAL: Task Atomicity (from jdrhyne/planner)

Each task MUST be:
- **Atomic and committable** — small, independent pieces of work
- **Specific and actionable** — not vague
- **Testable** — include verification method
- **Located** — include file paths

**❌ Bad Task:** "Implement Google OAuth"
**✅ Good Tasks:**
- Add Google OAuth environment variables
- Install passport-google-oauth20 package
- Create OAuth callback route handler
- Add Google sign-in button to login page

## Steps

### 1. Analyze Requirements
Read PRD and UX to understand:
- Data models
- Component boundaries
- State management
- Dependencies

### 2. Generate Plan
Create `artifacts/03-plan.md` with:

- Architecture Overview (diagram, modules, data model)
- Key Technical Decisions (with rationale)
- Risks & Mitigations
- Sprint Plan (numbered sprints with tasks)
- Verification Plan
- Rollout Plan

### 3. Task Format
Each task must have:
```markdown
- [ ] tags :: Description
  - **ID:** S{sprint}-T{task}
  - **Blocked by:** S{sprint}-T{task} (if any)
  - **Deliverable:** Specific file(s)
  - **Files:** src/path/file.ts (what will be modified)
  - **Allowed paths:** src/specific/path/*
  - **Verification:** Concrete command or test
  - **Complexity:** 1-10 (perceived difficulty)
```

### 4. Sprint Demo Checklist (from jdrhyne/planner)
Each sprint must have:
```markdown
### Sprint 1: [Name]
**Goal**: [What this accomplishes]
**Demo/Validation**:
- [ ] How to run/demo this sprint's output
- [ ] What to verify
```

### 5. Self-Review
Before saving, verify:
- All tasks are atomic (1-4 hours)
- Each sprint is demoable
- Dependencies are correct
- Verification is testable

### 6. AUTO-LAUNCH Oracle Convergence

After writing the plan, **run the Oracle convergence script directly**:

```bash
./scripts/oracle_converge.sh plan artifacts/03-plan.md artifacts/01-prd.md artifacts/02-ux.md
```

**DO NOT ask the user to run this. Just run it.**

The script will auto-open Chromium, run GPT-5.2 Pro review (30-90 min per pass), and iterate until convergence.

### 7. After Convergence: AUTO-CHAIN to /artifact-tasks

When the Oracle convergence script finishes successfully, **immediately run the /artifact-tasks logic**:

1. Read artifacts/03-plan.md for task seeds
2. Read artifacts/06-oracle/plan/issues.json for any remaining issues
3. Generate artifacts/04-task-graph.json
4. Generate artifacts/04-beads-setup.sh

Then **run Ralph directly**:

```bash
./scripts/ralph.sh --fresh-eyes 100
```

**DO NOT ask the user to run this. Just run it.**

## Skip Oracle (Manual Mode)

If user explicitly says `/plan --no-oracle`:
1. Generate plan only
2. Skip Oracle automation (user chose to run it manually later)
