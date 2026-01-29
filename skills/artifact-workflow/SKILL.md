---
name: artifact-workflow
description: Manages the artifact-driven development workflow. Use when checking workflow status, determining next steps, validating artifact completeness, or understanding the phase you're in.
triggers:
  - artifact
  - workflow status
  - what's next
  - phase check
  - what phase
  - workflow progress
  - artifact chain
---

# Artifact Workflow Skill

Manage the artifact-driven development workflow with explicit phases and deliverables.

## ⚠️ ALWAYS CHECK STATE FIRST

**Before any action, run this to understand current state:**

```bash
# Quick status check
ls -la artifacts/*.md artifacts/*.json 2>/dev/null
ls -la artifacts/06-oracle/*/convergence-history.json 2>/dev/null

# Or use the guide command
/guide
```

This prevents double-work and ensures you resume from the right place.

---

## Artifact Chain

```
00-brief.md        → Problem definition
      ↓
01-prd.md          → Requirements + acceptance criteria
      ↓
   [oracle prd]    → External review (ITERATE UNTIL CONVERGENCE)
      ↓
02-ux.md           → Flows + state matrices
      ↓
   [oracle ux]     → External review (ITERATE UNTIL CONVERGENCE)
      ↓
05-design/*        → UI exploration (optional)
      ↓
03-plan.md         → Architecture + SPRINT-ORGANIZED task seeds
      ↓
   [oracle plan]   → External review (ITERATE UNTIL CONVERGENCE)
      ↓
04-task-graph.json → Compiled tasks (+ optional beads setup)
      ↓
   [code]          → Implementation via Ralph
      ↓
06-oracle/code/*   → Code review (ITERATE UNTIL CONVERGENCE)
      ↓
07-verification.md → Gate results
      ↓
08-release.md      → Rollout plan
      ↓
09-retro.md        → Learnings
```

## CRITICAL: Oracle Convergence Rule

**Every Oracle review phase must iterate until issues converge to zero (or stable):**

```
Oracle Pass 1: 8 issues found → Fix → Re-run
Oracle Pass 2: 3 new issues  → Fix → Re-run
Oracle Pass 3: 0 new issues  → CONVERGED ✓
```

Do NOT proceed to the next phase until:
- All blockers are resolved
- All major issues are addressed
- New issues = 0 (or only nits remain)

## Phase Detection

To determine current phase, check which artifacts exist:

```javascript
const phases = {
  'brief': !exists('artifacts/00-brief.md'),
  'prd': exists('artifacts/00-brief.md') && !exists('artifacts/01-prd.md'),
  'oracle-prd': exists('artifacts/01-prd.md') && !oracleConverged('prd'),
  'ux': oracleConverged('prd') && !exists('artifacts/02-ux.md'),
  'oracle-ux': exists('artifacts/02-ux.md') && !oracleConverged('ux'),
  'ui': oracleConverged('ux') && !exists('artifacts/05-design/keystone.html'),
  'plan': (oracleConverged('ux') || exists('artifacts/05-design/keystone.html')) && !exists('artifacts/03-plan.md'),
  'oracle-plan': exists('artifacts/03-plan.md') && !oracleConverged('plan'),
  'tasks': oracleConverged('plan') && !exists('artifacts/04-task-graph.json'),
  'code': exists('artifacts/04-task-graph.json') && !exists('artifacts/07-verification.md'),
  'gates': hasCode() && !exists('artifacts/07-verification.md'),
  'ship': exists('artifacts/07-verification.md') && !exists('artifacts/08-release.md'),
  'retro': exists('artifacts/08-release.md') && !exists('artifacts/09-retro.md'),
  'done': exists('artifacts/09-retro.md')
};

// Helper: Check if Oracle has converged (run multiple times, issues stable)
function oracleConverged(kind) {
  const issuesFile = `artifacts/06-oracle/${kind}/issues.json`;
  if (!exists(issuesFile)) return false;
  
  const issues = JSON.parse(read(issuesFile));
  const blockers = issues.filter(i => i.severity === 'blocker').length;
  const majors = issues.filter(i => i.severity === 'major' && !i.addressed).length;
  
  // Converged if no unaddressed blockers/majors
  return blockers === 0 && majors === 0;
}
```

## Workflow Status Check

When user asks "what's next" or "where am I":

1. Check which artifacts exist
2. Check Oracle convergence status
3. Identify current phase
4. Report next action

Example response:
```
Workflow Status:
├── ✅ 00-brief.md
├── ✅ 01-prd.md
├── ✅ 06-oracle/prd/issues.json
│   └── Pass 1: 5 issues → addressed
│   └── Pass 2: 2 issues → addressed
│   └── Pass 3: 0 issues → CONVERGED ✓
├── ✅ 02-ux.md
├── ⚠️  06-oracle/ux/issues.json
│   └── Pass 1: 8 issues → 3 addressed, 2 blockers remaining
└── ...

Current phase: oracle-ux (not converged)
Next action: Address remaining blockers, then re-run `/oracle ux`
```

## Artifact Validation

### Brief Validation
- [ ] One-liner is specific, not vague
- [ ] Target users are concrete personas
- [ ] Must-haves are measurable
- [ ] Non-goals are explicit
- [ ] Constraints are documented

### PRD Validation
- [ ] Every must-have has a user story
- [ ] Every story has acceptance criteria
- [ ] Edge cases are documented
- [ ] Observability events defined
- [ ] Security requirements stated

### UX Validation
- [ ] Every story maps to a flow
- [ ] Every screen has state matrix
- [ ] Error states are explicit
- [ ] Accessibility documented
- [ ] Responsive rules defined

### Plan Validation
- [ ] Architecture diagram exists
- [ ] Key decisions documented with rationale
- [ ] Risks have mitigations
- [ ] **Tasks organized into SPRINTS**
- [ ] **Each sprint is DEMOABLE**
- [ ] Task seeds in correct format with IDs
- [ ] Verification plan is runnable
- [ ] Self-review step completed

### Task Graph Validation
- [ ] No orphan tasks (no dependencies, nothing depends on them)
- [ ] No circular dependencies
- [ ] All tasks have verification
- [ ] Task sizes are reasonable (< 4h)
- [ ] **Sprint structure preserved**
- [ ] **beads setup script generated (if using beads)**

## Phase Transitions

### Blocking Rules
Do NOT proceed to next phase if:
- Oracle review has not converged (unaddressed blockers/majors)
- Artifact is incomplete (missing required sections)
- Previous phase has unresolved issues
- Plan lacks sprint structure
- Tasks lack verification commands

### Non-Blocking
Can proceed with warnings for:
- Minor/nit issues from Oracle
- Optional sections missing
- Nice-to-have improvements

## Quick Commands

| Question | Check |
|----------|-------|
| "What phase?" | Check artifact existence + Oracle convergence |
| "What's next?" | Identify next missing artifact or unconverged Oracle |
| "Is PRD ready?" | Validate PRD + check Oracle CONVERGED |
| "Can I start coding?" | Verify task graph exists + Oracle converged |
| "Ready to ship?" | Check gates pass |

## Recovery from Interruption

If workflow was interrupted:
1. Run `ls artifacts/` to see state
2. Check for partial Oracle outputs
3. Check Oracle convergence status
4. Identify last complete phase
5. Resume from next step

```bash
# See what exists
ls -la artifacts/

# Check Oracle status for each kind
for kind in prd ux plan code; do
  if [ -f "artifacts/06-oracle/$kind/issues.json" ]; then
    echo "=== $kind ==="
    cat "artifacts/06-oracle/$kind/issues.json" | jq '{
      total: .issues | length,
      blockers: [.issues[] | select(.severity == "blocker")] | length,
      majors: [.issues[] | select(.severity == "major")] | length,
      addressed: [.issues[] | select(.addressed == true)] | length
    }'
  fi
done

# Resume
# (run the next /command based on what's missing or not converged)
```

## Task Source Selection

When reaching the `code` phase, Ralph will prompt for task source:

```
╔═══════════════════════════════════════════════════════════════╗
║            SELECT TASK SOURCE                                 ║
╠═══════════════════════════════════════════════════════════════╣
║  [1] beads_rust (br) — Recommended for multi-agent swarms     ║
║  [2] task-graph.json — Built-in, no external deps             ║
╚═══════════════════════════════════════════════════════════════╝
```

Use `--beads` or `--no-beads` to skip interactive selection.
