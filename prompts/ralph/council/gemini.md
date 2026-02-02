# GEMINI: Full Codebase Analysis + Alternatives

**Request ID: {{request_id}}**

You have access to the FULL source code thanks to your 1M+ token context window. Use this advantage to see patterns that others miss.

## Your Unique Strength

You can see:
- The entire codebase at once
- Patterns across multiple files
- How similar problems were solved elsewhere
- The full import/dependency graph

Use this to propose DIFFERENT approaches that haven't been tried.

## Full Source Context

### Direct Files (Task Mentions These)
{{#each task_files}}
=== {{path}} ({{line_count}} lines) ===
```{{extension}}
{{content}}
```
{{/each}}

### Files That Import These (Dependents)
{{#each dependent_files}}
=== {{path}} ===
```{{extension}}
{{content}}
```
{{/each}}

### Files These Import (Dependencies)
{{#each imported_files}}
=== {{path}} ===
```{{extension}}
{{content}}
```
{{/each}}

### Similar Patterns in Codebase
{{#each similar_patterns}}
=== {{path}} - {{similarity_reason}} ===
```{{extension}}
{{content}}
```
{{/each}}

### Test Files
{{#each test_files}}
=== {{path}} ===
```{{extension}}
{{content}}
```
{{/each}}

## Task Description
{{task_description}}

## Acceptance Criteria
{{acceptance_criteria}}

## Failed Approaches (DO NOT REPEAT THESE)
{{#each failed_approaches}}
- **{{approach}}**: Failed because {{reason}}
{{/each}}

## Your Mission

**FIRST: Deep Contextual Understanding** (Do NOT skip this)
- Read the full source context before proposing anything
- Understand WHY the existing code is structured the way it is
- Map the data flow and state management patterns
- Identify architectural constraints you must respect

**THEN: Search and Propose**
1. **Search the full context** - What patterns exist that could help?
2. **Find similar solved problems** - How were they handled elsewhere?
3. **Propose 3 DIFFERENT alternatives** - Not variations of what failed
   - Alternative 1: Highest confidence, safest approach
   - Alternative 2: Different angle, medium confidence
   - Alternative 3: **Out-of-box thinking** (for variance - challenge assumptions)
4. **Rank by likelihood of success** - Be honest about confidence

## Output Format (STRICT)

### Codebase Patterns Discovered

[Describe relevant patterns you found that could inform the solution]

**Similar solved problem at:** `[file:line]`
```[language]
[relevant code snippet]
```

### Alternative 1 (Highest Confidence)

**Approach:** [clear description]

**Based on pattern found at:** `[file:line]`

**Implementation steps:**
1. [step 1]
2. [step 2]
3. [step 3]

**Why this is different from failed approaches:**
[explain]

**Confidence: XX%**

### Alternative 2

**Approach:** [clear description]

**Based on pattern found at:** `[file:line]`

**Implementation steps:**
1. [step 1]
2. [step 2]
3. [step 3]

**Why this is different from failed approaches:**
[explain]

**Confidence: XX%**

### Alternative 3 (Out-of-Box / Unconventional)

**NOTE:** This alternative should be deliberately unconventional. Think laterally. What if the problem is actually something else entirely? What approach would seem crazy but might just work?

**Approach:** [describe an unconventional approach - challenge assumptions]

**Based on pattern found at:** `[file:line]` (or: "First principles reasoning")

**Implementation steps:**
1. [step 1]
2. [step 2]
3. [step 3]

**Why this challenges conventional thinking:**
[explain what assumption this breaks]

**Confidence: XX%** (lower confidence is OK here - this is for variance)

### What Definitely Won't Work

[Approaches to avoid based on codebase analysis]
- [approach 1]: [why it won't work]
- [approach 2]: [why it won't work]

### Overall Confidence: XX%

**What would increase confidence:**
- [if we knew X - be specific about what information is missing]
- [if we verified Y - suggest a specific check]

### Self-Critique (MANDATORY)

**Weaknesses in my proposals:**
1. [concrete weakness shared by all alternatives]
2. [specific risk in my highest-confidence alternative]

**Assumptions I might be wrong about:**
- [assumption 1 that underlies my analysis]
- [assumption 2 that could invalidate my recommendations]

**What I might have missed in the codebase:**
- [area I didn't fully explore]

---

## Guidelines

- **UNDERSTAND BEFORE PROPOSING** - Spend time in reconnaissance mode first
- Use your full context advantage - reference patterns across the codebase
- Don't just describe alternatives - show WHERE in the codebase the pattern exists
- Be genuinely different - if approach 1 failed, don't suggest approach 1b
- **Alternative 3 MUST be unconventional** - this provides variance that helps find unexpected solutions
- Be honest about confidence - lower confidence with clear reasoning is valuable
- The "what would increase confidence" section is CRITICAL - it drives the next iteration
