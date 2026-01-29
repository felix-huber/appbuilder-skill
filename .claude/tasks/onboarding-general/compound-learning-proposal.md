# Proposal: Nightly Compound Learning for AppBuilder

Based on analysis of the "compound-engineering" pattern.

## Executive Summary

Add a self-improving loop where the agent:
1. Reviews completed work and extracts learnings
2. Updates CLAUDE.md with patterns and gotchas
3. Picks the next priority from a backlog
4. Executes overnight while developer sleeps

## Current State vs Proposed

| Capability | Current | Proposed |
|------------|---------|----------|
| Learning capture | Manual (progress.txt) | Automatic (CLAUDE.md updates) |
| Next task selection | Manual or sequential | Priority-based from reports |
| Execution timing | Manual trigger | Scheduled nightly |
| Knowledge persistence | Session-scoped | Cross-session compound |

## Proposed Changes

### 1. Daily Compound Review Script

New script: `scripts/daily-compound-review.sh`

```bash
#!/bin/bash
# Reviews recent work and updates CLAUDE.md with learnings

cd "$(dirname "$0")/.."

# Ensure we're on main and up to date
git checkout main
git pull origin main

# Run compound review
claude -p "
Review all recent work:
1. Read progress.txt and learnings.md
2. Read recent git commits and their messages
3. Read any .beads/logs/*.log files from today

Extract learnings:
- Patterns that worked well
- Gotchas and pitfalls discovered
- Anti-patterns to avoid
- Workflow improvements

Update CLAUDE.md:
- Add new patterns to '## Codebase Patterns' section
- Add new gotchas to '## Gotchas' section
- Keep it concise - only add genuinely useful learnings

Commit and push if changes were made.
" --dangerously-skip-permissions
```

### 2. Priority Picker Script

New script: `scripts/pick-next-priority.sh`

```bash
#!/bin/bash
# Picks the next priority item from reports/backlog

REPORTS_DIR="${1:-reports}"
LATEST_REPORT=$(ls -t "$REPORTS_DIR"/*.md 2>/dev/null | head -1)

if [[ -z "$LATEST_REPORT" ]]; then
  echo "No reports found in $REPORTS_DIR"
  exit 1
fi

# Use Claude to analyze and pick priority
claude -p "
Read the report: $LATEST_REPORT

Identify the #1 priority item that:
- Is clearly defined and actionable
- Has the highest impact/urgency ratio
- Can be completed in a single session

Output JSON:
{
  \"priority_item\": \"description of what to build\",
  \"branch_name\": \"feature/short-name\",
  \"estimated_tasks\": 3-10
}
" --dangerously-skip-permissions --output-format json
```

### 3. Nightly Auto-Compound Script

New script: `scripts/nightly-auto-compound.sh`

```bash
#!/bin/bash
# Full nightly loop: review → pick priority → implement → PR

set -e
cd "$(dirname "$0")/.."

LOG_DIR="logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/nightly-$(date +%Y%m%d).log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Nightly Auto-Compound Started: $(date) ==="

# Step 1: Compound review (update CLAUDE.md with learnings)
echo "--- Step 1: Compound Review ---"
./scripts/daily-compound-review.sh

# Step 2: Pick next priority
echo "--- Step 2: Pick Priority ---"
PRIORITY_JSON=$(./scripts/pick-next-priority.sh reports/)
PRIORITY_ITEM=$(echo "$PRIORITY_JSON" | jq -r '.priority_item')
BRANCH_NAME=$(echo "$PRIORITY_JSON" | jq -r '.branch_name')

if [[ -z "$PRIORITY_ITEM" || "$PRIORITY_ITEM" == "null" ]]; then
  echo "No priority item found. Exiting."
  exit 0
fi

echo "Priority: $PRIORITY_ITEM"
echo "Branch: $BRANCH_NAME"

# Step 3: Create feature branch
git checkout -b "$BRANCH_NAME"

# Step 4: Create PRD and tasks
echo "--- Step 3: Create PRD ---"
# Use existing /prd and /artifact-tasks workflow
# ... (integrate with existing commands)

# Step 5: Run Ralph
echo "--- Step 4: Execute with Ralph ---"
./scripts/ralph.sh --beads 25

# Step 6: Create PR
echo "--- Step 5: Create PR ---"
git push -u origin "$BRANCH_NAME"
gh pr create --draft --title "Nightly: $PRIORITY_ITEM" --base main

echo "=== Nightly Auto-Compound Completed: $(date) ==="
```

### 4. launchd Configuration (macOS)

Create plist files for scheduled execution:

```xml
<!-- ~/Library/LaunchAgents/com.appbuilder.nightly-compound.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.appbuilder.nightly-compound</string>

  <key>ProgramArguments</key>
  <array>
    <string>/path/to/appbuilder-skill/scripts/nightly-auto-compound.sh</string>
  </array>

  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>23</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>/path/to/appbuilder-skill/logs/launchd.log</string>

  <key>StandardErrorPath</key>
  <string>/path/to/appbuilder-skill/logs/launchd.log</string>
</dict>
</plist>
```

### 5. CLAUDE.md Updates Structure

Add sections for compound learning:

```markdown
## Codebase Patterns
<!-- Auto-updated by daily-compound-review.sh -->
- (Patterns will be added as discovered)

## Gotchas
<!-- Auto-updated by daily-compound-review.sh -->
- (Gotchas will be added as discovered)

## Recent Learnings
<!-- Last 7 days of learnings, auto-rotated -->
- (Recent learnings appear here)
```

## Integration Points

### With Existing Ralph

The nightly script calls Ralph for execution, so all existing features work:
- Build verification
- Council of Subagents review (if enabled)
- Fresh-eyes review
- Anti-pattern detection

### With Beads

Use beads for task tracking:
```bash
# In nightly script, after PRD creation:
node scripts/generate_beads_setup.js
bash artifacts/04-beads-setup.sh
./scripts/ralph.sh --beads 25
```

### With Oracle

For high-impact changes, run Oracle review:
```bash
# If priority item is large/risky:
./scripts/oracle_converge.sh plan artifacts/03-plan.md
```

## Benefits

1. **Compound Knowledge** - CLAUDE.md improves every day
2. **Overnight Productivity** - Work happens while you sleep
3. **Priority-Driven** - Always working on what matters most
4. **Self-Improving** - Yesterday's learnings inform today's work

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Bad commits overnight | Use draft PRs, require human review |
| Runaway costs | Set iteration limits, add cost tracking |
| Wrong priorities | Human reviews/updates reports weekly |
| CLAUDE.md bloat | Auto-rotate old learnings, keep concise |

## Implementation Order

1. **Phase 1**: `daily-compound-review.sh` - Start capturing learnings
2. **Phase 2**: `pick-next-priority.sh` - Add priority selection
3. **Phase 3**: `nightly-auto-compound.sh` - Full overnight loop
4. **Phase 4**: launchd setup - Schedule automation

## Decision Needed

Should we implement this? Options:

1. **Full implementation** - All 4 phases
2. **Partial** - Just the compound review (Phase 1)
3. **Manual** - Document the pattern, run manually when needed
4. **Skip** - Current workflow is sufficient
