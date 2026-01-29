#!/usr/bin/env bash
set -euo pipefail

# Oracle Lens Pack Runner
# Runs all 8 review lenses for a given phase using Oracle browser mode.
#
# Usage:
#   ./scripts/oracle_lens_pack.sh <kind: prd|ux|plan|code> <file1> [file2...]
#
# Example:
#   ./scripts/oracle_lens_pack.sh prd artifacts/01-prd.md artifacts/00-brief.md
#   ./scripts/oracle_lens_pack.sh plan artifacts/03-plan.md artifacts/01-prd.md artifacts/02-ux.md

KIND="${1:-}"
shift || true

if [[ -z "$KIND" || "$#" -lt 1 ]]; then
  echo "Usage: ./scripts/oracle_lens_pack.sh <kind: prd|ux|plan|code> <file1> [file2...]"
  echo ""
  echo "Kinds:"
  echo "  prd  — Review product requirements"
  echo "  ux   — Review UX specification"
  echo "  plan — Review implementation plan"
  echo "  code — Review code files"
  echo ""
  echo "Example:"
  echo "  ./scripts/oracle_lens_pack.sh prd artifacts/01-prd.md artifacts/00-brief.md"
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

# Check for jq (required for summary)
if ! command -v jq &> /dev/null; then
  echo "Warning: jq not found. Install jq for issue summary."
fi

# Create output directory
OUT_DIR="artifacts/06-oracle/$KIND"
mkdir -p "$OUT_DIR"

# Define lenses (keep this list small and high-signal)
LENSES=(product ux architecture security performance tests simplicity ops)

# Timestamp for this run
TS="$(date +%Y%m%d-%H%M%S)"

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║            ORACLE LENS PACK: $KIND"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║ Lenses: ${LENSES[*]}"
echo "║ Files: $*"
echo "║ Output: $OUT_DIR"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Run each lens
for LENS in "${LENSES[@]}"; do
  PROMPT_FILE="prompts/$KIND/$LENS.txt"
  
  if [[ ! -f "$PROMPT_FILE" ]]; then
    echo "⚠️  Missing prompt: $PROMPT_FILE (skipping)"
    continue
  fi
  
  OUT_FILE="$OUT_DIR/${TS}_${LENS}.md"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔮 Running lens: $LENS"
  echo "   Prompt: $PROMPT_FILE"
  echo "   Output: $OUT_FILE"
  echo ""
  
  # Run Oracle browser mode
  ./scripts/oracle_browser_run.sh "$PROMPT_FILE" "$OUT_FILE" "$@"
  
  echo "   ✅ Complete: $OUT_FILE"
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Normalizing Oracle outputs to issues.json"
echo ""

# Normalize all outputs into issues.json (using prefix to isolate this run)
node scripts/normalize_oracle_output.js "$OUT_DIR" "$OUT_DIR/issues.json" --prefix "${TS}_"

# Report summary
if command -v jq &> /dev/null; then
  ISSUE_COUNT=$(cat "$OUT_DIR/issues.json" | jq '.issues | length')
  BLOCKER_COUNT=$(cat "$OUT_DIR/issues.json" | jq '[.issues[] | select(.severity == "blocker")] | length')
  MAJOR_COUNT=$(cat "$OUT_DIR/issues.json" | jq '[.issues[] | select(.severity == "major")] | length')
else
  ISSUE_COUNT="?"
  BLOCKER_COUNT="?"
  MAJOR_COUNT="?"
fi

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    ORACLE COMPLETE                            ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║ Total issues: $ISSUE_COUNT"
echo "║ Blockers: $BLOCKER_COUNT"
echo "║ Major: $MAJOR_COUNT"
echo "║ Output: $OUT_DIR/issues.json"
echo "╚═══════════════════════════════════════════════════════════════╝"

if command -v jq &> /dev/null && [[ "$BLOCKER_COUNT" -gt 0 ]]; then
  echo ""
  echo "⚠️  BLOCKERS FOUND — Address before proceeding:"
  cat "$OUT_DIR/issues.json" | jq -r '.issues[] | select(.severity == "blocker") | "  - \(.title)"'
fi
