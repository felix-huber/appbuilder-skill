# /combined-lfg — Full Integrated Workflow (Mostly Automated)

## Goal
Run the complete workflow from brief to ship. **Most steps are now fully automated!**

---

## ⚠️ CHECK EXISTING STATE FIRST

**Before starting, always check what already exists:**

```bash
# What artifacts exist?
ls -la artifacts/*.md artifacts/*.json 2>/dev/null

# What's the Oracle state?
for kind in prd ux plan code; do
  echo "=== $kind: $(cat artifacts/06-oracle/$kind/convergence-history.json 2>/dev/null | jq -r '.rounds[-1] | "\(.blockers) blockers, \(.majors) majors"' || echo 'no history') ==="
done

# Execution state?
cat progress.txt 2>/dev/null | tail -5
```

| Situation | Action |
|-----------|--------|
| No artifacts | Start from Step 1.1 (/brief) |
| Partial artifacts | Use `/guide` to find resume point |
| Oracle feedback unapplied | Apply it first, then continue |
| All phases complete | Run `/retro` |

---

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    COMBINED-LFG WORKFLOW                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PHASE 1: PLANNING (Fully Automated)                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ /brief → /prd (auto-Oracle) → /ux (auto-Oracle)        │   │
│  │ → /ui (optional) → /plan (auto-Oracle)                 │   │
│  │                                                         │   │
│  │ Each command runs Oracle convergence automatically!    │   │
│  │ Max 5 iterations, stops at 0 blockers/majors.          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            ↓                                    │
│  PHASE 2: TASK COMPILATION                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ /artifact-tasks → bash artifacts/04-beads-setup.sh     │   │
│  │ /review beads (6-9 times!)                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            ↓                                    │
│  PHASE 3: EXECUTION (Autonomous)                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ ./scripts/ralph.sh --beads --fresh-eyes 100            │   │
│  │ (Can run overnight - fully autonomous)                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                            ↓                                    │
│  PHASE 4: VERIFICATION                                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ /oracle code → /gates → /ship → /retro                 │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## What's Automated Now

| Step | Old (Manual) | New (Automated) |
|------|--------------|-----------------|
| `/prd` | Generate PRD, user runs Oracle manually | Generate PRD + auto-Oracle convergence loop |
| `/ux` | Generate UX, user runs Oracle manually | Generate UX + auto-Oracle convergence loop |
| `/plan` | Generate Plan, user runs Oracle manually | Generate Plan + auto-Oracle convergence loop |
| Ralph | User re-runs manually on failure | Auto-retry with fresh-eyes review |

## Steps

### Phase 1: Planning (Each Step is Fully Automated)

#### Step 1.1: Brief
```
/brief
```
- Create `artifacts/00-brief.md`
- Interactive: help user fill in sections
- **NOT automated** - requires human input

#### Step 1.2: PRD (Fully Automated)
```
/prd
```
This command does EVERYTHING:
1. Generate `artifacts/01-prd.md`
2. Run Oracle review (30-90 min)
3. Read issues, apply fixes
4. Re-run Oracle until converged (max 5 iterations)
5. Auto-chain to `/ux` (no user action needed)

**You do NOT need to run `/oracle <kind>` separately.**

#### Step 1.3: UX (Fully Automated)
```
/ux
```
Same as above - fully automated Oracle convergence.

#### Step 1.4: UI Exploration (Optional)
```
/ui
```
- Create design variants with Tasteboard
- Skip if not doing UI-heavy work

#### Step 1.5: Plan (Fully Automated)
```
/plan
```
Same as above - fully automated Oracle convergence.

#### Step 1.6: UI Exploration (Optional)
Ask user:
> Do you want to explore UI direction with tasteboard? (y/n)

If yes:
```
/ui
```
- Guide through tasteboard
- Generate keystone + variants
- **PAUSE** for human review in design gallery

---

### Phase 2: Task Compilation

#### Step 2.1: Compile Task Graph
```
/artifact-tasks
```
- Run `compile_task_graph.js`
- Create `artifacts/04-beads-setup.sh`
- Create beads structure with dependencies

#### Step 2.2: Initialize Beads
```bash
bash artifacts/04-beads-setup.sh
```

#### Step 2.3: Review Beads (6-9 times!)
```
/review beads
```
- Critical step! Run 6-9 times before implementation
- Each pass catches different issues

---

### Phase 3: Execution (Ralph - Autonomous)

#### Step 3.1: Spawn Swarm
Use Compound Engineering's swarm system:
```
/slfg
```

Or manually:
```
TeammateTool spawnTeam { team_name: "project-swarm", description: "..." }
```

Spawn teammates:
- `engine-worker`: Core engine tasks
- `ui-worker`: UI component tasks
- `test-worker`: Test tasks
- `io-worker`: I/O and integration tasks

#### Step 3.2: Execute Work
Let swarm work through tasks.

Monitor with:
```
/swarm-status
```

Or Compound Engineering's:
```
TaskList { team: "project-swarm" }
```

#### Step 3.3: Review with Compound Engineering
When code is ready:
```
/workflows:review
```
- 13 agents review in parallel
- security-sentinel, performance-oracle, etc.
- Apply findings

---

### Phase 4: Final Review

#### Step 4.1: Oracle Code Review
```
/oracle code
```
**PAUSE**: Print command:
```bash
./scripts/oracle_converge.sh code <changed-files>
```

Or for specific files:
```bash
./scripts/oracle_converge.sh code src/core/*.ts src/ui/*.tsx
```

**WAIT** for `artifacts/06-oracle/code/issues.json`.
- Review external perspective
- Apply fixes

---

### Phase 5: Ship

#### Step 5.1: Verification Gates
```
/gates
```
- Run lint, types, tests, build
- Generate `artifacts/07-verification.md`

If gates fail:
> Gates failed. Fix issues and re-run `/gates`.

#### Step 5.2: Release Plan
```
/ship
```
- Generate `artifacts/08-release.md`
- Include rollout steps, monitoring, rollback

#### Step 5.3: Retrospective
After shipping:
```
/retro
```
- Capture learnings
- Update templates and prompts
- Generate `artifacts/09-retro.md`

---

## Timing Estimates

| Phase | Estimated Time |
|-------|----------------|
| Planning (with Oracle) | 2-4 hours |
| Task Compilation | 15 minutes |
| Execution (swarm) | Varies by project |
| Final Review | 1-2 hours |
| Ship | 1 hour |
| **Total overhead** | ~5-8 hours |

## Customization

### Skip UI Exploration
```
/combined-lfg --skip-ui
```

### Skip Oracle Reviews (Not Recommended)
```
/combined-lfg --skip-oracle
```

### Specific Lenses Only
```
/combined-lfg --lenses security,performance,tests
```

## Interruption Recovery

If interrupted, check:
1. Which artifacts exist?
2. Which Oracle outputs exist?
3. Resume from the next missing step.

```bash
ls artifacts/
# See what exists, resume from there
```
