---
name: phase-transitions
description: Contains the actual prompts and iteration requirements for each workflow phase. Use these prompts directly - they are the exact prompts that produce high-quality results.
triggers:
  - phase transition
  - transform
  - next phase
  - review artifact
  - self review
  - iterate
  - converge
  - fresh eyes
  - beads review
  - stuck
  - sideways
  - re-plan
  - not working
---

# Phase Transitions Skill

**CRITICAL**: This skill contains the exact prompts to use at each phase. These are not documentation - they are the actual prompts that should be executed. Copy and use them directly.

## The Core Insight

> "Planning tokens are a lot fewer and cheaper than implementation tokens. Even a very big, complex markdown plan is shorter than a few substantive code files. The models are far smarter when reasoning about a plan that fits in context."
> — Jeffrey Emanuel

**Time Distribution**: 85% planning, 15% implementation

---

## ITERATION REQUIREMENTS (NON-NEGOTIABLE)

| Phase | Iterations Required | Convergence Criteria |
|-------|--------------------|-----------------------|
| Plan review | 4-5 passes | Suggestions become incremental |
| Beads review | 6-9 passes | No more changes |
| Fresh eyes code review | Until stable | No bugs found |
| Oracle review | Until converged | 0 new blockers/majors |

---

## PHASE 1: PLAN CREATION (Multi-Model)

### Step 1a: Initial Creative Plan (ChatGPT Pro Extended Thinking)

```
I have a great idea for this project and need a spectacularly brilliant,
creative, clever, comprehensive, accretive plan for architecting, designing,
and implementing this system in a harmonious, cohesive, coherent way.

## Project Description
[PASTE YOUR BRIEF/PRD HERE]

## Requirements

Please create a plan that includes:

1. **System Architecture**
   - Components and their interactions
   - Data flow diagrams  
   - API design
   - Security considerations

2. **Implementation Strategy**
   - Phased approach (SPRINTS with DEMOABLE milestones)
   - Dependencies between phases
   - Risk mitigation

3. **Technical Decisions**
   - Technology stack with rationale
   - Trade-offs considered
   - Alternative approaches rejected and why

4. **Task Breakdown**
   - Granular tasks (1-4 hours each)
   - Effort estimates
   - Critical path

Make sure your plan is:
- Super detailed, granular, and comprehensive
- World-class UI/UX and polish  
- Self-contained and self-documenting
- Including relevant background, reasoning/justification, considerations
- Anything we'd want our "future self" to know
```

### Step 1b: Critical Review (Claude Opus)

```
Please review this plan critically and:

1. **Identify weaknesses or gaps**
2. **Suggest improvements**
3. **Add missing considerations**
4. **Enhance technical depth**
5. **Propose alternative approaches where beneficial**

Then produce an enhanced version of the plan that incorporates your improvements.

[PASTE CHATGPT PLAN HERE]
```

### Step 1c: Final Synthesis (ChatGPT Pro again)

```
Please synthesize this into a final, comprehensive plan that:

1. **Resolves any contradictions**
2. **Prioritizes the best ideas**
3. **Creates a clear execution roadmap**
4. **Is ready for transformation into beads**

[PASTE CLAUDE ENHANCED PLAN HERE]
```

### Step 1d: Iterative Improvement (REPEAT 4-5 TIMES!)

```
Carefully review this entire plan for me and come up with your best
revisions in terms of better architecture, new features, changed features,
etc. to make it better, more robust/reliable, more performant, more
compelling/useful, etc.

For each proposed change, give me your detailed analysis and
rationale/justification for why it would make the project better along
with the git-diff style changes relative to the original markdown plan
shown below:

[PASTE CURRENT PLAN]
```

After receiving suggestions, integrate them:

```
OK, now integrate these revisions to the markdown plan in-place;
use ultrathink and be meticulous. At the end, you can tell me which
changes you wholeheartedly agree with, which you somewhat agree with,
and which you disagree with:

[PASTE REVIEW OUTPUT]
```

**Keep iterating until suggestions become very incremental (usually 4-5 rounds).**

---

## PHASE 2: PLAN → BEADS (THE CRITICAL TRANSFORMATION)

### Initial Beads Creation Prompt

```
OK so now read ALL of [PLAN_FILE]; please take ALL of that and
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

### Beads Review Prompt (RUN 6-9 TIMES!)

```
Reread AGENTS.md (or CLAUDE.md) so it's still fresh in your mind.

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

**Run this prompt 6-9 times until it stops making changes!**

> "I used to only run that once or twice before starting implementation, 
> but I experimented recently with running it 6+ times, and it kept 
> making useful refinements."

### Fresh Eyes Review (After Compaction or New Session)

```
First read ALL of the AGENTS.md (or CLAUDE.md) file and README.md file super carefully
and understand ALL of both! Then use your code investigation agent mode
to fully understand the code, and technical architecture and purpose
of the project. Use ultrathink.

We recently transformed a markdown plan file into a bunch of new beads.
I want you to very carefully review and analyze these using `br` and `bv`.
```

---

## PHASE 3: IMPLEMENTATION

### Agent Init Prompt (Send to ALL agents)

```
First read ALL of the AGENTS.md (or CLAUDE.md) file and README.md file super carefully
and understand ALL of both!

Then use your code investigation agent mode to fully understand the code,
and technical architecture and purpose of the project.

When you're not sure what to do next, use the bv tool (or br ready)
to prioritize the best beads to work on next; pick the next one that you
can usefully work on and get started.

Use ultrathink.
```

### Fresh Eyes Code Review (AFTER EVERY BEAD COMPLETION!)

```
Great, now I want you to carefully read over all of the new code you
just wrote and other existing code you just modified with "fresh eyes"
looking super carefully for any obvious bugs, errors, problems, issues,
confusion, etc.

CRITICAL: Check integration! Trace the user flow end-to-end:
- How does a user actually trigger this feature?
- Is your new hook/component/util actually called from somewhere?
- Creating code is NOT enough - it must be wired into the existing UI/API.

Carefully fix anything you uncover. Use ultrathink.
```

**Keep running this until no more bugs are found!**

### Next Bead Prompt

```
Reread AGENTS.md (or CLAUDE.md) so it's still fresh in your mind. Use ultrathink.

Use `br ready --json` to find the most impactful bead(s) to work on next
and then start on it.

Remember to mark the beads appropriately:
- br update <id> --status in_progress  (when starting)
- br close <id> --reason "..."         (when done)
```

---

## PHASE 4: REVIEW & CLEANUP

### Cross-Agent Review (Different Model Perspective)

```
Ok can you now turn your attention to reviewing the code written by
your fellow agents and checking for any issues, bugs, errors, problems,
inefficiencies, security problems, reliability issues, etc. and carefully
diagnose their underlying root causes using first-principle analysis
and then fix or revise them if necessary?

Don't restrict yourself to the latest commits, cast a wider net and go
super deep! Use ultrathink.
```

### Random Code Exploration (Bug Hunt)

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

Be sure to comply with ALL rules in AGENTS.md (or CLAUDE.md) and ensure that any code
you write or revise conforms to the best practice guides referenced in
that file. Use ultrathink.
```

### Test Coverage Check

```
Do we have full unit test coverage without using mocks/fake stuff?
What about complete e2e integration test scripts with great, detailed
logging?

If not, then create a comprehensive and granular set of beads for all
this with tasks, subtasks, and dependency structure overlaid with
detailed comments.
```

### UI/UX Polish (Run multiple times)

```
Great, now I want you to super carefully scrutinize every aspect of
the application workflow and implementation and look for things that
just seem sub-optimal or even wrong/mistaken to you, things that could
very obviously be improved from a user-friendliness and intuitiveness
standpoint, places where our UI/UX could be improved and polished to
be slicker, more visually appealing, and more premium feeling and just
ultra high quality, like Stripe-level apps.

I want you to carefully consider desktop UI/UX and mobile UI/UX
separately while doing this and hyper-optimize for both separately to
play to the specifics of each modality.

I'm looking for true world-class visual appeal, polish, slickness, etc.
that makes people gasp at how stunning and perfect it is in every way.

Use ultrathink.
```

---

## MULTI-MODEL REVIEW ENSEMBLE

When you want multiple perspectives on a plan or architecture:

### Architecture Review Ensemble

| Model | Reasoning Mode | Prompt Suffix |
|-------|---------------|---------------|
| ChatGPT Pro | Systems Thinking | "What feedback loops and emergent behaviors exist?" |
| Claude Opus | Adversarial | "How could this architecture fail?" |
| Gemini | Constraint Analysis | "What constraints are violated or at risk?" |
| GPT-4 | Deductive | "What must be true given our requirements?" |

### Usage

For each model, add the reasoning mode to the review prompt:

```
Review this plan using [REASONING MODE] analysis:
- [SPECIFIC QUESTION FOR THAT MODE]

[PASTE PLAN]
```

Then synthesize:

```
I asked 3 competing LLMs to do the exact same thing and they came up
with pretty different plans which you can read below.

I want you to REALLY carefully analyze their plans with an open mind
and be intellectually honest about what they did that's better than
your plan.

Then I want you to come up with the best possible revisions to your
plan that artfully and skillfully blends the "best of all worlds"
to create a true, ultimate, superior hybrid version.

[PASTE ALL MODEL OUTPUTS]
```

---

## TRACKING ITERATIONS

Add to the top of each artifact:

```markdown
<!-- 
ITERATION LOG
=============
- v1: Initial generation (ChatGPT Pro)
- v2: Claude Opus review integration  
- v3: ChatGPT Pro synthesis
- v4: Self-review pass 1 - fixed X
- v5: Self-review pass 2 - fixed Y
- v6: Self-review pass 3 - no changes (STABLE)
- v7: Oracle review pass 1 - 8 issues
- v8: Oracle review pass 2 - 3 issues
- v9: Oracle review pass 3 - 0 issues (CONVERGED)
-->
```

For beads:

```bash
# Create .beads/iteration-log.md
echo "## Beads Review Iterations

- Pass 1: Created 24 beads from plan
- Pass 2: Split 3 large tasks, added 2 missing tests
- Pass 3: Reordered dependencies for better parallelism
- Pass 4: Added implementation notes to 5 beads  
- Pass 5: Minor description improvements
- Pass 6: No changes (STABLE)" > .beads/iteration-log.md
```

---

## RECOVERY: RE-PLAN WHEN SIDEWAYS

When implementation goes wrong, don't push through. Stop and re-plan.

### Detection Signals
- Tests keep failing unexpectedly
- Implementation feels hacky
- Scope is expanding
- You're unsure which direction to go
- Same bug keeps coming back

### Recovery Prompt

```
STOP. Things are going sideways.

1. What was the original goal?
2. What's actually happening?
3. Where did it diverge?
4. What's the root cause?

Before continuing, create a new plan:
- Write to tasks/todo.md
- Document the lesson in tasks/lessons.md
- Only proceed when the new plan is clear
```

### Document the Lesson

Always add to `tasks/lessons.md`:
```markdown
## [YYYY-MM-DD] - Recovery

**Mistake:** What went wrong

**Pattern:** The underlying pattern that caused it

**Rule:** The rule to prevent it

**Files affected:** Where to apply this rule
```

---

## THE KEY INSIGHT

> "Measure twice, cut once!" → **"Check your beads N times, implement once!"**

Planning and reviewing in "plan space" is:
- 100x cheaper (fewer tokens)
- 10x faster (no build/test cycles)
- Much higher quality (easier to reason about)

**DO NOT SKIP ITERATIONS. The extra planning time pays massive dividends during implementation.**
