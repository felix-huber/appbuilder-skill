# Agents — Oracle Swarm Extension

This extension provides 4 specialized agents that complement Compound Engineering's 27 agents.

**CRITICAL**: Read ALL sections before starting any work!

---

## When Working With Me

- Be concise, skip obvious explanations
- Just make the fix, don't ask permission for small changes
- If something's unclear, make a reasonable assumption and note it
- **After starting/restarting the dev server**, always smoke test: wait for ready, curl the homepage, then agent-browser open key pages affected by recent changes

---

## CRITICAL RULES (ALL AGENTS MUST FOLLOW)

### Rule 1: Never Delete Files Without Permission
You may NOT delete files without explicit permission. Even files you created. Ask first, always.

### Rule 2: No File Proliferation
NEVER create `file_v2.js`, `file_improved.js`, `file_enhanced.js`, etc. Revise existing files in place.

### Rule 3: No Automated Code Transforms  
NEVER run scripts that process/change code files. Make changes manually. Use subagents in parallel for many simple changes.

### Rule 4: Simplicity Check
Before committing: "Would a senior engineer say this is overcomplicated? If yes, simplify."

---

## Note for Codex/GPT-5.2 (READ THIS!)

If you are Codex or GPT-5.2 (or any non-Claude agent): another agent may have made changes since you last saw the code. Before assuming your mental model is correct:

```bash
git status              # See uncommitted changes
git log --oneline -5    # See recent commits
```

**Re-read any files you plan to modify.** This prevents overwriting another agent's work.

### Using Skills in Codex

This extension's skills work in both Claude Code and Codex (same SKILL.md format).

**One-time setup:**
```bash
./scripts/setup_codex_skills.sh   # Creates symlinks in .codex/skills/
```

**Start Codex with skills:**
```bash
codex --enable skills
```

**Invoke skills with `$` prefix:**
```
$oracle-integration     # Run Oracle review
$artifact-workflow      # Artifact chain management
$frontend-design        # UI work
```

**Or just describe what you want** — Codex will use skills automatically:
```
Run the Oracle convergence loop for UX
Create a PRD from the brief
```

**Command equivalents:**

| Claude Code | Codex | Alternative |
|-------------|-------|-------------|
| `/oracle ux` | `$oracle-integration` | `./scripts/oracle_converge.sh ux ...` |
| `/prd` | `$artifact-workflow` | Describe: "create PRD from brief" |
| `/ralph` | — | `./scripts/ralph.sh` (scripts work directly) |

All shell scripts (`./scripts/*.sh`) work in both environments without modification.

### ⚠️ Check Existing Oracle State FIRST

**Before running any Oracle command, check what already exists:**

```bash
# Check existing state
ls -la artifacts/06-oracle/<kind>/ 2>/dev/null
cat artifacts/06-oracle/<kind>/convergence-history.json 2>/dev/null
```

| Situation | Action |
|-----------|--------|
| Already converged (0 blockers, ≤2 majors) | Done — no action needed |
| Unapplied feedback exists | Apply feedback first |
| No Oracle output | Run Oracle |

### Long-Running Oracle Processes (CRITICAL for Codex)

Oracle CLI commands take **60-90 minutes** to complete. This is normal.

**DO NOT:**
- ❌ Interrupt or timeout Oracle processes
- ❌ Assume "no output" means stuck
- ❌ Kill processes after 5-10 minutes

**DO:**
- ✅ Wait patiently (GPT-5.2 Pro "thinking" takes 30+ minutes)
- ✅ Monitor with: `pgrep -fl oracle`
- ✅ Watch logs: `tail -f artifacts/06-oracle/*/oracle-*.log`
- ✅ Check for new files: `ls -la artifacts/06-oracle/ux/`

**Expected timeline:**
1. Script starts → immediate output
2. Browser opens → GPT-5.2 Pro starts
3. **30-60 minutes of silence** → extended thinking
4. Response streams → output file created
5. Script reports results

After Oracle completes, apply feedback from the newest `*_product.md` file.

**Codex config for long runs** (add to `~/.codex/config.toml`):
```toml
[model_providers.openai]
stream_idle_timeout_ms = 7200000  # 2 hours
```

---

## ITERATION REQUIREMENTS (Doodlestein Methodology)

> "Planning tokens are a lot fewer and cheaper than implementation tokens."
> — Jeffrey Emanuel (@doodlestein)

**Time Distribution**: 85% planning, 15% implementation

| Phase | Minimum Iterations | Convergence Criteria |
|-------|-------------------|----------------------|
| Plan review | 4-5 passes | Suggestions become incremental |
| Beads review | 6-9 passes | No more changes |
| Fresh eyes code review | Until stable | No bugs found |
| Oracle review | Until converged | 0 new blockers/majors |

### Key Prompts (Use These Verbatim!)

**Before reviewing beads:**
```
Reread AGENTS.md so it's still fresh in your mind.
```

**After completing a task:**
```
Great, now I want you to carefully read over all of the new code you
just wrote and other existing code you just modified with "fresh eyes"
looking super carefully for any obvious bugs, errors, problems, issues,
confusion, etc.

**FIRST CHECK**: Would a senior engineer say this is overcomplicated? 
If yes, simplify it first.

Carefully fix anything you uncover. Use ultrathink.
```
→ **Keep running this until no bugs are found!**

**Beads review (run 6-9 times):**
```
Check over each bead super carefully-- are you sure it makes sense?
Is it optimal? Could we change anything to make the system work better?

DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY!
```

See `skills/phase-transitions/SKILL.md` for the complete prompt library.

---

## oracle-coordinator

**Role**: Orchestrates multi-lens Oracle review runs.

**When to use**:
- Automated Oracle workflows (e.g., `/combined-lfg`)
- When running multiple lenses in sequence
- When tracking Oracle output across phases

**Capabilities**:
- Generates Oracle CLI commands for each lens
- Monitors for output file creation
- Normalizes outputs to issues.json
- Summarizes findings by severity/category
- Tracks unresolved blockers across phases
- **Iterates until convergence (0 new issues)**

**Prompt**:
```
You are the Oracle Coordinator. Your job is to run GPT-5.2 Pro review loops via the Oracle CLI (browser mode only). You generate commands, wait for outputs, and normalize results.

CRITICAL: Keep running Oracle until issues converge to zero. Do not stop after a single pass!
```

---

## artifact-validator

**Role**: Validates artifact completeness and ordering.

**When to use**:
- Before phase transitions (e.g., before coding)
- When user asks "what's next?" or "where am I?"
- After Oracle reviews to check blocker status

**Capabilities**:
- Checks artifact existence and completeness
- Validates required sections in each artifact
- Reports unresolved Oracle blockers
- **Checks Oracle convergence status**
- Suggests next action based on workflow state

**Prompt**:
```
You are the Artifact Validator. Your job is to ensure the artifact chain is complete and properly ordered. Check for missing artifacts, incomplete sections, and unresolved blockers.

CRITICAL: Do not approve phase transitions until Oracle reviews have CONVERGED (0 new blockers/majors).
```

---

## design-synthesizer

**Role**: Synthesizes tasteboard into keystone and variants.

**When to use**:
- During `/ui` command execution
- When generating HTML prototypes from design references
- When creating variant explorations

**Capabilities**:
- Extracts design principles from tasteboard
- Generates keystone HTML with realistic content
- Creates 6-12 variant HTML files
- Builds design manifest for gallery

**Prompt**:
```
You are the Design Synthesizer. Your job is to transform design references (tasteboard) into production-quality HTML prototypes. You create a keystone screen and multiple variants exploring different directions.
```

---

## release-planner

**Role**: Generates release plans from verification results.

**When to use**:
- During `/ship` command execution
- When creating rollout/rollback strategies
- When documenting release readiness

**Capabilities**:
- Reads verification report (artifact 07)
- Generates rollout steps with checkpoints
- Creates monitoring and alerting requirements
- Documents rollback procedures
- Prepares customer communications

**Prompt**:
```
You are the Release Planner. Your job is to create comprehensive release plans with rollout steps, monitoring, and rollback procedures. You ensure releases are safe and reversible.
```

---

## Agent Roles in Multi-Agent Execution

Based on Doodlestein's methodology, different agents have different strengths:

| Agent Type | Best For | Role |
|------------|----------|------|
| Claude Code (CC) | Frontend/UI, complex reasoning, architecture | Nuanced implementation |
| Codex (COD) | Backend/API, fast iteration, refactoring | Fast iteration |
| Gemini (GMI) | Code review ONLY | Quality gate |
| GPT-5.2 Pro | Heavy document reviews (PRD, UX, Plan) | Oracle reviews |

### Ralph Agent Assignment (DEFAULT: Smart Routing)

By default, `./scripts/ralph.sh` routes tasks intelligently:
- **Backend tasks** (core, engine, api, data, worker, db) → **Codex** (fast)
- **Frontend tasks** (ui, components, design, css, styles) → **Claude Code** (nuanced)
- **Heavy doc reviews** (PRD, UX, Plan) → **GPT-5.2 Pro** via `/oracle` command

### Skills (Within Claude Code)

Claude Code uses skills from `skills/` directory:
- `phase-transitions` — Transformation prompts between phases
- `review-loops` — Iteration methodology for reviews
- `artifact-workflow` — Artifact chain management
- `oracle-integration` — Oracle CLI wrapper
- `ui-exploration` — Design workflow

### Multi-Agent Collaboration Rules

1. **Reserve files** before editing (avoid conflicts)
2. **Never overwrite** other agents' changes
3. **Communicate** via agent mail or git commits
4. **Mark beads** when starting (`in_progress`) and completing (`closed`)

---

## Agent Interaction with Compound Engineering

These agents work alongside Compound Engineering's agents:

| Oracle Swarm Agent | Works With | Phase |
|--------------------|------------|-------|
| oracle-coordinator | (standalone) | All phases |
| artifact-validator | (standalone) | Phase transitions |
| design-synthesizer | frontend-design skill | UI exploration |
| release-planner | (standalone) | Ship phase |

### Handoff Points

1. **Pre-code**: `artifact-validator` confirms plan is ready AND Oracle has converged → Compound Engineering takes over for `/workflows:work`

2. **Post-code**: Compound Engineering's `/workflows:review` completes → `oracle-coordinator` runs external GPT-5.2 Pro review (iterate until converged!)

3. **Ship**: `release-planner` generates release plan after gates pass

---

## The Key Insight

> "Measure twice, cut once!" → **"Check your beads N times, implement once!"**

Planning and reviewing in "plan space" is:
- 100x cheaper (fewer tokens)
- 10x faster (no build/test cycles)  
- Much higher quality (easier to reason about)

**DO NOT SKIP ITERATIONS. The extra planning time pays massive dividends during implementation.**

---

## Landing the Plane (Session Completion)

When ending a work session, complete ALL steps. Work is NOT complete until git push succeeds.

1. **File issues** for remaining work (`br create ...`)
2. **Run quality gates** if code changed
3. **Update issue status** (`br close ...`)
4. **PUSH TO REMOTE** (MANDATORY):
   ```bash
   git pull --rebase
   br sync --flush-only
   git add .beads/ && git commit -m "Update beads"
   git push
   ```
5. **Verify** `git status` shows "up to date with origin"
6. **Hand off** context for next session

**NEVER stop before pushing — that leaves work stranded locally.**

---

## Quick Tool Reference

### ast-grep vs ripgrep
- **ast-grep**: Refactors, codemods, pattern enforcement (structure matters)
- **ripgrep (rg)**: Find text, TODOs, pre-filter files (speed matters)
- **Combine**: `rg -l 'pattern' | xargs ast-grep run -p 'pattern'`

### UBS (Ultimate Bug Scanner)
```bash
ubs --diff .  # Before every commit. Exit 0 = safe.
```

See `CLAUDE.md` for full documentation.
