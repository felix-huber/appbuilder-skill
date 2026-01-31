#!/usr/bin/env bash
# gather_task_context.sh - Smart context collection for long-context models
#
# Collects comprehensive context for Oracle/Gemini (1M+ token windows):
# - Full source files mentioned in task
# - Import/export chains
# - Dependent files (what imports these)
# - Similar patterns in codebase
# - Test files
# - Recent git changes

set -euo pipefail

TASK_FILE="${1:-}"
OUTPUT_DIR="${2:-/tmp/task_context}"

if [[ -z "$TASK_FILE" ]]; then
  echo "Usage: $0 <task_file> [output_dir]"
  echo "  task_file: Path to task JSON or markdown file"
  echo "  output_dir: Where to write context (default: /tmp/task_context)"
  exit 1
fi

if [[ ! -f "$TASK_FILE" ]]; then
  echo "Error: Task file not found: $TASK_FILE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# Extract files from task description
extract_files_from_task() {
  local task_file="$1"
  # Look for file paths in the task (src/..., lib/..., etc.)
  grep -oE '(src|lib|app|components|pages|utils|hooks|services|api|workers)/[a-zA-Z0-9_/.-]+\.(ts|tsx|js|jsx|py|rs|go)' "$task_file" 2>/dev/null | sort -u || true
}

# Find what imports a given file
find_dependents() {
  local file="$1"
  local basename
  basename=$(basename "$file" | sed 's/\.[^.]*$//')

  # Search for imports of this file
  rg -l "(import.*from.*['\"].*${basename}['\"]|require\(['\"].*${basename}['\"])" --glob '*.{ts,tsx,js,jsx}' 2>/dev/null | head -20 || true
}

# Find what a file imports
find_imports() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return
  fi

  # Extract import paths
  grep -E "^import|^from|require\(" "$file" 2>/dev/null | \
    grep -oE "['\"]\.?\.?/[^'\"]+['\"]" | \
    tr -d "'\""  | \
    head -30 || true
}

# Find similar patterns in codebase
find_similar_patterns() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return
  fi

  # Extract function/class names from the file
  local patterns
  patterns=$(grep -oE "(function|class|const|export)\s+[A-Z][a-zA-Z0-9]+" "$file" 2>/dev/null | \
    awk '{print $2}' | head -5)

  for pattern in $patterns; do
    # Find similar named things elsewhere
    rg -l "\b${pattern}\b" --glob '*.{ts,tsx,js,jsx}' 2>/dev/null | grep -v "$file" | head -3 || true
  done | sort -u
}

# Find test files for source files
find_test_files() {
  local file="$1"
  local basename
  basename=$(basename "$file" | sed 's/\.[^.]*$//')

  # Common test file patterns
  find . -type f \( \
    -name "${basename}.test.*" -o \
    -name "${basename}.spec.*" -o \
    -name "${basename}_test.*" -o \
    -name "test_${basename}.*" \
  \) 2>/dev/null | head -5 || true
}

# Get recent git changes for a file
get_recent_changes() {
  local file="$1"
  if [[ -f "$file" ]]; then
    git log --oneline -5 -- "$file" 2>/dev/null || true
  fi
}

# Main collection logic
echo "=== Gathering Task Context ===" > "$OUTPUT_DIR/context.md"
echo "" >> "$OUTPUT_DIR/context.md"
echo "Task file: $TASK_FILE" >> "$OUTPUT_DIR/context.md"
echo "Generated: $(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$OUTPUT_DIR/context.md"
echo "" >> "$OUTPUT_DIR/context.md"

# Extract files mentioned in task
echo "## Files Mentioned in Task" >> "$OUTPUT_DIR/context.md"
task_files=$(extract_files_from_task "$TASK_FILE")
echo "$task_files" >> "$OUTPUT_DIR/context.md"
echo "" >> "$OUTPUT_DIR/context.md"

# For each task file, gather comprehensive context
all_source_files=""
all_dependent_files=""
all_imported_files=""
all_test_files=""
all_similar_files=""

for file in $task_files; do
  if [[ -f "$file" ]]; then
    all_source_files="$all_source_files $file"

    # Find dependents
    dependents=$(find_dependents "$file")
    all_dependent_files="$all_dependent_files $dependents"

    # Find imports
    imports=$(find_imports "$file")
    for imp in $imports; do
      # Resolve relative paths
      dir=$(dirname "$file")
      resolved="${dir}/${imp}"
      # Try common extensions
      for ext in "" ".ts" ".tsx" ".js" ".jsx"; do
        if [[ -f "${resolved}${ext}" ]]; then
          all_imported_files="$all_imported_files ${resolved}${ext}"
          break
        fi
        # Try index files
        if [[ -f "${resolved}/index${ext}" ]]; then
          all_imported_files="$all_imported_files ${resolved}/index${ext}"
          break
        fi
      done
    done

    # Find tests
    tests=$(find_test_files "$file")
    all_test_files="$all_test_files $tests"

    # Find similar patterns
    similar=$(find_similar_patterns "$file")
    all_similar_files="$all_similar_files $similar"
  fi
done

# Deduplicate
all_source_files=$(echo "$all_source_files" | tr ' ' '\n' | sort -u | tr '\n' ' ')
all_dependent_files=$(echo "$all_dependent_files" | tr ' ' '\n' | sort -u | tr '\n' ' ')
all_imported_files=$(echo "$all_imported_files" | tr ' ' '\n' | sort -u | tr '\n' ' ')
all_test_files=$(echo "$all_test_files" | tr ' ' '\n' | sort -u | tr '\n' ' ')
all_similar_files=$(echo "$all_similar_files" | tr ' ' '\n' | sort -u | tr '\n' ' ')

# Write source files
echo "## Source Files (Full Content)" >> "$OUTPUT_DIR/context.md"
for file in $all_source_files; do
  if [[ -f "$file" ]]; then
    ext="${file##*.}"
    line_count=$(wc -l < "$file" | tr -d ' ')
    echo "" >> "$OUTPUT_DIR/context.md"
    echo "### $file ($line_count lines)" >> "$OUTPUT_DIR/context.md"
    echo '```'"$ext" >> "$OUTPUT_DIR/context.md"
    cat "$file" >> "$OUTPUT_DIR/context.md"
    echo "" >> "$OUTPUT_DIR/context.md"  # Ensure newline before closing backticks
    echo '```' >> "$OUTPUT_DIR/context.md"

    # Include recent changes
    changes=$(get_recent_changes "$file")
    if [[ -n "$changes" ]]; then
      echo "" >> "$OUTPUT_DIR/context.md"
      echo "**Recent commits:**" >> "$OUTPUT_DIR/context.md"
      echo '```' >> "$OUTPUT_DIR/context.md"
      echo "$changes" >> "$OUTPUT_DIR/context.md"
      echo '```' >> "$OUTPUT_DIR/context.md"
    fi
  fi
done

# Write dependent files
echo "" >> "$OUTPUT_DIR/context.md"
echo "## Dependent Files (What Imports These)" >> "$OUTPUT_DIR/context.md"
for file in $all_dependent_files; do
  if [[ -f "$file" ]]; then
    ext="${file##*.}"
    echo "" >> "$OUTPUT_DIR/context.md"
    echo "### $file" >> "$OUTPUT_DIR/context.md"
    echo '```'"$ext" >> "$OUTPUT_DIR/context.md"
    cat "$file" >> "$OUTPUT_DIR/context.md"
    echo "" >> "$OUTPUT_DIR/context.md"
    echo '```' >> "$OUTPUT_DIR/context.md"
  fi
done

# Write imported files
echo "" >> "$OUTPUT_DIR/context.md"
echo "## Imported Files (Dependencies)" >> "$OUTPUT_DIR/context.md"
for file in $all_imported_files; do
  if [[ -f "$file" ]]; then
    ext="${file##*.}"
    echo "" >> "$OUTPUT_DIR/context.md"
    echo "### $file" >> "$OUTPUT_DIR/context.md"
    echo '```'"$ext" >> "$OUTPUT_DIR/context.md"
    cat "$file" >> "$OUTPUT_DIR/context.md"
    echo "" >> "$OUTPUT_DIR/context.md"
    echo '```' >> "$OUTPUT_DIR/context.md"
  fi
done

# Write test files
echo "" >> "$OUTPUT_DIR/context.md"
echo "## Test Files" >> "$OUTPUT_DIR/context.md"
for file in $all_test_files; do
  if [[ -f "$file" ]]; then
    ext="${file##*.}"
    echo "" >> "$OUTPUT_DIR/context.md"
    echo "### $file" >> "$OUTPUT_DIR/context.md"
    echo '```'"$ext" >> "$OUTPUT_DIR/context.md"
    cat "$file" >> "$OUTPUT_DIR/context.md"
    echo "" >> "$OUTPUT_DIR/context.md"
    echo '```' >> "$OUTPUT_DIR/context.md"
  fi
done

# Write similar pattern files
echo "" >> "$OUTPUT_DIR/context.md"
echo "## Similar Patterns in Codebase" >> "$OUTPUT_DIR/context.md"
for file in $all_similar_files; do
  if [[ -f "$file" ]]; then
    ext="${file##*.}"
    echo "" >> "$OUTPUT_DIR/context.md"
    echo "### $file" >> "$OUTPUT_DIR/context.md"
    echo '```'"$ext" >> "$OUTPUT_DIR/context.md"
    cat "$file" >> "$OUTPUT_DIR/context.md"
    echo "" >> "$OUTPUT_DIR/context.md"
    echo '```' >> "$OUTPUT_DIR/context.md"
  fi
done

# Summary
echo "" >> "$OUTPUT_DIR/context.md"
echo "## Summary" >> "$OUTPUT_DIR/context.md"
echo "- Source files: $(echo "$all_source_files" | wc -w | tr -d ' ')" >> "$OUTPUT_DIR/context.md"
echo "- Dependent files: $(echo "$all_dependent_files" | wc -w | tr -d ' ')" >> "$OUTPUT_DIR/context.md"
echo "- Imported files: $(echo "$all_imported_files" | wc -w | tr -d ' ')" >> "$OUTPUT_DIR/context.md"
echo "- Test files: $(echo "$all_test_files" | wc -w | tr -d ' ')" >> "$OUTPUT_DIR/context.md"
echo "- Similar patterns: $(echo "$all_similar_files" | wc -w | tr -d ' ')" >> "$OUTPUT_DIR/context.md"

# Output path for next step
echo "$OUTPUT_DIR/context.md"
