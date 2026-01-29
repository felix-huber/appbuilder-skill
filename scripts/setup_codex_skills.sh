#!/bin/bash
set -euo pipefail

# Setup Oracle Swarm skills for Codex CLI
# Creates symlinks so skills work in both Claude Code and Codex

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║  Oracle Swarm Extension - Codex Skills Setup                  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Must run from project root (where skills/ exists)
if [ ! -d "skills" ]; then
  echo "❌ Error: Must run from project root (where skills/ directory exists)"
  echo "   cd your-project && ./scripts/setup_codex_skills.sh"
  exit 1
fi

# Create .codex/skills directory
mkdir -p .codex/skills

echo "Creating symlinks in .codex/skills/..."
echo ""

# Symlink each skill (relative paths so they work when repo is moved)
for skill_dir in skills/*/; do
  if [ -f "${skill_dir}SKILL.md" ]; then
    skill_name=$(basename "$skill_dir")
    link_path=".codex/skills/$skill_name"
    target_path="../../skills/$skill_name"
    
    # Remove existing (symlink or directory)
    rm -rf "$link_path"
    
    # Create symlink
    ln -s "$target_path" "$link_path"
    
    echo "  ✓ $skill_name -> $target_path"
  fi
done

echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Setup complete! Skills are symlinked (changes propagate automatically)"
echo ""
echo "To use in Codex:"
echo ""
echo "  codex --enable skills"
echo ""
echo "  Then invoke with \$skill-name or just describe the task."
echo "  Codex reads AGENTS.md for project rules."
echo ""
echo "Skill mapping (Claude Code → Codex):"
echo "  /oracle      → \$oracle-integration or 'run oracle'"
echo "  /prd, /ux    → \$artifact-workflow or 'create PRD'"
echo "  /ralph       → ./scripts/ralph.sh (scripts work directly)"
echo ""
echo "════════════════════════════════════════════════════════════════"
