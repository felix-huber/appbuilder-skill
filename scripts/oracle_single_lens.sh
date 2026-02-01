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

# Generate Oracle Request ID for tracking
get_oracle_request_id() {
  local lens="$1"
  local abbrev
  case "$lens" in
    product)      abbrev="PROD" ;;
    ux)           abbrev="UX" ;;
    architecture) abbrev="ARCH" ;;
    security)     abbrev="SEC" ;;
    performance)  abbrev="PERF" ;;
    tests)        abbrev="TEST" ;;
    simplicity)   abbrev="SIMP" ;;
    ops)          abbrev="OPS" ;;
    *)            abbrev=$(echo "$lens" | tr '[:lower:]' '[:upper:]' | cut -c1-4) ;;
  esac
  printf "#%s-001" "$abbrev"
}

ORACLE_REQUEST_ID=$(get_oracle_request_id "$LENS")

echo "🔮 Running single lens: $KIND / $LENS"
echo "   Request ID: $ORACLE_REQUEST_ID"
echo "   Files: $*"
echo "   Output: $OUT_FILE"
echo ""

# Create temp prompt file with Request ID prepended
TEMP_PROMPT=$(mktemp)
trap 'rm -f "$TEMP_PROMPT"' EXIT

echo "$ORACLE_REQUEST_ID" > "$TEMP_PROMPT"
echo "" >> "$TEMP_PROMPT"
cat "$PROMPT_FILE" >> "$TEMP_PROMPT"

./scripts/oracle_browser_run.sh "$TEMP_PROMPT" "$OUT_FILE" "$@"

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
