#!/usr/bin/env bash
set -euo pipefail

# Oracle Single Lens Runner
# Run a single specific lens instead of the full pack.
#
# Usage:
#   ./scripts/oracle_single_lens.sh <kind> <lens> <file1> [file2...]
#
# Example:
#   ./scripts/oracle_single_lens.sh plan security artifacts/03-plan.md

KIND="${1:-}"
LENS="${2:-}"
shift 2 || true

if [[ -z "$KIND" || -z "$LENS" || "$#" -lt 1 ]]; then
  echo "Usage: ./scripts/oracle_single_lens.sh <kind> <lens> <file1> [file2...]"
  echo ""
  echo "Kinds: prd, ux, plan, code"
  echo "Lenses: product, ux, architecture, security, performance, tests, simplicity, ops"
  echo ""
  echo "Example:"
  echo "  ./scripts/oracle_single_lens.sh plan security artifacts/03-plan.md"
  exit 1
fi

# Validate kind
case "$KIND" in
  prd|ux|plan|code) ;;
  *)
    echo "Error: Invalid kind '$KIND'. Must be one of: prd, ux, plan, code"
    exit 1
    ;;
esac

# Validate lens
case "$LENS" in
  product|ux|architecture|security|performance|tests|simplicity|ops) ;;
  *)
    echo "Error: Invalid lens '$LENS'. Must be one of: product, ux, architecture, security, performance, tests, simplicity, ops"
    exit 1
    ;;
esac

PROMPT_FILE="prompts/$KIND/$LENS.txt"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Error: Prompt file not found: $PROMPT_FILE"
  exit 1
fi

OUT_DIR="artifacts/06-oracle/$KIND"
mkdir -p "$OUT_DIR"

TS="$(date +%Y%m%d-%H%M%S)"
OUT_FILE="$OUT_DIR/${TS}_${LENS}.md"

echo "🔮 Running single lens: $KIND / $LENS"
echo "   Files: $*"
echo "   Output: $OUT_FILE"
echo ""

./scripts/oracle_browser_run.sh "$PROMPT_FILE" "$OUT_FILE" "$@"

echo ""
echo "📊 Normalizing to issues.json"
node scripts/normalize_oracle_output.js "$OUT_DIR" "$OUT_DIR/issues.json" --prefix "${TS}_"

if command -v jq &> /dev/null; then
  ISSUE_COUNT=$(cat "$OUT_DIR/issues.json" | jq '.issues | length')
  echo ""
  echo "✅ Complete: $ISSUE_COUNT issues in $OUT_DIR/issues.json"
else
  echo ""
  echo "✅ Complete: $OUT_DIR/issues.json"
fi
