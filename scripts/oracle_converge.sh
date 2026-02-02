#!/bin/bash
# oracle_converge.sh - FULLY AUTOMATED Oracle convergence loop
#
# This script runs in your terminal and handles EVERYTHING:
# 1. Runs Oracle through each lens (30-90 min per lens per iteration)
# 2. Reads issues AND suggestions
# 3. Calls Claude Code to apply fixes (with fresh-eyes review)
# 4. Re-runs Oracle
# 5. Loops until converged (0 blockers/majors) or max rounds
#
# Usage:
#   ./scripts/oracle_converge.sh prd artifacts/01-prd.md artifacts/00-brief.md
#   ./scripts/oracle_converge.sh --lens product prd artifacts/01-prd.md    # Single lens
#   ./scripts/oracle_converge.sh --lens all ux artifacts/02-ux.md          # All lenses (default)
#
# Convergence rules:
#   - STOP when: blockers + majors == 0 for current lens
#   - STOP when: rounds >= MAX_ROUNDS (default: 10)
#   - Suggestions are shown but don't block convergence

set -e

MAX_ROUNDS="${MAX_ROUNDS:-10}"

# All available lenses
ALL_LENSES=(product ux architecture security performance tests simplicity ops)

# Parse arguments
LENS_ARG=""  # Empty = ask user
INTERACTIVE=true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lens)
      if [[ -z "${2:-}" ]] || [[ "$2" == --* ]]; then
        echo "ERROR: --lens requires a value (lens name or 'all')"
        exit 1
      fi
      LENS_ARG="$2"
      INTERACTIVE=false
      shift 2
      ;;
    --quick)
      LENS_ARG="product"
      INTERACTIVE=false
      shift
      ;;
    --all)
      LENS_ARG="all"
      INTERACTIVE=false
      shift
      ;;
    *)
      break
      ;;
  esac
done

KIND="${1:-}"
PRIMARY_FILE="${2:-}"
shift 2 2>/dev/null || true
CONTEXT_FILES=("$@")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_box() {
  local title="$1"
  local width=75
  echo ""
  printf "╔"; printf '═%.0s' $(seq 1 $width); printf "╗\n"
  printf "║  %-$((width-3))s║\n" "$title"
  printf "╚"; printf '═%.0s' $(seq 1 $width); printf "╝\n"
}

# Generate Oracle Request ID for tracking
# Format: #<LENS_ABBREV>-<ROUND_PADDED> (e.g., #SEC-001, #PERF-002)
get_oracle_request_id() {
  local lens="$1"
  local round="$2"
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
  printf "#%s-%03d" "$abbrev" "$round"
}

if [ -z "$KIND" ] || [ -z "$PRIMARY_FILE" ]; then
  echo "Usage: $0 [--lens <lens|all>] <kind> <primary_file> [context_files...]"
  echo ""
  echo "Examples:"
  echo "  $0 prd artifacts/01-prd.md artifacts/00-brief.md              # Interactive"
  echo "  $0 --lens product prd artifacts/01-prd.md artifacts/00-brief.md  # Single lens"
  echo "  $0 --lens all ux artifacts/02-ux.md artifacts/01-prd.md          # Explicit all"
  echo ""
  echo "Options:"
  echo "  --quick         Quick mode: product lens only (~1-2 hours)"
  echo "  --all           Full mode: all 8 lenses (~4-16 hours)"
  echo "  --lens <lens>   Run specific lens (30-90 min per lens)"
  echo "                  Lenses: product, ux, architecture, security,"
  echo "                          performance, tests, simplicity, ops"
  echo ""
  echo "Environment variables:"
  echo "  MAX_ROUNDS=10   Max iterations per lens (default: 10)"
  exit 1
fi

# Interactive mode: ask user which mode they want
if [ "$INTERACTIVE" = true ] && [ -z "$LENS_ARG" ]; then
  echo ""
  echo "╔═══════════════════════════════════════════════════════════════════════╗"
  echo "║                    ORACLE REVIEW MODE SELECTION                       ║"
  echo "╠═══════════════════════════════════════════════════════════════════════╣"
  echo "║                                                                       ║"
  echo "║  [1] QUICK MODE - Product lens only                                   ║"
  echo "║      • Time: ~1-2 hours                                               ║"
  echo "║      • Best for: Fast iteration, early drafts                         ║"
  echo "║                                                                       ║"
  echo "║  [2] FULL MODE - All 8 lenses with convergence                        ║"
  echo "║      • Time: ~4-16 hours (overnight recommended)                      ║"
  echo "║      • Best for: Final review before implementation                   ║"
  echo "║      • Lenses: product, ux, architecture, security,                   ║"
  echo "║                performance, tests, simplicity, ops                    ║"
  echo "║                                                                       ║"
  echo "║  [3] SINGLE LENS - Choose one specific lens                           ║"
  echo "║      • Time: ~30-90 min per convergence round                         ║"
  echo "║                                                                       ║"
  echo "╚═══════════════════════════════════════════════════════════════════════╝"
  echo ""
  echo -n "Select mode [1/2/3]: "
  read -r MODE_CHOICE

  case "$MODE_CHOICE" in
    1)
      LENS_ARG="product"
      echo -e "${GREEN}→ Quick mode selected (product lens only)${NC}"
      ;;
    2)
      LENS_ARG="all"
      echo -e "${GREEN}→ Full mode selected (all 8 lenses)${NC}"
      ;;
    3)
      echo ""
      echo "Available lenses:"
      for i in "${!ALL_LENSES[@]}"; do
        echo "  $((i+1)). ${ALL_LENSES[i]}"
      done
      echo ""
      echo -n "Select lens [1-8]: "
      read -r LENS_CHOICE
      if [[ "$LENS_CHOICE" =~ ^[1-8]$ ]]; then
        LENS_ARG="${ALL_LENSES[$((LENS_CHOICE-1))]}"
        echo -e "${GREEN}→ Single lens selected: $LENS_ARG${NC}"
      else
        echo -e "${RED}Invalid choice. Using quick mode (product).${NC}"
        LENS_ARG="product"
      fi
      ;;
    *)
      echo -e "${YELLOW}Invalid choice. Using quick mode (product).${NC}"
      LENS_ARG="product"
      ;;
  esac
  echo ""
fi

# Build lens list based on --lens argument
if [ "$LENS_ARG" = "all" ]; then
  LENSES_TO_RUN=("${ALL_LENSES[@]}")

  # For PRD phase: ask if simplicity lens should be included
  if [ "$KIND" = "prd" ] && [ "$INTERACTIVE" = true ]; then
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  OPTIONAL: Simplicity Lens${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  The simplicity lens checks for over-engineering and scope creep."
    echo "  It's useful for catching unnecessary complexity early, but may"
    echo "  flag intentional architectural decisions as issues."
    echo ""
    echo -n "  Include simplicity lens? [y/N]: "
    read -r SIMPLICITY_CHOICE
    if [[ ! "$SIMPLICITY_CHOICE" =~ ^[Yy](es)?$ ]]; then
      # Remove simplicity from lenses
      LENSES_TO_RUN=()
      for l in "${ALL_LENSES[@]}"; do
        [ "$l" != "simplicity" ] && LENSES_TO_RUN+=("$l")
      done
      echo -e "  ${YELLOW}→ Simplicity lens excluded${NC}"
    else
      echo -e "  ${GREEN}→ Simplicity lens included${NC}"
    fi
    echo ""
  fi
else
  # Validate single lens
  VALID_LENS=false
  for l in "${ALL_LENSES[@]}"; do
    [ "$l" = "$LENS_ARG" ] && VALID_LENS=true && break
  done
  if [ "$VALID_LENS" = false ]; then
    echo -e "${RED}ERROR: Invalid lens '$LENS_ARG'. Valid lenses: ${ALL_LENSES[*]}${NC}"
    exit 1
  fi
  LENSES_TO_RUN=("$LENS_ARG")
fi

# Check dependencies
if ! command -v npx &> /dev/null; then
  echo -e "${RED}ERROR: npx not found. Install Node.js.${NC}"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo -e "${YELLOW}WARNING: jq not found. Issue counting will be limited.${NC}"
fi

# Validate files
if [ ! -f "$PRIMARY_FILE" ]; then
  echo -e "${RED}ERROR: Primary file not found: $PRIMARY_FILE${NC}"
  exit 1
fi

for f in "${CONTEXT_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo -e "${RED}ERROR: Context file not found: $f${NC}"
    exit 1
  fi
done

# Setup
OUTPUT_DIR="artifacts/06-oracle/$KIND"
mkdir -p "$OUTPUT_DIR"

print_box "ORACLE CONVERGENCE LOOP v2.2"
echo ""
echo "  Kind:       $KIND"
echo "  Primary:    $PRIMARY_FILE"
echo "  Context:    ${CONTEXT_FILES[*]:-none}"
echo "  Max rounds: $MAX_ROUNDS per lens"
echo "  Lenses:     ${LENSES_TO_RUN[*]}"
echo ""
echo -e "  ${GREEN}✓ Oracle will AUTO-OPEN Chromium and start immediately${NC}"
echo -e "  ${YELLOW}  Each lens: Oracle (30-90 min/round) + Apply fixes until converged${NC}"
if [ "${#LENSES_TO_RUN[@]}" -gt 1 ]; then
  echo -e "  ${YELLOW}  Total time estimate: ${#LENSES_TO_RUN[@]}-$((${#LENSES_TO_RUN[@]} * 4)) hours (${#LENSES_TO_RUN[@]} lenses)${NC}"
fi
echo ""
echo -e "  ${CYAN}💡 Tip: Keep Chromium window open. Go grab a coffee! ☕${NC}"
echo ""

# Track overall progress
TOTAL_LENSES=${#LENSES_TO_RUN[@]}
CONVERGED_LENSES=0
LENS_INDEX=0

# Outer loop: each lens
for LENS in "${LENSES_TO_RUN[@]}"; do
  LENS_INDEX=$((LENS_INDEX + 1))

  print_box "LENS $LENS_INDEX/$TOTAL_LENSES: $LENS"
  echo ""

  # Reset per-lens state
  LENS_HISTORY_FILE="$OUTPUT_DIR/convergence-${LENS}.json"

  # Check for existing lens state - resume if possible
  RESUME_ROUND=1
  if [ -f "$LENS_HISTORY_FILE" ]; then
    EXISTING_ROUNDS=$(jq -r '.rounds | length' "$LENS_HISTORY_FILE" 2>/dev/null || echo "0")
    if [ "$EXISTING_ROUNDS" -gt 0 ]; then
      LAST_ROUND=$(jq -r '.rounds[-1]' "$LENS_HISTORY_FILE" 2>/dev/null)
      LAST_BLOCKERS=$(echo "$LAST_ROUND" | jq -r '.blockers // 999')
      LAST_MAJORS=$(echo "$LAST_ROUND" | jq -r '.majors // 999')

      if [ "$LAST_BLOCKERS" -eq 0 ] && [ "$LAST_MAJORS" -eq 0 ]; then
        echo -e "${GREEN}✅ Lens '$LENS' already converged! Skipping...${NC}"
        CONVERGED_LENSES=$((CONVERGED_LENSES + 1))
        continue
      fi

      RESUME_ROUND=$((EXISTING_ROUNDS + 1))
      echo -e "${YELLOW}📍 Resuming lens '$LENS' from round $RESUME_ROUND${NC}"
    fi
  else
    echo '{"lens": "'"$LENS"'", "rounds": []}' > "$LENS_HISTORY_FILE"
  fi

  # Convergence history for this lens (reset each lens iteration)
  HISTORY=()

  ROUND=$RESUME_ROUND
  PREV_BLOCKING=999
  STUCK_COUNT=0  # Track consecutive rounds with same blocking count

  # Inner loop: convergence for this lens
  while [ "$ROUND" -le "$MAX_ROUNDS" ]; do
    print_box "LENS: $LENS | ROUND $ROUND of $MAX_ROUNDS"
  
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    OUTPUT_FILE="$OUTPUT_DIR/${TIMESTAMP}_${LENS}.md"
    ISSUES_FILE="$OUTPUT_DIR/issues-${LENS}-round${ROUND}.json"
  
  # Build file arguments as array (safe for paths with spaces)
  FILE_ARGS_ARRAY=("--file" "$PRIMARY_FILE")
  for f in "${CONTEXT_FILES[@]}"; do
    FILE_ARGS_ARRAY+=("--file" "$f")
  done
  
  # Check if prompt file exists
  PROMPT_FILE="prompts/$KIND/$LENS.txt"
  if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED}ERROR: Prompt file not found: $PROMPT_FILE${NC}"
    exit 1
  fi
  
  echo ""
  echo -e "${BLUE}🔮 Phase 1: Running Oracle ($LENS lens)...${NC}"
  echo "   Started: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "   Output:  $OUTPUT_FILE"
  echo ""
  echo -e "   ${YELLOW}This takes 30-90 minutes. GPT-5.2 Pro is thinking deeply. ☕${NC}"
  echo -e "   ${YELLOW}Keep the Chromium window open until Oracle finishes!${NC}"
  echo ""
  
  # Run Oracle with retry logic (3 attempts before manual fallback)
  # Uses --browser-manual-login for persistent Chromium profile (no cookie sync needed)
  MAX_ATTEMPTS=3
  ATTEMPT=1
  ORACLE_SUCCESS=false

  # Generate Oracle Request ID for tracking (e.g., #SEC-001)
  ORACLE_REQUEST_ID=$(get_oracle_request_id "$LENS" "$ROUND")
  echo -e "   ${CYAN}Request ID: $ORACLE_REQUEST_ID${NC}"

  while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo -e "${BLUE}   Oracle attempt $ATTEMPT of $MAX_ATTEMPTS...${NC}"

    set +e
    npx -y @steipete/oracle \
      --engine browser \
      --browser-manual-login \
      --browser-no-cookie-sync \
      --model gpt-5.2-pro \
      --timeout auto \
      --browser-attachments auto \
      --force \
      --prompt "$ORACLE_REQUEST_ID

$(cat "$PROMPT_FILE")" \
      "${FILE_ARGS_ARRAY[@]}" \
      --write-output "$OUTPUT_FILE" 2>&1 | tee "$OUTPUT_DIR/oracle-${LENS}-round${ROUND}-attempt${ATTEMPT}.log"
    ORACLE_EXIT=${PIPESTATUS[0]}
    set -e
    
    if [ $ORACLE_EXIT -eq 0 ] && [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
      ORACLE_SUCCESS=true
      break
    fi
    
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
      WAIT_TIME=$((ATTEMPT * 10))  # 10s, 20s, 30s
      echo -e "${YELLOW}   ⚠️ Attempt $ATTEMPT failed. Retrying in ${WAIT_TIME}s... (attempt $((ATTEMPT+1))/$MAX_ATTEMPTS)${NC}"
      sleep $WAIT_TIME
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
  done
  
  if [ "$ORACLE_SUCCESS" = false ]; then
    echo ""
    echo -e "${RED}⚠️  Oracle automation failed after $MAX_ATTEMPTS attempts.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Make sure Chromium is installed"
    echo "  2. Keep the Chromium window OPEN during Oracle runs"
    echo "  3. Log into ChatGPT in the Chromium window that opens"
    echo ""
    echo "Manual fallback:"
    echo ""
    echo "  1. Copy the prompt bundle to clipboard:"
    echo "     npx -y @steipete/oracle --render --copy-markdown \\"
    echo "       --prompt \"\$(cat '$PROMPT_FILE')\" \\"
    # Build properly quoted file arguments for display
    QUOTED_FILE_ARGS=""
    for arg in "${FILE_ARGS_ARRAY[@]}"; do
      if [[ "$arg" == --* ]]; then
        QUOTED_FILE_ARGS="$QUOTED_FILE_ARGS $arg"
      else
        QUOTED_FILE_ARGS="$QUOTED_FILE_ARGS \"$arg\""
      fi
    done
    echo "      $QUOTED_FILE_ARGS"
    echo ""
    echo "  2. In ChatGPT (GPT-5.2 Pro), start with this Request ID:"
    echo "     $ORACLE_REQUEST_ID"
    echo ""
    echo "  3. Paste the prompt bundle after the Request ID"
    echo ""
    echo "  4. Save the response to:"
    echo "     $OUTPUT_FILE"
    echo ""
    echo "After saving, press ENTER to continue (or type 'skip' to skip this lens)..."
    read -r USER_RESPONSE

    if [[ "${USER_RESPONSE,,}" = "skip" ]]; then
      echo -e "${YELLOW}Skipping lens '$LENS' as requested.${NC}"
      break
    fi

    # Check if file was created manually
    if [ ! -f "$OUTPUT_FILE" ] || [ ! -s "$OUTPUT_FILE" ]; then
      echo -e "${RED}ERROR: Output file still missing or empty: $OUTPUT_FILE${NC}"
      exit 1
    fi
  fi
  
  echo ""
  echo "   Completed: $(date '+%Y-%m-%d %H:%M:%S')"
  
  # Parse results
  echo ""
  echo -e "${BLUE}📊 Phase 2: Parsing results...${NC}"
  
  # Try to extract JSON from output (takes first json block only)
  if [ -f "$OUTPUT_FILE" ]; then
    # Extract first JSON block from markdown output
    # Uses awk to stop after first complete block, avoiding concatenation of multiple blocks
    awk '/```json/{found=1; next} found && /```/{exit} found{print}' "$OUTPUT_FILE" > "$ISSUES_FILE" 2>/dev/null || true
  fi
  
  # Count issues
  BLOCKERS=0
  MAJORS=0
  MINORS=0
  NITS=0
  SUGGESTIONS=0
  CONFIDENCE=0
  READY="unknown"
  
  if [ -f "$ISSUES_FILE" ] && [ -s "$ISSUES_FILE" ] && command -v jq &> /dev/null; then
    BLOCKERS=$(jq '[.issues[]? | select(.severity == "blocker")] | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    MAJORS=$(jq '[.issues[]? | select(.severity == "major")] | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    MINORS=$(jq '[.issues[]? | select(.severity == "minor")] | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    NITS=$(jq '[.issues[]? | select(.severity == "nit")] | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    SUGGESTIONS=$(jq '.suggestions | length' "$ISSUES_FILE" 2>/dev/null || echo "0")
    CONFIDENCE=$(jq '.overallAssessment.confidenceScore // 0' "$ISSUES_FILE" 2>/dev/null || echo "0")
    READY=$(jq -r '.overallAssessment.readyForImplementation // "unknown"' "$ISSUES_FILE" 2>/dev/null || echo "unknown")
  fi
  
  TOTAL=$((BLOCKERS + MAJORS + MINORS + NITS))
  BLOCKING=$((BLOCKERS + MAJORS))
  
  # Record history
  HISTORY+=("Round $ROUND: $BLOCKERS blocker, $MAJORS major, $MINORS minor, $NITS nit | $SUGGESTIONS suggestions | confidence: $CONFIDENCE")
  
  # Update lens-specific history file (with error handling for malformed JSON)
  if command -v jq &> /dev/null; then
    if jq ".rounds += [{\"round\": $ROUND, \"blockers\": $BLOCKERS, \"majors\": $MAJORS, \"minors\": $MINORS, \"nits\": $NITS, \"suggestions\": $SUGGESTIONS, \"confidence\": $CONFIDENCE}]" "$LENS_HISTORY_FILE" > "$LENS_HISTORY_FILE.tmp" 2>/dev/null; then
      mv "$LENS_HISTORY_FILE.tmp" "$LENS_HISTORY_FILE"
    else
      echo -e "${YELLOW}Warning: Could not update history file, reinitializing...${NC}"
      rm -f "$LENS_HISTORY_FILE.tmp"
      echo "{\"lens\": \"$LENS\", \"rounds\": [{\"round\": $ROUND, \"blockers\": $BLOCKERS, \"majors\": $MAJORS, \"minors\": $MINORS, \"nits\": $NITS, \"suggestions\": $SUGGESTIONS, \"confidence\": $CONFIDENCE}]}" > "$LENS_HISTORY_FILE"
    fi
  fi
  
  echo ""
  echo "┌─────────────────────────────────────────────────────────────┐"
  printf "│  %-57s │\n" "Round $ROUND Results"
  echo "├─────────────────────────────────────────────────────────────┤"
  printf "│  ${RED}Blockers:${NC}    %-46s │\n" "$BLOCKERS"
  printf "│  ${YELLOW}Majors:${NC}      %-46s │\n" "$MAJORS"
  printf "│  Minors:     %-46s │\n" "$MINORS"
  printf "│  Nits:       %-46s │\n" "$NITS"
  echo "├─────────────────────────────────────────────────────────────┤"
  printf "│  ${CYAN}Suggestions:${NC} %-46s │\n" "$SUGGESTIONS"
  printf "│  Confidence: %-46s │\n" "$CONFIDENCE/10"
  printf "│  Ready:      %-46s │\n" "$READY"
  echo "└─────────────────────────────────────────────────────────────┘"
  
  # Check convergence for this lens
  if [ "$BLOCKING" -eq 0 ]; then
    print_box "✅ LENS '$LENS' CONVERGED after $ROUND round(s)!"
    echo ""
    echo -e "${GREEN}No blockers or major issues remaining for $LENS lens.${NC}"
    if [ "$MINORS" -gt 0 ] || [ "$NITS" -gt 0 ]; then
      echo "Deferred: $MINORS minor(s), $NITS nit(s)"
    fi
    echo ""
    echo "Lens History:"
    for h in "${HISTORY[@]}"; do
      echo "  $h"
    done
    echo ""
    CONVERGED_LENSES=$((CONVERGED_LENSES + 1))
    [ -f "$ISSUES_FILE" ] && cp "$ISSUES_FILE" "$OUTPUT_DIR/issues-${LENS}.json"
    break  # Exit inner loop, continue to next lens
  fi
  
  # Check if stuck (same blocking count for multiple consecutive rounds)
  if [ "$BLOCKING" -eq "$PREV_BLOCKING" ]; then
    STUCK_COUNT=$((STUCK_COUNT + 1))
  else
    STUCK_COUNT=0
  fi

  if [ "$STUCK_COUNT" -ge 2 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Same number of blocking issues ($BLOCKING) for $((STUCK_COUNT + 1)) consecutive rounds.${NC}"
    echo "   This may indicate false positives or unresolvable issues."
    echo ""
  fi
  PREV_BLOCKING=$BLOCKING
  
  if [ "$ROUND" -eq "$MAX_ROUNDS" ]; then
    print_box "⚠️  LENS '$LENS' MAX ROUNDS ($MAX_ROUNDS) reached"
    echo ""
    echo -e "${YELLOW}Remaining for $LENS: $BLOCKERS blocker(s), $MAJORS major(s)${NC}"
    echo ""
    echo "Lens History:"
    for h in "${HISTORY[@]}"; do
      echo "  $h"
    done
    echo ""
    [ -f "$ISSUES_FILE" ] && cp "$ISSUES_FILE" "$OUTPUT_DIR/issues-${LENS}.json"
    break  # Move to next lens even if not converged
  fi
  
  # Apply fixes
  echo ""
  echo -e "${BLUE}📝 Phase 3: Apply fixes via Claude Code...${NC}"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  APPLY FEEDBACK FOR LENS: $LENS"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "In Claude Code, run:"
  echo ""
  echo -e "  ${GREEN}/oracle $KIND${NC}"
  echo ""
  echo "This will:"
  echo "  1. Read the Oracle output from $OUTPUT_FILE"
  echo "  2. Evaluate each issue critically"
  echo "  3. Apply fixes to $PRIMARY_FILE"
  echo "  4. Run fresh-eyes review"
  echo "  5. Report what was applied/dismissed"
  echo ""
  echo -e "${YELLOW}Press ENTER when fixes are applied to continue to round $((ROUND + 1))...${NC}"
  read -r

  ROUND=$((ROUND + 1))
  done  # End inner while loop (rounds for this lens)

done  # End outer for loop (each lens)

# Final summary
echo ""
print_box "ALL LENSES COMPLETE"
echo ""
echo "  Converged: $CONVERGED_LENSES / $TOTAL_LENSES lenses"
echo "  Output:    $OUTPUT_DIR/"
echo ""

# Merge all lens issues into combined issues.json
if command -v jq &> /dev/null; then
  LENS_FILES=("$OUTPUT_DIR"/issues-*.json)
  if [ -e "${LENS_FILES[0]}" ]; then
    echo "Merging all lens issues..."
    # Use unique_by with fallback for issues without title field
    jq -s '{
      issues: [.[].issues[]?] | unique_by(.title // .description // .id // (. | tostring)),
      suggestions: [.[].suggestions[]?] | unique
    }' "${LENS_FILES[@]}" > "$OUTPUT_DIR/issues.json" 2>/dev/null || echo -e "${YELLOW}Warning: Could not merge issues files${NC}"
  fi
fi

if [ "$CONVERGED_LENSES" -eq "$TOTAL_LENSES" ]; then
  echo -e "${GREEN}✅ ALL LENSES CONVERGED!${NC}"
  echo ""
  echo "Next step:"
  case "$KIND" in
    prd) echo -e "  ${GREEN}/ux${NC} - Generate UX specification" ;;
    ux)  echo -e "  ${GREEN}/plan${NC} - Generate implementation plan" ;;
    plan)
      echo -e "  ${GREEN}Auto-compiling task graph...${NC}"
      if command -v node &> /dev/null && [ -f "scripts/compile_task_graph.js" ]; then
        node scripts/compile_task_graph.js \
          --plan artifacts/03-plan.md \
          --issues "$OUTPUT_DIR/issues.json" \
          --out artifacts/04-task-graph.json 2>/dev/null || true

        if [ -f "artifacts/04-task-graph.json" ]; then
          TASK_COUNT=$(jq '.tasks | length' artifacts/04-task-graph.json 2>/dev/null || echo "?")
          echo -e "  ${GREEN}✅ Task graph compiled: $TASK_COUNT tasks${NC}"
        fi
      fi
      echo ""
      echo "Next steps:"
      echo -e "  1. ${GREEN}bash artifacts/04-beads-setup.sh${NC}  # Create beads from tasks"
      echo -e "  2. ${GREEN}/review beads${NC}                     # Run 6-9 times!"
      echo -e "  3. ${GREEN}./scripts/ralph.sh --beads --fresh-eyes 100${NC}"
      ;;
    code) echo -e "  ${GREEN}/gates${NC} - Run quality gates" ;;
  esac
  exit 0
else
  echo -e "${YELLOW}⚠️  Some lenses did not converge (hit max rounds).${NC}"
  echo ""
  echo "Options:"
  echo "  1. Review remaining issues manually (may be false positives)"
  # Build properly quoted command suggestions
  CONTEXT_ARGS=""
  for f in "${CONTEXT_FILES[@]}"; do
    CONTEXT_ARGS="$CONTEXT_ARGS \"$f\""
  done
  echo "  2. Increase rounds: MAX_ROUNDS=15 $0 --lens all $KIND \"$PRIMARY_FILE\"$CONTEXT_ARGS"
  echo "  3. Re-run specific lens: $0 --lens <lens> $KIND \"$PRIMARY_FILE\"$CONTEXT_ARGS"
  exit 1
fi
