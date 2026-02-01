# Project Structure

```
appbuilder-skill/
├── .claude/
│   ├── commands/           # Slash commands (/guide, /prd, etc.)
│   ├── context/            # Context files for session priming
│   └── tasks/              # Task-specific onboarding notes
│
├── .beads/
│   ├── beads.db            # SQLite task database
│   ├── logs/               # Per-task execution logs
│   └── audit/              # Action audit trail
│
├── artifacts/              # Generated documents
│   ├── 00-brief.md         # Problem definition
│   ├── 01-prd.md           # Product requirements
│   ├── 02-ux.md            # UX specification
│   ├── 03-plan.md          # Implementation plan
│   ├── 04-task-graph.json  # Compiled tasks
│   ├── 05-design/          # Design variants
│   ├── 06-oracle/          # Review feedback by phase
│   └── 07-verification.md  # Gate results
│
├── scripts/
│   ├── ralph.sh            # Autonomous execution (main script)
│   ├── oracle_converge.sh  # Review convergence loop
│   ├── gate_pack.sh        # Verification gates
│   ├── compile_task_graph.js
│   └── generate_beads_setup.js
│
├── prompts/
│   ├── ralph/              # Task agent prompts
│   │   ├── task_prompt.md
│   │   └── council/        # Council of Subagents
│   ├── review/             # Review prompts
│   ├── sprint/             # Sprint decomposition
│   └── prd/, ux/, plan/, code/  # Phase-specific
│
├── skills/                 # Skill documentation
├── templates/              # Document templates
├── reference-specs/        # Exemplary planning documents
├── docs/                   # Additional documentation
├── tools/                  # Web-based tools (task board, etc.)
├── tasks/                  # Session-level tracking
│   ├── todo.md             # Current session plan
│   └── lessons.md          # Learnings from mistakes
│
├── CLAUDE.md               # Agent instructions
├── AGENTS.md               # Multi-agent coordination
└── .appbuilder.yaml        # Unified configuration
```
