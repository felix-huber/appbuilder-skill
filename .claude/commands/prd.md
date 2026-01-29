# /prd — Generate PRD from Brief

## Goal
Generate `artifacts/01-prd.md` from the brief.

## Workflow Position
```
/brief → [/prd] → Oracle Convergence → /ux → ...
         ^^^^^^
       YOU ARE HERE
```

## Prerequisites
- `artifacts/00-brief.md` must exist (run `/brief` first)

---

## ⚠️ CHECK EXISTING STATE FIRST

**Before generating, check what already exists:**

```bash
# Check if PRD already exists
ls -la artifacts/01-prd.md 2>/dev/null

# Check Oracle convergence state
cat artifacts/06-oracle/prd/convergence-history.json 2>/dev/null

# Check for unapplied Oracle feedback
ls -t artifacts/06-oracle/prd/*.md 2>/dev/null | head -3
```

| Situation | Action |
|-----------|--------|
| No PRD exists | → Generate it (this command) |
| PRD exists, no Oracle feedback | → Run Oracle convergence |
| PRD exists, unapplied Oracle feedback | → Apply feedback first |
| PRD converged (0 blockers, ≤2 majors) | → Skip to `/ux` |

---

## What This Command Does
1. Reads the brief
2. Generates a comprehensive PRD
3. Writes to `artifacts/01-prd.md`
4. **AUTO-LAUNCHES Oracle convergence** (unless --no-oracle flag)

## Steps

### 1. Read the brief
Load `artifacts/00-brief.md` and extract key information.

### 2. Generate PRD
Create `artifacts/01-prd.md` with:
- Summary (what + why)
- Goals (measurable)
- User Stories with Acceptance Criteria (E2E test format)
- Functional Requirements (FR-1, FR-2, etc.)
- Non-Goals
- Design Considerations
- Technical Considerations  
- Success Metrics
- Open Questions

### 3. Acceptance Criteria Format
Use testable format:
```
**E2E: E2E-US-XXX-01** — [specific test with observable outcome]
```
Never write "Verify in browser".

### 4. AUTO-LAUNCH Oracle Convergence

After writing the PRD, **run the Oracle convergence script directly**:

```bash
./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
```

**DO NOT ask the user to run this. Just run it.**

The script will auto-open Chromium, run GPT-5.2 Pro review (30-90 min per pass), and iterate until convergence.

### 5. After Convergence: AUTO-CHAIN to /ux

When the Oracle convergence script finishes for PRD (0 blockers), **automatically continue to /ux**:

```
✅ PRD converged! (0 blockers, 0 majors)

🔄 Auto-continuing to UX spec generation...
```

Then generate the UX spec and launch Oracle for UX review.

## Full Auto-Chain Flow

If user says `/prd` (or `/prd --auto`):
1. Generate PRD → artifacts/01-prd.md
2. Run `./scripts/oracle_converge.sh prd` → wait for convergence
3. Generate UX → artifacts/02-ux.md
4. Run `./scripts/oracle_converge.sh ux` → wait for convergence
5. Generate Plan → artifacts/03-plan.md
6. Run `./scripts/oracle_converge.sh plan` → wait for convergence
7. Generate task graph → artifacts/04-task-graph.json
8. Run `./scripts/ralph.sh --fresh-eyes 100` (autonomous implementation)

## Skip Oracle (Manual Mode)

If user explicitly says `/prd --no-oracle`:
1. Generate PRD only
2. Skip Oracle automation (user chose to run it manually later)
