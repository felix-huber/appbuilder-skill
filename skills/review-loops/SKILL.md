---
name: review-loops
description: Implements Doodlestein's iterative review methodology. Contains exact prompts for plan review, beads review, code review, bug hunting, and UI polish. Use when you need to iterate on any artifact until convergence.
triggers:
  - review
  - iterate
  - converge
  - bug hunt
  - polish
  - fresh eyes
  - check beads
  - review code
---

# Review Loops Skill (Doodlestein Methodology)

This skill implements Jeffrey Emanuel's (@doodlestein) iterative review methodology. The core insight: **planning tokens are 100x cheaper than debugging code**. Run reviews multiple times until they converge.

## CRITICAL: Iteration Counts

| Review Type | Minimum Passes | Stop Condition |
|-------------|----------------|----------------|
| Plan Review (GPT Pro) | 4-5 | No new architectural changes |
| Beads Review | 6-9 | No changes made |
| Code Review (post-impl) | 3+ | No bugs found |
| Bug Hunt | 2-3 | No bugs found |
| UI/UX Polish | 2-3 | No improvements identified |

**NEVER proceed after just 1 pass.** Even if the first pass looks clean, run at least the minimum.

---

## 1. PLAN REVIEW (ChatGPT Pro 5.2)

### The Killer Prompt (EXACT - from Doodlestein)

Run this in ChatGPT Pro with Extended Reasoning enabled:

```
Carefully review this entire plan for me and come up with your best
revisions in terms of better architecture, new features, changed features,
etc. to make it better, more robust/reliable, more performant, more
compelling/useful, etc.

For each proposed change, give me your detailed analysis and
rationale/justification for why it would make the project better along
with the git-diff style changes relative to the original markdown plan
shown below:

<PASTE PLAN HERE>
```

### Integration Prompt (in Claude Code)

After getting GPT Pro's response:

```
OK, now integrate these revisions to the markdown plan in-place;
use ultrathink and be meticulous. At the end, you can tell me which
changes you wholeheartedly agree with, which you somewhat agree with,
and which you disagree with:

```[Pasted GPT Pro output]```
```

### Iteration Pattern

```
Pass 1: Initial plan review → Get suggestions → Integrate
Pass 2: Review revised plan → Get suggestions → Integrate
Pass 3: Review revised plan → Get suggestions → Integrate
Pass 4: Review revised plan → Get suggestions → Integrate
Pass 5: Review revised plan → Usually stable by now
```

> "After four or five rounds of this, you tend to reach a steady-state where the suggestions become very incremental."

---

## 2. BEADS REVIEW (THE MOST IMPORTANT STEP!)

### Initial Creation Prompt

```
OK so now read ALL of [PLAN_FILE.md]; please take ALL of that and
elaborate on it and use it to create a comprehensive and granular set
of beads for all this with tasks, subtasks, and dependency structure
overlaid, with detailed comments so that the whole thing is totally
self-contained and self-documenting (including relevant background,
reasoning/justification, considerations, etc.-- anything we'd want
our "future self" to know about the goals and intentions and thought
process and how it serves the over-arching goals of the project.).

The beads should be so detailed that we never need to consult back
to the original markdown plan document.

Remember to ONLY use the `br` tool to create and modify the beads
and add the dependencies. Use ultrathink.
```

### Review Prompt (RUN 6-9 TIMES!)

This is the exact Doodlestein prompt. Run it repeatedly until no changes are made:

```
Reread AGENTS.md so it's still fresh in your mind.

Check over each bead super carefully-- are you sure it makes sense?
Is it optimal? Could we change anything to make the system work better
for users? If so, revise the beads.

It's a lot easier and faster to operate in "plan space" before we start
implementing these things!

DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY!

Also, make sure that as part of these beads, we include comprehensive
unit tests and e2e test scripts with great, detailed logging so we can
be sure that everything is working perfectly after implementation.

Remember to ONLY use the `br` tool to create and modify the beads and
to add the dependencies to beads. Use ultrathink.
```

### Tracking Iterations

Keep a log at `.beads/review-iterations.md`:

```markdown
# Beads Review Iterations

## Pass 1 (initial)
- Created 24 beads from plan
- Changes: N/A (initial creation)

## Pass 2
- Split 3 large tasks into smaller ones
- Added 2 missing test beads
- Changes: 5 beads modified, 2 added

## Pass 3
- Reordered dependencies for better parallelism
- Added implementation notes to 5 beads
- Changes: 5 beads modified

## Pass 4
- Minor description improvements
- Changes: 3 beads modified

## Pass 5
- Added edge case handling to 2 beads
- Changes: 2 beads modified

## Pass 6
- No changes (STABLE)
- CONVERGED ✓
```

---

## 3. FRESH EYES REVIEW (After Context Compaction)

When Claude Code compacts context or you want fresh perspective:

### Phase 1: Re-orient

```
First read ALL of the AGENTS.md file and README.md file super carefully
and understand ALL of both! Then use your code investigation agent mode
to fully understand the code, and technical architecture and purpose
of the project. Use ultrathink.
```

### Phase 2: Review Beads

```
We recently transformed a markdown plan file into a bunch of new beads.
I want you to very carefully review and analyze these using `br list`
and `br show <id>`.

With completely fresh eyes, check:
1. Does the overall architecture make sense?
2. Are there any gaps in the task coverage?
3. Are dependencies correctly ordered?
4. Could any tasks be parallelized better?
5. Are there any obvious issues I missed before?

Make any necessary corrections using ONLY the `br` tool.
```

---

## 4. CODE REVIEW (Post-Implementation)

### Self-Review Prompt (run after completing each bead)

```
Great, now I want you to carefully read over all of the new code you
just wrote and other existing code you just modified with "fresh eyes"
looking super carefully for any obvious bugs, errors, problems, issues,
confusion, etc.

Carefully fix anything you uncover. Use ultrathink.
```

**Keep running rounds of this until they stop finding bugs!**

### Cross-Agent Review Prompt (multi-agent setups)

```
Ok can you now turn your attention to reviewing the code written by
your fellow agents and checking for any issues, bugs, errors, problems,
inefficiencies, security problems, reliability issues, etc. and carefully
diagnose their underlying root causes using first-principle analysis
and then fix or revise them if necessary?

Don't restrict yourself to the latest commits, cast a wider net and go
super deep! Use ultrathink.
```

---

## 5. BUG HUNT (Random Code Exploration)

### The Bug Hunt Prompt

Run this 2-3 times or until no bugs found:

```
I want you to sort of randomly explore the code files in this project,
choosing code files to deeply investigate and understand and trace their
functionality and execution flows through the related code files which
they import or which they are imported by.

Once you understand the purpose of the code in the larger context of
the workflows, I want you to do a super careful, methodical, and critical
check with "fresh eyes" to find any obvious bugs, problems, errors, issues,
silly mistakes, etc. and then systematically and meticulously and
intelligently correct them.

Be sure to comply with ALL rules in AGENTS.md and ensure that any code
you write or revise conforms to the best practice guides referenced in
the AGENTS.md file. Use ultrathink.
```

---

## 6. UI/UX POLISH

### Standard Polish Prompt

```
Great, now I want you to super carefully scrutinize every aspect of
the application workflow and implementation and look for things that
just seem sub-optimal or even wrong/mistaken to you, things that could
very obviously be improved from a user-friendliness and intuitiveness
standpoint, places where our UI/UX could be improved and polished to
be slicker, more visually appealing, and more premium feeling and just
ultra high quality, like Stripe-level apps.
```

### Intensive Polish Prompt (for final pass)

```
I still think there are strong opportunities to enhance the UI/UX look
and feel and to make everything work better and be more intuitive,
user-friendly, visually appealing, polished, slick, and world class
in terms of following UI/UX best practices like those used by Stripe,
don't you agree?

And I want you to carefully consider desktop UI/UX and mobile UI/UX
separately while doing this and hyper-optimize for both separately to
play to the specifics of each modality.

I'm looking for true world-class visual appeal, polish, slickness, etc.
that makes people gasp at how stunning and perfect it is in every way.

Use ultrathink.
```

---

## 7. TEST COVERAGE CHECK

When all beads are complete:

```
Do we have full unit test coverage without using mocks/fake stuff?
What about complete e2e integration test scripts with great, detailed
logging?

If not, then create a comprehensive and granular set of beads for all
this with tasks, subtasks, and dependency structure overlaid with
detailed comments.
```

---

## 8. MULTI-MODEL BLENDING (Advanced)

When you have plans from multiple AI models (Gemini, Grok, Claude, GPT):

```
I asked 3 competing LLMs to do the exact same thing and they came up
with pretty different plans which you can read below.

I want you to REALLY carefully analyze their plans with an open mind
and be intellectually honest about what they did that's better than
your plan.

Then I want you to come up with the best possible revisions to your
plan (you should simply update your existing document for your original
plan with the revisions) that artfully and skillfully blends the
"best of all worlds" to create a true, ultimate, superior hybrid version
of the plan that best achieves our stated goals and will work the best
in real-world practice to solve the problems we are facing and our
overarching goals while ensuring the extreme success of the enterprise
as best as possible.

You should provide me with a complete series of git-diff style changes
to your original plan to turn it into the new, enhanced, much longer
and detailed plan that integrates the best of all the plans with every
good idea included.
```

---

## 9. SMART COMMIT

After completing work:

```
Now, based on your knowledge of the project, commit all changed files
now in a series of logically connected groupings with super detailed
commit messages for each and then push.

Take your time to do it right. Don't edit the code at all.
Don't commit obviously ephemeral files. Use ultrathink.
```

---

## CONVERGENCE DETECTION

A review has converged when:
- No new issues/bugs found
- No architectural changes suggested
- Only cosmetic/nit changes (if any)
- Reviewer says "no changes needed" or "looks good"

**Log every iteration.** If you're not tracking iterations, you're not doing Doodlestein.
