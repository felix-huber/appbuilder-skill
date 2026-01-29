#!/bin/bash
# devin_review.sh - Run Devin AI code review on a PR
#
# Uses the Devin CLI by default (npx devin-review) for best results.
# Falls back to web interface if CLI unavailable.
#
# Devin Review is FREE for public PRs and provides:
# - Bug detection (severe/non-severe)
# - Logical code grouping
# - Copy/move detection
# - Context-aware Q&A
#
# Usage:
#   ./scripts/devin_review.sh [options] [pr_url_or_number]
#   ./scripts/devin_review.sh                           # Current PR via CLI
#   ./scripts/devin_review.sh 123                       # PR #123
#   ./scripts/devin_review.sh --web 123                 # Force web interface
#
# Output:
#   artifacts/06-oracle/devin/pr-<number>-review.md

set -e

# Defaults
USE_WEB=false
PR_INPUT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --web)
      USE_WEB=true
      shift
      ;;
    *)
      PR_INPUT="$1"
      shift
      ;;
  esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_box() {
  local title="$1"
  local width=60
  echo ""
  printf "╔"; printf '═%.0s' $(seq 1 $width); printf "╗\n"
  printf "║  %-$((width-3))s║\n" "$title"
  printf "╚"; printf '═%.0s' $(seq 1 $width); printf "╝\n"
}

# Create output directory
OUTPUT_DIR="artifacts/06-oracle/devin"
mkdir -p "$OUTPUT_DIR"

print_box "DEVIN CODE REVIEW"

# Try CLI first (preferred)
if [[ "$USE_WEB" == "false" ]] && command -v npx &> /dev/null; then
  echo ""
  echo -e "${BLUE}Running Devin CLI (npx devin-review)...${NC}"
  echo -e "${CYAN}This analyzes your PR locally with deep context.${NC}"
  echo ""
  
  # Run devin-review CLI
  # It opens a localhost server and analyzes the PR
  set +e
  npx devin-review 2>&1 | tee "$OUTPUT_DIR/cli-output.log"
  CLI_EXIT=$?
  set -e
  
  if [[ $CLI_EXIT -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Devin CLI review complete.${NC}"
    echo ""
    echo "Review the results in your browser."
    echo "Severe bugs will be highlighted in red."
    echo ""
    
    # Try to detect PR number for filename
    if [[ -n "$PR_INPUT" ]]; then
      PR_NUMBER="$PR_INPUT"
    else
      PR_NUMBER=$(gh pr view --json number -q .number 2>/dev/null || echo "unknown")
    fi
    
    # Save a record
    cat > "$OUTPUT_DIR/pr-${PR_NUMBER}-review.md" << EOF
# Devin Review: PR #${PR_NUMBER}

**Date**: $(date -Iseconds)
**Method**: CLI (npx devin-review)

## Summary

Devin CLI review completed. Check the browser for detailed results.

See: $OUTPUT_DIR/cli-output.log for CLI output.

## Next Steps

1. Review bugs in the Devin Review interface
2. Fix any SEVERE bugs before merging
3. Re-run to verify fixes
EOF
    
    echo -e "${GREEN}Record saved to: $OUTPUT_DIR/pr-${PR_NUMBER}-review.md${NC}"
    exit 0
  else
    echo ""
    echo -e "${YELLOW}CLI failed (exit $CLI_EXIT). Falling back to web interface...${NC}"
  fi
fi

# Web interface fallback
if [ -z "$PR_INPUT" ]; then
  # Try to get current PR
  if command -v gh &> /dev/null; then
    PR_INPUT=$(gh pr view --json number -q .number 2>/dev/null || echo "")
  fi
  
  if [ -z "$PR_INPUT" ]; then
    echo "Usage: $0 [--web] <pr_url_or_number>"
    echo ""
    echo "Examples:"
    echo "  $0                              # Current PR via CLI"
    echo "  $0 123                          # PR #123"
    echo "  $0 --web 123                    # Force web interface"
    echo "  $0 owner/repo#123               # Specific repo"
    exit 1
  fi
fi

# Parse PR input into GitHub URL
GITHUB_URL=""
DEVIN_URL=""
PR_NUMBER=""

if [[ "$PR_INPUT" =~ ^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
  PR_NUMBER="${BASH_REMATCH[3]}"
  GITHUB_URL="$PR_INPUT"
  DEVIN_URL="https://devin.ai/${OWNER}/${REPO}/pull/${PR_NUMBER}"
elif [[ "$PR_INPUT" =~ ^([^/]+)/([^#]+)#([0-9]+)$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
  PR_NUMBER="${BASH_REMATCH[3]}"
  GITHUB_URL="https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"
  DEVIN_URL="https://devin.ai/${OWNER}/${REPO}/pull/${PR_NUMBER}"
elif [[ "$PR_INPUT" =~ ^[0-9]+$ ]]; then
  PR_NUMBER="$PR_INPUT"
  
  # Get repo from gh CLI or git remote
  if command -v gh &> /dev/null; then
    REPO_INFO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "")
    if [ -n "$REPO_INFO" ]; then
      OWNER=$(echo "$REPO_INFO" | cut -d'/' -f1)
      REPO=$(echo "$REPO_INFO" | cut -d'/' -f2)
    fi
  fi
  
  if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
    REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/(.+?)(\.git)?$ ]]; then
      OWNER="${BASH_REMATCH[1]}"
      REPO="${BASH_REMATCH[2]}"
      # Strip .git suffix if present
      REPO="${REPO%.git}"
    fi
  fi
  
  if [ -z "$OWNER" ] || [ -z "$REPO" ]; then
    echo -e "${RED}ERROR: Cannot determine repo. Use full URL or owner/repo#123 format.${NC}"
    exit 1
  fi
  
  GITHUB_URL="https://github.com/${OWNER}/${REPO}/pull/${PR_NUMBER}"
  DEVIN_URL="https://devin.ai/${OWNER}/${REPO}/pull/${PR_NUMBER}"
else
  echo -e "${RED}ERROR: Invalid PR format: $PR_INPUT${NC}"
  exit 1
fi

OUTPUT_FILE="$OUTPUT_DIR/pr-${PR_NUMBER}-review.md"

echo ""
echo "  PR:        $GITHUB_URL"
echo "  Devin URL: $DEVIN_URL"
echo ""

# Open Devin Review in browser
echo -e "${BLUE}Opening Devin Review in browser...${NC}"

if command -v open &> /dev/null; then
  open "$DEVIN_URL"
elif command -v xdg-open &> /dev/null; then
  xdg-open "$DEVIN_URL"
elif command -v wslview &> /dev/null; then
  wslview "$DEVIN_URL"
else
  echo "Please open: $DEVIN_URL"
fi

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Devin Review is analyzing your PR...${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Fix any SEVERE bugs (red) before merging."
echo "  Investigate FLAGS (yellow) as needed."
echo ""
echo -e "${CYAN}Tip: For private repos, use: npx devin-review${NC}"

# Save record
cat > "$OUTPUT_FILE" << EOF
# Devin Review: PR #${PR_NUMBER}

**Date**: $(date -Iseconds)
**PR**: $GITHUB_URL
**Devin**: $DEVIN_URL
**Method**: Web interface

## Instructions

1. Review bugs in the Devin Review interface
2. Fix any SEVERE bugs before merging
3. Re-run to verify fixes

## Integration with Claude Code

To apply fixes, tell Claude Code:

\`\`\`
Read $OUTPUT_FILE and fix all bugs found by Devin Review.
Use fresh eyes review after each fix.
\`\`\`
EOF

echo ""
echo -e "${GREEN}Record saved to: $OUTPUT_FILE${NC}"
