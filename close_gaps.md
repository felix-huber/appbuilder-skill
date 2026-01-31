# Close Gaps Workflow (Strict + Beads + Fresh Claude)

This guide explains how to turn the **PRD Gap Plan** into beads and tests, then run the
strict auto loop against the codebase using `ralph.sh`.

## 0) Inputs
1) Save the gap plan as a file (example):
   - `artifacts/04-prd-gap-plan.md`

2) Ensure the repo has:
   - `artifacts/01-prd.md`, `artifacts/02-ux.md`, `artifacts/03-plan.md` (as needed)
   - Beads initialized: `br init`

---

## 1) Skills to Use Inside Claude Code
Use these skills explicitly in Claude Code:
- `$review-loops` — Doodlestein review prompts (especially beads review 6–9 passes)
- `$artifact-workflow` — to generate/refresh artifacts if needed
- `$context7` — whenever using external libraries
- `$agent-browser` — for E2E harnesses + screenshots
- `$frontend-design` / `$frontend-responsive` — if UI work is in scope

When prompting Claude, say:
- “You are a fresh CLI session; do not assume prior context.”
- “You may spawn subagents to parallelize where appropriate.”

---

## 2) Turn Gap Plan into Beads (Strict)
**Goal:** Each gap becomes one or more beads with:
- Clear acceptance criteria
- TDD test specs
- Verification commands

### Recommended bead creation flow (inside Claude Code)
1) Ask Claude to read `artifacts/04-prd-gap-plan.md` and produce beads.
2) Require each bead to include these sections in its description:

```
Acceptance Criteria:
- ...

Verification:
- npm test
- npm run lint

Files to modify:
- src/...
```

3) Enforce TDD and test harness instructions in the bead text.

### Beads Review Loop (required)
Use the **Doodlestein beads review prompt** from `$review-loops` **6–9 times**
until no changes remain. This is the quality gate that prevents fake tests.

---

## 3) Run Strict Auto Loop (outside Claude)
Once beads are ready:

```
./scripts/ralph.sh --beads --tool claude --review-tool codex --strict 50
```

What this does:
- Picks the next unblocked bead via `br ready --json`
- Runs Claude in a fresh CLI session for implementation
- Runs Claude in a fresh CLI session for review
- Enforces test changes + verification commands
- Logs progress to `progress.txt`
- Appends learnings to `learnings.md`
- Writes summary to `artifacts/08-execution-summary.md`

### Important knobs
- `--allow-no-tests` only for non-code tasks
- `--allow-no-verify` if a bead lacks verification commands
- `--no-commit` to manually review before committing (loop stops after 1 task)

---

## 4) Verification + E2E
After loop completion:

```
./scripts/gate_pack.sh
./scripts/run_e2e_happy_paths.sh   # if present
```

If E2E is missing for critical flows, add a **test harness**:
- UI: minimal route/screen rendering real component + mock data
- CLI: fixture command using temp inputs
- API: minimal runner hitting real endpoints
- Library: end-to-end usage example

---

## 5) Summary Checklist
- [ ] Gap plan saved
- [ ] Beads created with Acceptance Criteria + Verification
- [ ] Beads reviewed 6–9 times (Doodlestein)
- [ ] Strict loop run with fresh Claude for coder + reviewer
- [ ] All tests real (no tautologies)
- [ ] Gates + E2E executed

---

If you want, I can add a template bead structure or a ready-to-paste prompt for
Claude to convert the gap plan into beads.
