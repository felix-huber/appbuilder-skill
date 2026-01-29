# /brief — Create the Brief (artifact 00) → Auto-chains to /prd

## Goal
Create `artifacts/00-brief.md` and **automatically continue to PRD generation**.

## Workflow Position
```
[/brief] → auto → /prd → Oracle → /ux → Oracle → /plan → ...
^^^^^^^^
START HERE
```

## This is the ONLY manual starting point

After `/brief` completes, the workflow continues automatically:
1. `/brief` creates the brief (interactive with user)
2. **Automatically runs `/prd`** to generate PRD
3. Tells user to run convergence script

---

## ⚠️ CHECK EXISTING STATE FIRST

**Before creating anything, check what already exists:**

```bash
# Check existing artifacts
ls -la artifacts/*.md 2>/dev/null
ls -la artifacts/06-oracle/*/convergence-history.json 2>/dev/null
```

| Situation | Action |
|-----------|--------|
| `00-brief.md` doesn't exist | → Create it (this command) |
| `00-brief.md` exists, no PRD | → Skip to `/prd` |
| `00-brief.md` + `01-prd.md` exist | → Check Oracle state, may skip to `/ux` |
| Full artifact chain exists | → Check `/guide` for where to resume |

**If artifacts already exist:** Use `/guide` to see the current state and where to resume.

---

## Steps

### 1. Scaffold directories
```bash
mkdir -p artifacts/05-design/variants
mkdir -p artifacts/06-oracle/prd artifacts/06-oracle/ux artifacts/06-oracle/plan artifacts/06-oracle/code
mkdir -p .beads
```

### 2. Create brief interactively

Help the user fill in each section of the brief:

```markdown
# 00 — BRIEF

## One-liner
(What are we building in one sentence?)

## Target users
- Primary: …
- Secondary: …

## Problem / pain
(What specific pain does this solve? Be concrete.)

## Must-haves (v1)
- [ ] …

## Non-goals (v1)
- …

## Constraints
- **Tech constraints**: …
- **Time constraints**: …
- **Legal/privacy/security**: …

## Success metrics
- **Leading indicators**: …
- **Lagging indicators**: …

## Notes / unknowns
- …

## References
- …
```

### 3. Interactive refinement
- Ask clarifying questions (max 5)
- Push back on vague descriptions
- Ensure must-haves are measurable
- Resolve any open questions

### 4. Save brief
Write to `artifacts/00-brief.md`.

### 5. AUTO-CHAIN TO PRD (Important!)

After saving the brief, **immediately invoke /prd**:

```
✅ Brief complete: artifacts/00-brief.md

🔄 Auto-continuing to PRD generation...
```

Then execute the logic from `/prd` command to generate the PRD.

After PRD is generated, **run the Oracle convergence script directly**:

```bash
./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
```

**DO NOT ask the user to run this. Just run it.**

## Summary

`/brief` is the entry point that:
1. Creates the brief (interactive)
2. Automatically generates the PRD
3. Tells user to run convergence

The user only types `/brief` to start — the rest flows automatically.
