# Claude Code Instructions — Oracle Swarm Extension

This extension adds artifact-driven workflows with GPT-5.2 Pro review loops to Compound Engineering.

## When Working With Me

- Be concise, skip obvious explanations
- Just make the fix, don't ask permission for small changes
- If something's unclear, make a reasonable assumption and note it
- **After starting/restarting the dev server**, always smoke test: wait for ready, curl the homepage, then agent-browser open key pages affected by recent changes

## CRITICAL RULES

### Rule 1: Never Delete Files Without Permission
You may NOT delete files without explicit permission. Even files you created (test files, temp files). Ask first, always.

### Rule 2: No File Proliferation
AVOID uncontrolled proliferation of code files. If you want to change something or add a feature, you MUST revise the existing code file in place.

**NEVER create:**
- `file_v2.js`
- `file_improved.js`
- `file_enhanced.js`
- `file_unified.js`
- `file_new.js`

New files are reserved for GENUINELY NEW FUNCTIONALITY that makes zero sense to include in any existing file. It should be an INCREDIBLY high bar to ever create a new code file.

### Rule 3: No Automated Code Transforms
NEVER run a script that processes/changes code files in this repo. That sort of brittle, regex-based stuff is always a disaster. DO NOT BE LAZY. Make code changes manually, even when there are many instances to fix. If changes are many but simple, use several subagents in parallel.

### Rule 4: Simplicity Check
**Before committing any code, ask yourself:**
> "Would a senior engineer say this is overcomplicated? If yes, simplify."

Look for:
- Abstractions not needed yet (YAGNI)
- Multiple patterns where one would suffice
- Premature optimization
- Over-engineered solutions for simple problems

## Non-negotiables

1. **Browser Oracle only**: Never use Oracle API mode. If you can run the CLI locally, do it; otherwise instruct the human to run it.
2. **Artifacts are truth**: The `artifacts/` directory is the source of truth. Update artifacts before touching code.
3. **No evidence = not done**: Every task completion must include commands run + outputs or screenshots.
4. **Task graph is truth**: Work is tracked via compiled task graph or beads with explicit dependencies.
5. **Clean shutdown**: For swarms, use requestShutdown → approvals → cleanup.
6. **ITERATE UNTIL CONVERGENCE**: Oracle reviews and self-reviews must run multiple times.
7. **Backpressure required**: Tasks must include verification commands and/or LLM subjective checks. No verification = task fails unless explicitly allowed.

## CRITICAL: Iteration Requirements

Based on the Doodlestein methodology, **planning tokens are 100x cheaper than fixing code bugs**:

| Phase | Minimum Iterations |
|-------|-------------------|
| Plan review (Oracle) | 4-5 passes until stable |
| Plan → Beads review | 6-9 passes until no changes |
| Code review (Oracle) | Until 0 new blockers/majors |
| Any self-review | Until stable (no changes) |

**DO NOT SKIP ITERATIONS.** See `skills/phase-transitions/SKILL.md` for detailed prompts.

---

## Note for Codex/GPT-5.2

If you are Codex or GPT-5.2 (or any non-Claude agent): another agent (often Claude Code) may have made changes to the working tree since you last saw it. Before assuming your mental model of the code is correct:

```bash
git status              # See uncommitted changes
git log --oneline -5    # See recent commits
```

Re-read any files you plan to modify. This prevents you from overwriting another agent's work or making edits based on stale context.

---

## Manual Oracle Rule (IMPORTANT)

### ⚠️ ALWAYS CHECK EXISTING STATE FIRST

Before running any Oracle command, check what already exists:

```bash
ls -la artifacts/06-oracle/<kind>/ 2>/dev/null
cat artifacts/06-oracle/<kind>/convergence-history.json 2>/dev/null
```

**Decision:**
- Already converged? → Done, no action needed
- Unapplied feedback? → Apply it first
- No output? → Run Oracle

### Running Oracle

When the workflow requires Oracle, **run it directly**:

```bash
./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
```

The script will:
- Auto-open Chromium
- Run GPT-5.2 Pro review (30-90 min per pass)
- Iterate until convergence (0 blockers/majors)
- Write output to `artifacts/06-oracle/`
- **Auto-resume** if interrupted (reads convergence-history.json)

If you cannot run commands locally, instruct the human to run this. Otherwise, run it yourself.

---

## Task Management Options

### Option 1: beads_rust (br) — Recommended for Autonomous Execution

```bash
# Install
cargo install --git https://github.com/Dicklesworthstone/beads_rust.git

# Generate beads from task graph
node scripts/generate_beads_setup.js
bash artifacts/04-beads-setup.sh

# IMPORTANT: Run beads review prompt 6-9 times!
# See skills/phase-transitions/SKILL.md

# Execute with smart routing (default)
./scripts/ralph.sh --beads 50
```

### Option 2: task-graph.json — Built-in, No External Deps

```bash
# Compile task graph
node scripts/compile_task_graph.js

# Execute
./scripts/ralph.sh 50
```

### Option 3: Strict Mode — Enforced Backpressure + Cross-Model Review

```bash
# Full loop with cross-model review (beads)
./scripts/ralph.sh --beads --tool claude --review-tool codex --strict 50

# Full loop with TDD enforcement (task graph)
./scripts/ralph.sh --strict --require-tests 50

# Limit to 15 tasks with continue-on-error
./scripts/ralph.sh --beads --max-tasks 15 --continue-on-error 50
```

**Backpressure rules (Ralph strict mode):**
- Tasks must define `verification` commands.
- Optional `llmVerification` can be used for subjective checks.
- Defaults for non-Node repos:
  - `verification.txt` at repo root, or
  - `RALPH_DEFAULT_VERIFY` env var, or
  - `--default-verify "<cmds>"`.
- LLM-only verification is allowed if no commands exist, but it must pass.

---

## Ralph Agent Roles (Behavior Expectations)

**Implementer**
- Reads task, allowed paths, verification, and LLM checks.
- Implements ONE task; adds required tests.
- Runs task verification + build verification before claiming completion.
- Does NOT commit; Ralph handles commits/PRs.

**Reviewer**
- Fresh context; output `NO_ISSUES_FOUND` or `[P1|P2|P3]` issues with file:line.
- Prioritize correctness, regressions, and test quality.

**LLM Judge (Subjective)**
- Output `LLM_PASS` or `LLM_FAIL` with 1-line reason.
- Fail if criteria cannot be verified from diff/changes.

**Council Subagents**
- Analyst: correctness/architecture/perf risks
- Sentinel: anti-patterns, security, test cheating
- Designer: UI/UX polish, accessibility, hierarchy
- Healer: fixes issues found; re-run verification after fixes

---
