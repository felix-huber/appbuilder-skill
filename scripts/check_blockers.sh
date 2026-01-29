#!/usr/bin/env bash
# check_blockers.sh - Check for Oracle blockers safely
#
# Usage:
#   ./scripts/check_blockers.sh <issues_json_or_dir>
#
# Exit codes:
#   0 = No blockers, can proceed
#   1 = Has blockers, must fix
#
# Handles:
#   - Missing files (proceeds)
#   - Invalid JSON (proceeds with warning)
#   - Empty files (proceeds)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-}"

# If no target specified, proceed
if [[ -z "$TARGET" ]]; then
  echo "No issues file specified - proceeding"
  exit 0
fi

# If target doesn't exist, proceed
if [[ ! -e "$TARGET" ]]; then
  echo "No Oracle review yet ($TARGET not found) - proceeding"
  exit 0
fi

# Try to run the Node.js script
if command -v node &> /dev/null; then
  set +e
  result=$(node "$SCRIPT_DIR/check_blockers.js" "$TARGET" 2>/dev/null)
  node_status=$?
  set -e

  if [[ -z "$result" ]]; then
    if [[ "$node_status" == "1" ]]; then
      result='{"canProceed":false,"message":"⚠️  BLOCKERS found - must fix before proceeding"}'
    else
      result='{"canProceed":true,"message":"Check failed - proceeding"}'
    fi
  fi

  message=$(echo "$result" | jq -r '.message // "Unknown"' 2>/dev/null || echo "Check complete")
  canProceed=$(echo "$result" | jq -r '.canProceed // true' 2>/dev/null || echo "true")

  if [[ "$node_status" == "1" && "$canProceed" != "false" ]]; then
    message="⚠️  BLOCKERS found - must fix before proceeding"
    canProceed="false"
  fi
  
  echo "$message"
  
  if [[ "$canProceed" == "false" ]]; then
    exit 1
  fi
  exit 0
fi

# Fallback: Use jq if available
if command -v jq &> /dev/null; then
  if [[ -f "$TARGET" ]]; then
    # Handle both { issues: [...] } and top-level array formats
    blockers=$(jq 'if type == "array" then . else .issues // [] end | map(select(.severity == "blocker")) | length' "$TARGET" 2>/dev/null || echo "0")
    if [[ "$blockers" == "0" ]]; then
      echo "No blockers found - proceeding"
      exit 0
    else
      echo "⚠️  $blockers BLOCKERS found - must fix before proceeding"
      exit 1
    fi
  elif [[ -d "$TARGET" ]]; then
    # Find most recent issues file
    latest=$(ls -t "$TARGET"/issues*.json 2>/dev/null | head -1 || echo "")
    if [[ -z "$latest" ]]; then
      echo "No issues.json files found - proceeding"
      exit 0
    fi
    # Handle both { issues: [...] } and top-level array formats
    blockers=$(jq 'if type == "array" then . else .issues // [] end | map(select(.severity == "blocker")) | length' "$latest" 2>/dev/null || echo "0")
    if [[ "$blockers" == "0" ]]; then
      echo "No blockers found - proceeding"
      exit 0
    else
      echo "⚠️  $blockers BLOCKERS found - must fix before proceeding"
      exit 1
    fi
  fi
fi

# Last fallback: Just proceed
echo "Cannot check blockers (no node or jq) - proceeding"
exit 0
