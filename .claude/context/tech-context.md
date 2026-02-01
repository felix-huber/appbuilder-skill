# Technical Context

## Tech Stack

| Layer | Technology |
|-------|------------|
| Runtime | Node.js 18+ |
| Scripts | Bash, JavaScript |
| Task Tracking | Beads (Rust) or task-graph.json |
| AI Tools | Claude Code CLI, Codex CLI, Oracle (GPT-5.2 Pro) |
| Version Control | Git + GitHub CLI |

## Key Dependencies

```json
{
  "required": {
    "node": ">=18.0.0",
    "jq": "JSON processing",
    "gh": "GitHub CLI for auto-PR"
  },
  "optional": {
    "beads_rust": "cargo install --git https://github.com/Dicklesworthstone/beads_rust.git"
  }
}
```

## File Patterns

| Pattern | Purpose |
|---------|---------|
| `artifacts/*.md` | Generated documents (artifact chain) |
| `artifacts/*.json` | Compiled data (task graph) |
| `.beads/` | Task database and logs |
| `.claude/commands/*.md` | Slash command definitions |
| `scripts/*.sh` | Automation scripts |
| `prompts/**/*.md` | Prompt templates |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_CMD` | `claude -p --dangerously-skip-permissions` | Claude invocation |
| `CODEX_CMD` | `codex exec --yolo` | Codex invocation |
| `AUTO_PR` | `true` | Create PRs automatically |
| `FRESH_EYES` | `false` | Post-task review |
