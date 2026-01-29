# /retro — Capture Learnings and Process Updates

## Goal
Capture what worked, what didn't, and update templates/prompts for future projects.

## Prerequisites
- Project shipped (or at significant milestone)
- `artifacts/06-oracle/*/issues.json` files exist (Oracle ran at least once)

## Output
- `artifacts/09-retro.md`

## Steps

### 1. Gather data
Read through:
- All artifact files (00-08)
- Oracle issues across phases
- Git history / PR comments
- Any incident reports

### 2. Generate retrospective

Create `artifacts/09-retro.md`:

````markdown
# 09 — Retrospective

**Project**: [name]
**Date**: [date]
**Duration**: [start] → [end]

---

## Summary

- **Planned tasks**: X
- **Completed tasks**: Y
- **Oracle issues found**: Z
- **Blockers encountered**: N

---

## What Went Well

### Planning Phase
- Brief was comprehensive, reduced back-and-forth later
- UX state matrix caught edge cases early

### Oracle Reviews
- Security lens found XSS vulnerability before code
- Simplicity lens helped avoid over-engineering auth

### Execution
- Swarm parallelization saved ~2 days
- Worker boundaries were clean, no cross-cutting bugs

### Tooling
- Tasteboard helped align on design direction quickly
- Task graph dependencies prevented integration issues

---

## What Went Poorly

### Planning Phase
- Underestimated complexity of [feature]
- Missed [edge case] in PRD

### Oracle Reviews
- Performance lens suggested premature optimization
- Had to re-run oracle 3x due to browser automation issues

### Execution
- Teammate stuck on task #7 for 4 hours (too large)
- E2E tests were flaky, wasted debug time

### Tooling
- Design gallery didn't render on Firefox
- Task graph compiler missed some dependency edges

---

## Oracle Analysis

### What Oracle Caught
| Phase | Issue | Impact |
|-------|-------|--------|
| PRD | Missing error state for offline | Avoided user confusion |
| UX | Accessibility gap in form | Passed audit |
| PLAN | SQL injection risk | Prevented vulnerability |

### What Oracle Missed
| Phase | Issue Found Later | Why Missed? |
|-------|-------------------|-------------|
| PLAN | Race condition in worker | Needed code context |
| CODE | Memory leak in listener | Runtime-only issue |

### Oracle Accuracy
- **Useful issues**: 85%
- **False positives**: 10%
- **Missed issues**: 5%

### Lens Effectiveness
| Lens | Useful | Noise |
|------|--------|-------|
| security | ★★★★★ | Low |
| architecture | ★★★★☆ | Medium |
| performance | ★★★☆☆ | High |
| simplicity | ★★★★☆ | Low |
| tests | ★★★★☆ | Medium |
| product | ★★★☆☆ | Medium |
| ux | ★★★★☆ | Low |
| ops | ★★★☆☆ | Medium |

---

## Process Changes

### Start Doing
- Run `/oracle plan` before task compilation (caught issues earlier)
- Use tasteboard even for non-UI projects (clarifies direction)

### Stop Doing
- Running all 8 lenses for CODE phase (diminishing returns)
- Creating tasks > 4 hours (always split)

### Keep Doing
- Brief → PRD → UX → PLAN flow (worked well)
- Oracle reviews at each phase transition
- Swarm parallelization for independent tasks

### Experiment Next Time
- Try `/deepen-plan` from Compound Engineering
- Run Oracle with multiple models (`--models gpt-5.2-pro,claude-4.5-sonnet`)

---

## Template Updates

Based on this retro, update these templates:

### PRD Template (`templates/PRD.template.md`)
- Add: "Offline behavior" section
- Add: "Error recovery" for each story

### UX Template (`templates/UX.template.md`)
- Add: "Skeleton states" to state matrix
- Add: "Reduced motion" to accessibility

### PLAN Template (`templates/PLAN.template.md`)
- Add: "Task size check" reminder
- Add: "Worker error boundaries" section

---

## Prompt Updates

Based on Oracle effectiveness, update these prompts:

### `prompts/plan/performance.txt`
- Add: "Avoid suggesting optimizations without evidence of bottleneck"
- Add: "Prefer measurable recommendations"

### `prompts/code/security.txt`
- Add: "Check for event listener cleanup"
- Add: "Validate worker message origins"

---

## Metrics Comparison

| Metric | This Project | Previous Avg | Delta |
|--------|--------------|--------------|-------|
| Planning time | 2 days | 3 days | -33% |
| Oracle issues found | 24 | 18 | +33% |
| Post-ship bugs | 2 | 5 | -60% |
| Total duration | 8 days | 12 days | -33% |

---

## Action Items

- [ ] Update PRD template with offline section
- [ ] Fix design gallery Firefox rendering
- [ ] Add task size warning to compiler
- [ ] Create custom lens for [domain-specific concern]

---

## Team Feedback

> "Oracle security lens is a must-have now" — Dev A

> "Tasteboard saved hours of design debates" — Designer B

> "Swarm status helped me stay aware of blockers" — Dev C
````

### 3. Apply updates
Actually update the files mentioned:

```bash
# Update templates
# (make the edits to templates/*.md)

# Update prompts
# (make the edits to prompts/*/*.txt)
```

### 4. Commit learnings
```bash
git add templates/ prompts/ artifacts/09-retro.md
git commit -m "chore: retro learnings from [project]"
```

### 5. Save
Write to `artifacts/09-retro.md`.

## Next project
Learnings are now embedded in templates and prompts.
Future `/brief`, `/prd`, `/ux`, `/plan` will benefit automatically.
