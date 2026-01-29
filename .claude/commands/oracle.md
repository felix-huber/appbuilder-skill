# /oracle — Run Oracle Review and Apply Feedback

## Goal
Run Oracle (GPT-5.2 Pro) convergence loop and **intelligently incorporate feedback** into the artifact.

---

## ⚠️ MANDATORY FIRST STEP — DO NOT SKIP ⚠️

**BEFORE doing ANYTHING else, run these commands to check existing state:**

```bash
# 1. What Oracle output already exists?
ls -la artifacts/06-oracle/<kind>/ 2>/dev/null || echo "No Oracle output yet"

# 2. What's the convergence state?
cat artifacts/06-oracle/<kind>/convergence-history.json 2>/dev/null || echo "No history"

# 3. Find latest feedback file
ls -t artifacts/06-oracle/<kind>/*.md 2>/dev/null | head -3

# 4. Check if feedback is newer than artifact
stat artifacts/06-oracle/<kind>/*.md 2>/dev/null | grep Modify | tail -1
stat artifacts/01-prd.md | grep Modify  # Use: 01-prd, 02-ux, 03-plan as needed
```

**Replace `<kind>` with: prd, ux, plan, or code**

---

## Decision Tree (FOLLOW THIS!)

After running the check commands above:

| Situation | Action |
|-----------|--------|
| No Oracle output exists | → Run Oracle |
| Oracle output exists, convergence-history shows 0 blockers + ≤2 majors | → **ALREADY DONE!** Report success, no action needed |
| Oracle output exists, feedback NOT applied (oracle files newer than artifact) | → **APPLY FEEDBACK FIRST**, then check if more rounds needed |
| Oracle output exists, feedback applied, still has blockers/majors | → Run another Oracle round |

**Signs that feedback was NOT applied:**
- Oracle .md files have newer timestamps than the artifact
- No `<!-- Oracle Round N applied -->` comments in artifact
- Issues from Oracle output still present in artifact

**If unapplied feedback exists:** Read it, apply fixes to the artifact, THEN decide if another Oracle run is needed.

---

## STEP 1: RUN ORACLE (only if needed per decision tree above)

**Execute the Oracle convergence script directly. DO NOT print commands for the user to run.**

```bash
# Run this directly — takes 60-90 minutes, DO NOT TIMEOUT
./scripts/oracle_converge.sh <kind> <primary_file> [context_files...]

# Examples:
./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
./scripts/oracle_converge.sh ux artifacts/02-ux.md artifacts/01-prd.md
./scripts/oracle_converge.sh plan artifacts/03-plan.md artifacts/01-prd.md artifacts/02-ux.md
```

**The script now auto-resumes:**
- Detects previous rounds from `convergence-history.json`
- Skips if already converged
- Resumes from last round if interrupted

**Expected timeline:**
- Script starts → immediate output
- Browser opens → GPT-5.2 Pro starts
- **30-60 minutes of silence** → this is normal (extended thinking)
- Response streams → output file created
- Apply feedback → run again until converged

## Retry Logic (Built Into Script)

The script has 3 retries with backoff. Only if ALL fail, offer manual fallback:
```
⚠️ Oracle automation failed after 3 attempts. 

Manual fallback - run in terminal:
  npx -y @steipete/oracle --render --copy-markdown \
    --engine browser \
    --browser-manual-login \
    --browser-no-cookie-sync \
    --model gpt-5.2-pro \
    --prompt "$(cat prompts/prd/product.txt)" \
    --file artifacts/01-prd.md --file artifacts/00-brief.md

Then paste into ChatGPT (GPT-5.2 Pro) and save response to:
  artifacts/06-oracle/prd/[timestamp]_product.md
```

## Key Principle: Critical Evaluation of External Feedback

When incorporating feedback from another LLM (GPT-5.2 Pro), you must:

1. **Evaluate each piece of feedback critically** — Don't blindly apply everything
2. **Consider context the reviewer may have missed** — You have full project context
3. **Preserve intentional design decisions** — Some "issues" may be deliberate choices
4. **Synthesize conflicting suggestions** — Find the best path forward
5. **Run fresh-eyes review after edits** — Catch any issues introduced by changes

## Syntax
```
/oracle <kind>
```
Where `<kind>` is: `prd`, `ux`, `plan`, or `code`

## Process

### Step 1: Load Oracle Output

Find the latest Oracle output in:
```
artifacts/06-oracle/<kind>/*.md
artifacts/06-oracle/<kind>/issues*.json
```

### Step 2: Parse and Categorize Feedback

The Oracle output now includes:
- **Issues** (blockers, majors, minors, nits)
- **Suggestions** (improvements, simplifications, best practices)
- **Strengths** (what to preserve)
- **Overall Assessment** (readiness score)

### Step 3: Triage Issues

For each ISSUE, evaluate:

```
┌─────────────────────────────────────────────────────────────┐
│ ISSUE TRIAGE CHECKLIST                                      │
├─────────────────────────────────────────────────────────────┤
│ □ Is this a genuine problem or a misunderstanding?          │
│ □ Was this intentionally designed this way? Why?            │
│ □ Does the evidence cited actually support the concern?     │
│ □ Is the recommendation concrete and actionable?            │
│ □ Does fixing this break something else?                    │
│ □ Is the severity rating accurate?                          │
└─────────────────────────────────────────────────────────────┘
```

**Downgrade or dismiss issues that:**
- Are based on misreading the document
- Were already addressed elsewhere
- Conflict with explicit project constraints
- Are stylistic preferences disguised as "major" issues

**Escalate issues that:**
- Reveal genuine implementation blockers
- Point to missing critical information
- Identify security or data loss risks

### Step 4: Evaluate Suggestions

Suggestions are **not** issues — they're opportunities. For each suggestion:

1. **Does this add genuine value?** (not just complexity)
2. **Does it align with project goals?** (check brief)
3. **Is it feasible within scope?** (check constraints)
4. **What's the cost/benefit?** (time to implement vs value)

Apply suggestions that:
- Simplify implementation
- Improve testability
- Enhance user experience
- Follow proven best practices

Defer suggestions that:
- Add scope beyond v1
- Require significant rework
- Have unclear benefits

### Step 5: Apply Changes

For each accepted issue/suggestion:

```markdown
<!-- 
Oracle Round N - Applied:
- Issue: [title] → [what we changed]
- Suggestion: [title] → [what we added]
- Dismissed: [title] → [why not applicable]
-->
```

**Apply changes systematically:**
1. Address all BLOCKER issues first
2. Address MAJOR issues
3. Apply high-priority suggestions
4. Run self-review to check consistency
5. Update any dependent sections affected by changes

### Step 6: Fresh Eyes Review (CRITICAL)

After applying changes, do a fresh-eyes review:

```
Read through the entire modified artifact as if seeing it for the first time.
Check for:
- Contradictions introduced by edits
- Broken cross-references
- Inconsistent terminology
- Gaps created by changes
- Duplicated or conflicting information
```

If issues found, fix them before reporting.

### Step 7: Report Results

```
╔═══════════════════════════════════════════════════════════════╗
║                 ORACLE FEEDBACK INCORPORATED                  ║
╠═══════════════════════════════════════════════════════════════╣
║  From Oracle:                                                 ║
║    Blockers: 0 → Applied: 0, Dismissed: 0                    ║
║    Majors:   3 → Applied: 2, Dismissed: 1 (reason)           ║
║    Minors:   5 → Applied: 3, Deferred: 2                     ║
║    Suggestions: 4 → Applied: 2, Deferred: 2                  ║
╠═══════════════════════════════════════════════════════════════╣
║  Fresh-eyes check: ✅ No issues introduced                    ║
║  Artifact updated: artifacts/01-prd.md                        ║
╚═══════════════════════════════════════════════════════════════╝

📍 Return to terminal and press ENTER to continue convergence loop.
```

## Handling Repeated Feedback

If Oracle raises the same issue again after you've addressed it:

1. **Check if your fix was incomplete** — Maybe you missed part of the concern
2. **Check if the fix introduced a new form of the problem** — Shifted rather than solved
3. **Add explicit documentation** — Sometimes the reviewer needs more context
4. **Dismiss with clear rationale** — If it's a false positive, note why

Add to the artifact:
```markdown
<!-- 
DESIGN DECISION: [topic]
We chose [approach] because [rationale].
Alternative considered: [what Oracle suggested]
Why not: [specific reason]
-->
```

This helps future Oracle passes understand the decision was intentional.

## File Locations

| Kind | Artifact | Oracle Output |
|------|----------|---------------|
| prd | artifacts/01-prd.md | artifacts/06-oracle/prd/ |
| ux | artifacts/02-ux.md | artifacts/06-oracle/ux/ |
| plan | artifacts/03-plan.md | artifacts/06-oracle/plan/ |
| code | src/**/*.ts | artifacts/06-oracle/code/ |

## Anti-Patterns

❌ Blindly applying all feedback without evaluation
❌ Dismissing feedback without understanding it
❌ Making changes that contradict project constraints
❌ Skipping fresh-eyes review after edits
❌ Not documenting why feedback was dismissed
