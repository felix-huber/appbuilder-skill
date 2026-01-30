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

## Recommended: Install DCG for Safety

Prevents agents from running destructive git/filesystem commands:

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/destructive_command_guard/master/install.sh?$(date +%s)" | bash
```

This auto-configures Claude Code, Codex, Gemini, Cursor, and Aider to block:
- `git reset --hard`, `git clean -f`, `git push --force`
- `rm -rf` outside temp directories
- Other destructive patterns

See: https://github.com/Dicklesworthstone/destructive_command_guard

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

## ast-grep vs ripgrep (Quick Guidance)

**Use ast-grep when structure matters.** It parses code and matches AST nodes, so results ignore comments/strings, understand syntax, and can safely rewrite code.

| When | Tool |
|------|------|
| Refactors/codemods (rename APIs, change imports) | ast-grep |
| Policy checks (enforce patterns across repo) | ast-grep |
| "How is X implemented?" | ast-grep or warp_grep |

**Use ripgrep when text is enough.** It's the fastest way to grep literals/regex across files.

| When | Tool |
|------|------|
| Find strings, TODOs, log lines, config values | rg |
| Pre-filter before precise pass | rg |
| Non-code assets | rg |

**Rule of thumb:**
- Need correctness or you'll apply changes → start with ast-grep
- Need raw speed or just hunting text → start with rg
- Often combine: `rg` to shortlist files, then `ast-grep` to match/modify with precision

**Snippets:**
```bash
# Find structured code (ignores comments/strings)
ast-grep run -l Python -p 'def $NAME($PARAMS): $$$BODY'

# Find all async function definitions
ast-grep run -l Python -p 'async def $NAME($PARAMS): $$$BODY'

# Quick textual hunt
rg -n 'def .*research' -t py

# Combine speed + precision
rg -l -t py 'pandas' | xargs ast-grep run -l Python -p 'import pandas as $ALIAS' --json
```

---

## UBS Quick Reference (Ultimate Bug Scanner)

**Golden Rule:** `ubs --diff .` (or `ubs --staged`) before every commit. Exit 0 = safe. Exit >0 = fix & re-run.

**Commands:**
```bash
ubs --diff --only=js,python .    # Modified files (working tree vs HEAD) — USE THIS
ubs --staged --only=js,python .  # Staged files — before commit
ubs --ci --fail-on-warning --diff .  # CI mode for the diff — before PR
ubs .                             # Whole project (slow, use sparingly)
```

**Output Format:**
```
⚠️ Category (N errors)
file.ts:42:5 – Issue description
💡 Suggested fix
Exit code: 1
```

**Fix Workflow:**
1. Read finding → category + fix suggestion
2. Navigate `file:line:col` → view context
3. Verify real issue (not false positive)
4. Fix root cause (not symptom)
5. Re-run `ubs <file>` → exit 0
6. Commit

**Bug Severity:**
- **Critical (always fix):** Null safety, XSS/injection, async/await, memory leaks
- **Important (production):** Type narrowing, division-by-zero, resource leaks
- **Contextual (judgment):** TODO/FIXME, console logs

**Anti-Patterns:**
- ❌ Ignore findings → ✅ Investigate each
- ❌ Full scan per edit → ✅ Scope to file
- ❌ Fix symptom (`if (x) { x.y }`) → ✅ Root cause (`x?.y`)

---

## Beads Workflow Integration

When starting a beads-tracked task:

1. **Pick ready work (Beads)**
   ```bash
   br ready --json  # Choose highest priority, no blockers
   ```

2. **Announce start**
   ```bash
   br update <id> --status in_progress
   ```

3. **Work and update**
   - If you discover new work, create a new bead with `--deps discovered-from:<parent-id>`

4. **Complete and release**
   ```bash
   br close <id> --reason "Completed"
   ```

5. **If using beads, keep state updated (this repo ignores `.beads/`)**

**Mapping cheat-sheet:**
- Thread ID / commit messages: `br-###` for traceability
- File reservation reason: `br-###`

**Key invariants (when using beads):**
- `.beads/` is authoritative state in beads-tracked projects
- Do not edit `.beads/*.jsonl` directly; only via `br`

---

## Landing the Plane (Session Completion)

When ending a work session, you MUST complete ALL steps below. Work is NOT complete until git push succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work**
   - Create issues for anything that needs follow-up

2. **Run quality gates (if code changed)**
   ```bash
   npm run lint
   npm run typecheck
   npm test
   ```

3. **Update issue status**
   - Close finished work, update in-progress items

4. **PUSH TO REMOTE** — This is MANDATORY:
   ```bash
   git pull --rebase
   br sync --flush-only  # Export to JSONL (does NOT run git commands)
   git add -A && git commit -m "Update work"
   git push
   git status  # MUST show "up to date with origin"
   ```

5. **Clean up**
   - Clear stashes, prune remote branches

6. **Verify**
   - All changes committed AND pushed

7. **Hand off**
   - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing — that leaves work stranded locally
- NEVER say "ready to push when you are" — YOU must push
- If push fails, resolve and retry until it succeeds

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

## Artifact Chain

```
00-brief.md        → /brief
01-prd.md          → /prd
06-oracle/prd/*    → /oracle prd (iterate until converged)
02-ux.md           → /ux
06-oracle/ux/*     → /oracle ux (iterate until converged)
05-design/*        → /ui (optional)
03-plan.md         → /plan (with sprints!)
06-oracle/plan/*   → /oracle plan (iterate until converged)
04-task-graph.json → /artifact-tasks
04-beads-setup.sh  → (optional) beads creation script
[implementation]   → ./scripts/ralph.sh [--beads]
06-oracle/code/*   → /oracle code (iterate until converged)
07-verification.md → /gates
08-release.md      → /ship
09-retro.md        → /retro
```

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

### Option 3: strict_ralph.sh — Enforced Backpressure + Cross-Model Review

```bash
# Full loop (beads)
./scripts/strict_ralph.sh --loop --beads --tool claude --review-tool codex

# Full loop (task graph)
./scripts/strict_ralph.sh --loop
```

**Backpressure rules (Ralph + strict_ralph):**
- Tasks must define `verification` commands.
- Optional `llmVerification` can be used for subjective checks.
- Defaults for non-Node repos:
  - `verification.txt` at repo root, or
  - `RALPH_DEFAULT_VERIFY` env var, or
  - `--default-verify "<cmds>"`.
- LLM-only verification is allowed if no commands exist, but it must pass.

---

## Tool Routing (Doodlestein Methodology)

**Ralph uses smart routing by default:**

| Task Type | Tool | Why |
|-----------|------|-----|
| Backend (core, api, data, worker) | Codex | Fast iteration |
| Frontend (ui, components, design) | Claude Code | Nuanced implementation |
| Heavy doc reviews (PRD, UX, Plan) | GPT-5.2 Pro | Deep reasoning via /oracle |

---

## Commands from This Extension

| Command | Purpose |
|---------|---------|
| `/brief` | Create problem brief (artifact 00) |
| `/prd` | Generate PRD (artifact 01) |
| `/ux` | Generate UX spec (artifact 02) |
| `/ui` | UI exploration: tasteboard + keystone + variants |
| `/plan` | Generate implementation plan with SPRINTS (artifact 03) |
| `/oracle <kind>` | Run GPT-5.2 Pro review (prd/ux/plan/code) — iterate! |
| `/artifact-tasks` | Compile task graph from plan + issues |
| `/sprint` | Break spec into atomic sprint tasks |
| `/ralph` | Run autonomous execution loop |
| `/review <type>` | Run iterative review loops |
| `/swarm-status` | Report swarm health |
| `/gates` | Run verification checks |
| `/ship` | Create release plan |
| `/retro` | Capture learnings |
| `/combined-lfg` | Full integrated workflow |

---

## Skills from This Extension

| Skill | Purpose |
|-------|---------|
| `oracle-integration` | Oracle CLI wrapper and issue normalization |
| `artifact-workflow` | Artifact chain management and phase detection |
| `phase-transitions` | Transformation prompts between phases |
| `ui-exploration` | Tasteboard, keystone, variants workflow |
| `review-loops` | Iteration methodology |
| `parallel-execution` | Dependency rules, self-healing, status tracking |
| `frontend-design` | ASCII wireframes, oklch colors, animations |
| `agent-browser` | Browser automation patterns |

---

## Where Things Live

- Commands: `.claude/commands/`
- Skills: `skills/`
- Scripts: `scripts/`
- Prompts: `prompts/{prd,ux,plan,code,sprint,review,ralph}/`
- Templates: `templates/`
- Tools: `tools/` (tasteboard, design-gallery, task-board)
- Artifacts: `artifacts/` (generated during workflow)
- Docs: `docs/` (schema documentation, patterns)
