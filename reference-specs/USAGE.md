# Reference Specs Usage Guide

This directory contains exemplary planning documents from Dicklesworthstone's GitHub repositories. Use these as reference standards when creating or reviewing plans.

## Available Reference Specs

| File | Source | Lines | Type | Best For |
|------|--------|-------|------|----------|
| `frankentui-plan.md` | frankentui | 4800 | Terminal UI library | Engineering contracts, ADRs, formal specs |
| `ntm-improvement-plan.md` | ntm | 3600 | Agent orchestration | Integration tiers, ecosystem analysis |
| `beads-rust-integration-plan.md` | beads_rust | 1600 | CLI integration | Output modes, migration strategies |
| `flywheel-manifest-plan.md` | agentic_coding_flywheel_setup | 2800 | Install system | Dependency resolution, CLI flags |
| `vibe-cockpit-plan.md` | vibe_cockpit | 2400 | Dashboard | Data layers, observability |
| `ntm-hypersync-spec.md` | ntm | 1600 | Protocol spec | Distributed systems, correctness |
| `flywheel-gateway-plan.md` | flywheel_gateway | 10200 | TypeScript/Bun platform | SDK-first APIs, agent orchestration, WebSocket streaming |
| `jeffreysprompts-webapp-plan.md` | jeffreysprompts.com | 7300 | Next.js/React webapp | PWA architecture, BM25 search, monorepo structure |
| `beads-viewer-optimization-plan.md` | beads_viewer | 650 | Go performance | Profiling methodology, buffer pooling, benchmarks |

## When to Use Reference Comparison

Run the reference comparison Oracle after these events:

1. **After `/plan` skill completes** - Before implementation begins
2. **After major plan revisions** - When scope changes significantly
3. **Before task breakdown** - Ensure plan is complete enough to decompose
4. **When plan review stalls** - Fresh perspective from reference patterns

## Integration with oracle_converge.sh

### Option 1: Standalone Comparison

Run the reference comparison as a one-shot review:

```bash
# Create a prompt file with your plan + the comparison prompt
cat prompts/reference-comparison.txt artifacts/02-plan.md > /tmp/comparison-input.md

# Run through Oracle (manual browser mode)
./scripts/oracle_converge.sh plan-review /tmp/comparison-input.md reference-specs/frankentui-plan.md
```

### Option 2: Add as Oracle Pass Type

Add to `scripts/oracle_converge.sh` as a new review type:

```bash
# In oracle_converge.sh, add case for "reference-check":
"reference-check")
    SYSTEM_PROMPT="Compare against reference specs in reference-specs/ directory"
    INPUT_FILES="$ARTIFACT_PATH reference-specs/*.md"
    ;;
```

Then run:
```bash
./scripts/oracle_converge.sh reference-check artifacts/02-plan.md
```

### Option 3: Integrate into Plan Skill

Add to `skills/plan/SKILL.md` workflow:

```markdown
## Phase 3: Reference Comparison (NEW)

After generating the plan, compare against reference specs:

1. Load reference-comparison.txt prompt
2. Load user's plan + 2-3 relevant reference specs
3. Run GPT-5.2 Pro review
4. Apply gap recommendations
5. Iterate until score >= 70/100
```

## Key Patterns to Extract from Each Spec

### frankentui-plan.md
- **Non-Negotiables (Engineering Contract)**: Section 0.1.1
- **Quality Gates (Stop-Ship)**: Section 0.7
- **ADR Format**: Section 0.13
- **Performance Budgets**: Section 0.12
- **Kernel Invariants**: Section 0.5

### ntm-improvement-plan.md
- **Design Invariants + Non-Goals + Risks**: Top section
- **Integration Tier System**: Tier 0/1/2/3 classification
- **Tool Ecosystem Diagram**: ASCII art relationships
- **Priority Matrix**: Impact vs effort ranking
- **Test Strategy**: Section 28

### beads-rust-integration-plan.md
- **Output Context Pattern**: OutputMode enum + routing
- **Mode Detection Logic**: JSON/quiet/plain/rich
- **Gradual Migration**: Phase-based rollout
- **Theme System**: Consistent styling approach

### flywheel-manifest-plan.md
- **Module Taxonomy**: Category/tag/phase classification
- **Selection Algorithm**: Dependency resolution logic
- **Legacy Flag Mapping**: Backwards compatibility
- **Golden Path Examples**: Common usage patterns

### vibe-cockpit-plan.md
- **Layered Architecture**: Perception/Cognition/Memory/Action/Interface
- **Data Flow Diagrams**: Pull-first, push-optional
- **Collector Pattern**: Trait-based data ingestion
- **Source System Integration**: Per-tool ingestion tables

### ntm-hypersync-spec.md
- **Background Section**: Makes spec self-contained
- **Assumptions vs Guarantees vs Deviations**: Explicit contracts
- **Failure Model**: What happens when things break
- **Correctness Properties**: Formal invariants

### flywheel-gateway-plan.md
- **Agent Flywheel Diagram**: Comprehensive ASCII art showing PLAN/COORDINATE/EXECUTE/SCAN/REMEMBER cycle
- **SDK-First Architecture**: TypeScript/Bun monorepo with packages/apps structure
- **Tool Integration Tables**: Detailed per-tool integration specs (Agent Mail, BV, UBS, CASS)
- **WebSocket Streaming**: Real-time agent output patterns
- **Spawn Backend Abstraction**: Multiple backends (SDK, ACP, Tmux) unified under common interface

### jeffreysprompts-webapp-plan.md
- **Executive Summary Pattern**: "Why This Plan Wins" with bullet points
- **Goals/Non-Goals/Success Metrics**: Clear product framing
- **Background Context Section**: Origin story + problem statement
- **Monorepo Package Structure**: `@jeffreysprompts/core` as sole source of truth
- **PWA + CLI Dual-Mode**: Same content, different shells (web + CLI)
- **BM25 Search Implementation**: Client-side search architecture

### beads-viewer-optimization-plan.md
- **Hard Constraints Section**: Repo invariants + methodology invariants (A-G)
- **Architecture Snapshot**: Data plane + two-phase analysis contract
- **Baseline Metrics Tables**: Environment, workloads, latency distribution, peak memory
- **Profiling Results**: CPU/memory hotspot identification with percentages
- **Equivalence Oracle**: Golden outputs + property tests
- **Opportunity Matrix**: (Impact x Confidence) / Effort ranking

## Scoring Thresholds

When running reference comparison, use these thresholds:

| Score | Verdict | Action |
|-------|---------|--------|
| 80-100 | Excellent | Proceed to implementation |
| 60-79 | Good | Fix critical gaps, then proceed |
| 40-59 | Needs Work | Major revision required |
| 0-39 | Incomplete | Start over with template |

## Updating Reference Specs

To refresh or add new reference specs:

```bash
# Download latest version
curl -o reference-specs/frankentui-plan.md \
  "https://raw.githubusercontent.com/Dicklesworthstone/frankentui/main/PLAN_TO_CREATE_FRANKENTUI__OPUS.md"

# Check for new planning docs in a repo
gh api repos/Dicklesworthstone/{repo}/contents \
  --jq '.[] | select(.name | test("PLAN|SPEC|PRD|DESIGN"; "i")) | .name'
```

## Example Workflow

```bash
# 1. Generate initial plan with /plan skill
# 2. Check what exists
ls -la artifacts/02-plan.md

# 3. Run reference comparison
cat prompts/reference-comparison.txt > /tmp/oracle-input.md
echo "---" >> /tmp/oracle-input.md
echo "# USER PLAN TO REVIEW" >> /tmp/oracle-input.md
echo "---" >> /tmp/oracle-input.md
cat artifacts/02-plan.md >> /tmp/oracle-input.md

# 4. Open in browser Oracle and paste the 2-3 most relevant reference specs
# 5. Apply recommendations to artifacts/02-plan.md
# 6. Re-run comparison until score >= 70
# 7. Proceed to task breakdown
```
