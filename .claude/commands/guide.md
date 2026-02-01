# /guide — Where Am I? What's Next?

Check which artifacts exist and tell the user exactly where they are and what to do next.

## ⚠️ RUN THESE CHECKS FIRST

**Always start by running these commands to understand current state:**

```bash
# 0. Load project context (new in v2)
/context prime

# 1. What artifacts exist?
ls -la artifacts/*.md artifacts/*.json 2>/dev/null

# 2. What's the Oracle convergence state for each phase?
for kind in prd ux plan code; do
  echo "=== $kind ==="
  cat artifacts/06-oracle/$kind/convergence-history.json 2>/dev/null | jq '.rounds[-1]' || echo "No history"
done

# 3. Any unapplied Oracle feedback?
for kind in prd ux plan code; do
  echo "=== $kind Oracle files ==="
  ls -t artifacts/06-oracle/$kind/*.md 2>/dev/null | head -2
done

# 4. Task/execution state?
cat artifacts/04-task-graph.json 2>/dev/null | jq '.meta.counts'
cat progress.txt 2>/dev/null | tail -10
```

**Then use the decision logic below to determine next steps.**

---

## Task Management: Two Options

**Option A: task-graph.json (DEFAULT - No Install Required)**
- Tasks stored in `artifacts/04-task-graph.json`
- Ralph reads/updates this file directly
- Run: `./scripts/ralph.sh --fresh-eyes 100`

**Option B: beads_rust (Optional - More Features)**
- Requires: `cargo install --git https://github.com/Dicklesworthstone/beads_rust.git`
- Tasks stored in `.beads/` directory
- Better dependency visualization with `br ready`
- Run: `./scripts/ralph.sh --beads --fresh-eyes 100`

**Recommendation:** Start with task-graph.json (Option A). Add beads later if you need better dependency management.

## Workflow Overview

```
Phase 1: PLANNING (auto-chains where possible)
┌─────────────────────────────────────────────────────────────────────┐
│  /brief → auto → /prd                                               │
│     ↓                                                               │
│  ./scripts/oracle_converge.sh prd ...  (terminal, 30-90 min × N)    │
│     ↓                                                               │
│  /ux  → (after converge, auto → /plan)                              │
│     ↓                                                               │
│  ./scripts/oracle_converge.sh plan ... (auto-compiles task graph!)  │
└─────────────────────────────────────────────────────────────────────┘

Phase 2: PRE-IMPLEMENTATION REVIEW
┌─────────────────────────────────────────────────────────────────────┐
│  /review code                                                       │
│  (Review task graph 2-3 times until clean)                          │
└─────────────────────────────────────────────────────────────────────┘

Phase 3: IMPLEMENTATION (choose one)
┌─────────────────────────────────────────────────────────────────────┐
│  DEFAULT (no install needed):                                       │
│    ./scripts/ralph.sh --fresh-eyes 100                              │
│                                                                     │
│  WITH BEADS (optional, better dependency tracking):                 │
│    bash artifacts/04-beads-setup.sh                                 │
│    ./scripts/ralph.sh --beads --fresh-eyes 100                      │
│                                                                     │
│  (Autonomous - can run overnight, 4-8 hours typical)                │
└─────────────────────────────────────────────────────────────────────┘

Phase 4: VERIFICATION
┌─────────────────────────────────────────────────────────────────────┐
│  ./scripts/oracle_converge.sh code src/**/*.ts                      │
│     ↓                                                               │
│  /gates → /ship → /retro                                            │
└─────────────────────────────────────────────────────────────────────┘
```

## Check Current State

Read the artifacts directory:
- `artifacts/00-brief.md` - Brief
- `artifacts/01-prd.md` - PRD
- `artifacts/02-ux.md` - UX spec
- `artifacts/03-plan.md` - Implementation plan
- `artifacts/04-task-graph.json` - Task graph (always created)
- `artifacts/04-beads-setup.sh` - Beads setup script (optional)
- `.beads/` directory - Active beads tasks (if using beads)

Also check:
- `artifacts/06-oracle/*/issues.json` - Convergence status
- `tasks/todo.md` - Session-level task tracking (for plan mode)
- `tasks/lessons.md` - Captured lessons from mistakes

## Decision Logic

### No artifacts:
```
📍 Phase 1: PLANNING (Step 1)

Starting fresh! Run:
  /brief

This creates the project brief through an interactive conversation.
```

### Only 00-brief.md:
```
📍 Phase 1: PLANNING (Step 2)

✅ Brief complete
⏳ Next: /prd

This generates the PRD, then you'll run the convergence script:
  ./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
```

### 00-brief.md + 01-prd.md exist:
Check if PRD has converged (artifacts/06-oracle/prd/issues.json exists with 0 blockers/majors):
- If NOT converged: "Run convergence script: ./scripts/oracle_converge.sh prd ..."
- If converged: "Run /ux"

### 00-brief.md + 01-prd.md + 02-ux.md:
Check if UX has converged:
- If NOT converged: "Run convergence script: ./scripts/oracle_converge.sh ux ..."
- If converged: "Run /plan"

### All planning artifacts (00-03):
Check if Plan has converged:
- If NOT converged: "Run convergence script: ./scripts/oracle_converge.sh plan ..."
- If converged: "Run /artifact-tasks"

### 04-beads-setup.sh exists but .beads/ empty:
```
📍 Phase 2: TASK BREAKDOWN (Step 2)

Run: bash artifacts/04-beads-setup.sh
```

### .beads/ has tasks:
```
📍 Phase 2: TASK BREAKDOWN (Step 3)

Run: /review beads

Do this 6-9 times! Each pass catches different issues.
```

### Beads reviewed and ready:
```
📍 Phase 3: IMPLEMENTATION

Ready for autonomous execution:
  ./scripts/ralph.sh --beads --fresh-eyes 100

(Can run overnight - Claude Code will execute this)
```

## Important Notes

- **Oracle convergence takes hours**: Each round is 30-90 min, typically 2-4 rounds per artifact
- **Total planning time**: 4-24 hours depending on complexity
- **Implementation is autonomous**: Ralph can run unattended
- **Scripts run automatically**: Claude Code executes scripts directly, don't run manually
