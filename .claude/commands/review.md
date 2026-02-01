# /review — Run Iterative Review Loops (Doodlestein Methodology)

## Goal
Run the specified review type multiple times until convergence, tracking iterations.

## Syntax
```
/review <type> [--passes N]
```

Where `<type>` is one of:
- `plan` — Review session plan in tasks/todo.md (run 2-3 times)
- `beads` — Review beads structure and content (run 6-9 times)
- `code` — Fresh eyes code review (run until no bugs)
- `bugs` — Random code exploration bug hunt (run 2-3 times)
- `ux` — UI/UX polish review (run 2-3 times)
- `tests` — Test coverage verification
- `cross` — Cross-agent code review (multi-agent only)

## Default Pass Counts

| Type | Default Passes | Stop Condition |
|------|----------------|----------------|
| plan | 2 | No gaps found |
| beads | 6 | No changes made |
| code | 3 | No bugs found |
| bugs | 3 | No bugs found |
| ux | 2 | No improvements |
| tests | 1 | Coverage verified |
| cross | 2 | No issues found |

## Process

### 1. Initialize tracking
Create or update iteration log:
```bash
# For beads
cat >> .beads/review-iterations.md << EOF
## Review Session: $(date -Iseconds)
Type: $TYPE
EOF

# For code
cat >> artifacts/review-log.md << EOF
## Review Session: $(date -Iseconds)  
Type: $TYPE
EOF
```

### 2. Run review passes
For each pass:

1. Load the appropriate prompt from `prompts/review/<type>.txt`
2. Execute the review
3. Log results:
   ```
   ### Pass N
   - Changes made: [count]
   - Issues found: [list]
   - Status: [continuing|converged]
   ```
4. Check convergence:
   - If "no changes" or "no issues" → CONVERGED
   - If max passes reached → WARN and stop
   - Otherwise → continue to next pass

### 3. Report results
```
╔═══════════════════════════════════════════════════════════════╗
║                    REVIEW COMPLETE                            ║
╠═══════════════════════════════════════════════════════════════╣
║  Type:        beads                                           ║
║  Passes:      6                                               ║
║  Status:      CONVERGED ✓                                     ║
║  Changes:     14 total (Pass 1-5), 0 (Pass 6)                 ║
╚═══════════════════════════════════════════════════════════════╝
```

## Examples

### Beads Review (full iteration)
```
/review beads
```
Output:
```
Starting beads review (target: 6+ passes until stable)...

Pass 1: 5 beads modified, 2 added
Pass 2: 3 beads modified  
Pass 3: 2 beads modified
Pass 4: 1 bead modified
Pass 5: 1 bead modified
Pass 6: No changes made

CONVERGED after 6 passes ✓
```

### Bug Hunt
```
/review bugs --passes 3
```
Output:
```
Starting bug hunt (target: 3 passes or until clean)...

Pass 1: Explored 12 files, found 3 bugs, fixed 3
Pass 2: Explored 8 files, found 1 bug, fixed 1
Pass 3: Explored 10 files, no bugs found

CONVERGED after 3 passes ✓
```

### Code Review (after implementation)
```
/review code
```
Output:
```
Starting fresh eyes code review...

Pass 1: Found 2 issues, fixed 2
Pass 2: Found 1 issue, fixed 1
Pass 3: No issues found

CONVERGED after 3 passes ✓
```

### Plan Review (before implementation)
```
/review plan
```
Output:
```
Reviewing current plan in tasks/todo.md...

Pass 1:
- Plan is too vague for step 2
- Missing error handling consideration
- Revised: Added specifics

Pass 2: Plan looks solid. Ready to implement.

CONVERGED after 2 passes ✓
```

## Integration with Workflow

### After Plan Review
```
/plan              # Generate plan
/oracle plan       # External review (iterate until converged)
/review beads      # Internal beads review (6-9 passes)
```

### After Implementation
```
./scripts/ralph.sh 50   # Execute tasks
/review code            # Fresh eyes review
/review bugs            # Bug hunt
/review ux              # UI polish
/review tests           # Verify coverage
```

### Multi-Agent
```
/review cross     # Agents review each other's code
```

## Prompts Used

All prompts are in `prompts/review/`:
- `plan_review.txt` — Session plan review
- `beads_review.txt` — Beads structure review
- `fresh_eyes.txt` — Code self-review
- `bug_hunt.txt` — Random exploration bug hunt
- `ux_polish.txt` — UI/UX quality review
- `test_coverage.txt` — Test completeness check
- `cross_agent.txt` — Multi-agent code review

## Critical Notes

1. **DO NOT SKIP ITERATIONS** — Even if pass 1 looks clean, run the minimum
2. **Log everything** — Iteration tracking is essential for methodology
3. **Converge before proceeding** — Don't move to next phase until stable
4. **"ultrathink"** — Use extended reasoning mode when available
5. **Fresh eyes** — After context compaction, re-read CLAUDE.md first
