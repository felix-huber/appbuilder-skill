# Strict Claude Appbuilder Workflow

This is a strict, repeatable workflow to build a full app with Claude using this repo.
It enforces TDD, blocks fake tests, and uses fresh reviewer instances for review loops (cross-model by default).

## Preconditions
- Repo initialized
- Templates copied into artifacts/
- Claude Code CLI installed (or use manual prompts)

## Phase 1: Planning (Claude Instance A)
1) Create brief
   - Copy `templates/BRIEF.template.md` -> `artifacts/00-brief.md`
   - Fill in goals, constraints, and non-goals

2) PRD
   - Ask Claude to generate `artifacts/01-prd.md` from the brief

3) UX spec
   - Ask Claude to generate `artifacts/02-ux.md` with user journeys
   - Each journey must have testable steps and visible assertions

4) Implementation plan
   - Ask Claude to generate `artifacts/03-plan.md` using `templates/PLAN.template.md`
   - Must include:
     - Unit test specs per feature task
     - Integration/E2E test tasks
     - Test harness plan (UI/CLI/API/library)
     - Test quality review step

## Phase 2: Task Generation
Choose one:
- Beads: run `/sprint` or create beads manually
- Task graph: generate `artifacts/04-task-graph.json`

## Skills to Use (inside Claude Code)
Use these skills inside Claude Code as you work through the phases:
- `$prd` for PRD generation from the brief
- `$artifact-workflow` for the artifact chain (PRD -> UX -> Plan)
- `$review-loops` for Doodlestein review prompts (plan/beads/code)
- `$oracle-integration` for Oracle reviews (long-running, use only when needed)
- `$agent-browser` for E2E user journeys and screenshots
- `$frontend-design` and `$frontend-responsive` for UI work
- `$context7` when using external libraries or SDKs
- `$llm-council` (optional) for robust multi-agent planning

When doing code review loops, explicitly ask for a fresh instance and
use the review-loops prompts to keep iterations strict.

## Commands to Run Manually (outside Claude Code)
Run these in your shell (not inside Claude):
- Beads setup: `br init`, `br ready`, `br list`, `br show`, `br close`, `br update`
- Strict loop: `./scripts/strict_ralph.sh --loop --beads --tool claude --review-tool codex`
- Gates: `./scripts/gate_pack.sh`
- E2E: `./scripts/run_e2e_happy_paths.sh` (if present)
- Oracle (optional): `./scripts/oracle_converge.sh <lens> ...` after checking state

## Phase 3: Strict Task Execution (per task)
Use a fresh Claude instance for each task.

1) Implementer prompt includes:
   - Task ID, acceptance criteria, files, verification commands
   - TDD required for feature work
   - Test quality guardrails: no fake tests

2) TDD enforced:
   - Write tests first
   - Run tests and confirm they fail for the right reason
   - Implement minimal code to pass

3) Test harness required if integration is incomplete:
   - UI: minimal route/screen with real component + mock data
   - CLI: fixture command that runs against temp input/output
   - API: minimal runner that starts server + hits real endpoints
   - Library: example harness calling public API end-to-end

4) Verification:
   - Run the task’s verification commands (lint/typecheck/test/build etc)
   - Do not mark task complete without passing tests

5) Commit after verification

## Phase 4: Strict Review Loop (fresh instance)
Use a fresh reviewer instance (preferably a different model).

1) Reviewer receives:
   - Task acceptance criteria
   - Diff or PR
   - Test output

2) Reviewer checks:
   - Acceptance criteria met
   - Tests are real (behavioral, no tautologies)
   - No regressions

3) Reviewer output format:
   - If clean: output exactly `NO_ISSUES_FOUND`
   - If issues: list `[P1]/[P2]/[P3]` issues with file:line

4) If issues found:
   - Spawn a new implementer instance
   - Provide task + code + reviewer feedback
   - Fix, re-run tests, and re-review

Repeat until `NO_ISSUES_FOUND`.

## Phase 5: Integration and Gates
- Run `./scripts/gate_pack.sh`
- Run E2E (if present)
- If E2E is missing for critical flows, add the harness + tests before release

## Notes for non-UI apps (CLI/API/Library)
- E2E still required: replace with real end-to-end harnesses
- Tests must assert real behavior (exit codes, side effects, persistence)
- No config-only or tautological assertions

## strict_ralph.sh (automated strict loop)
Use `./scripts/strict_ralph.sh` to automate the strict loop.

Examples:
- Single task (task graph): `./scripts/strict_ralph.sh --task-id S1-T1`
- Full loop (task graph): `./scripts/strict_ralph.sh --loop`
- Full loop (beads): `./scripts/strict_ralph.sh --loop --beads`

Notes:
- It auto-picks the next unblocked task from task graph or `br ready --json` if `--beads` is set.
- It auto-commits after a clean review (use `--no-commit` to disable).
- If `--no-commit` is set in loop mode, the script stops after one task so you can
  review and commit manually before continuing.
- It enforces test-file changes via filename patterns (tests/, *_test.go, _spec.rb, etc).
- If your tests live inline in non-test files, use `--allow-no-tests` and explain why.
- If using beads, make sure each bead description includes verification commands
  or pass `--allow-no-verify`.
- It logs progress to `progress.txt`, writes a lightweight execution summary to
  `artifacts/08-execution-summary.md`, and appends a learnings stub to `learnings.md`.
- Each tool invocation is a fresh CLI session; no shared context is assumed.
