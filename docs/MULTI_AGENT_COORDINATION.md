# Multi-Agent Coordination with MCP Agent Mail

## When Do You Need Multi-Agent Coordination?

| Scenario | Ralph (single agent) | MCP Agent Mail (multi-agent) |
|----------|---------------------|------------------------------|
| Sequential task execution | ✅ Works | Overkill |
| One Claude Code instance | ✅ Works | Not needed |
| 2+ parallel agents | ⚠️ May conflict | ✅ Required |
| Frontend + Backend agents | ⚠️ May conflict | ✅ Recommended |
| 7 Codex instances (Doodlestein style) | ❌ Will conflict | ✅ Essential |

## What is MCP Agent Mail?

**MCP Agent Mail** (by Doodlestein/Jeffrey Emanuel) is a coordination layer for coding agents:
- **Gmail for agents** — Inbox/outbox, threads, search
- **Identities** — Each agent gets a memorable name (e.g., "SwiftFalcon", "BoldPanda")
- **File reservations** — Agents claim files to avoid conflicts
- **Message history** — Searchable, auditable in Git + SQLite

GitHub: https://github.com/Dicklesworthstone/mcp_agent_mail

## Installation

```bash
# Clone the repo
git clone https://github.com/Dicklesworthstone/mcp_agent_mail.git
cd mcp_agent_mail

# Install dependencies
pip install -r requirements.txt

# Start the server
python -m mcp_agent_mail
```

Server runs on `http://localhost:8765` by default.

## Setting Up Agents

### 1. Register Agent Identity

Each agent registers with a unique identity:

```bash
# In Claude Code
mcp-agent-mail register --name "FrontendFalcon" --role "frontend"

# In Codex instance 1
mcp-agent-mail register --name "BackendBear" --role "backend"

# In Codex instance 2  
mcp-agent-mail register --name "CoreCobra" --role "core"
```

### 2. Add to CLAUDE.md / AGENTS.md

```markdown
## Multi-Agent Coordination

This project uses MCP Agent Mail for coordination.

### Your Identity
You are **FrontendFalcon**, responsible for UI components.

### Before Starting Work
1. Check inbox: `mcp-agent-mail inbox FrontendFalcon`
2. Acknowledge plan: Send message confirming you've read AGENTS.md
3. Claim files: Reserve files you'll modify

### Coordination Rules
- Check inbox at start of each task
- Reserve files before modifying: `mcp-agent-mail reserve src/ui/**`
- Send status updates after completing tasks
- Reply to questions from other agents
- Release files when done: `mcp-agent-mail release src/ui/**`

### Message Format
Subject: [TASK-ID] Brief description
Body: What you did, what's next, any blockers
```

## Doodlestein's 5-Prompt Workflow

Jeffrey runs 7 Codex instances with just 5 rotating prompts:

### Prompt 1: Start Task
```
Check your inbox and acknowledge any messages. Then look at the beads backlog 
with `br ready` and pick a task appropriate for your role. Reserve the relevant 
files, implement the task, and send a status update when done.
```

### Prompt 2: Coordinate
```
Please first discuss and coordinate with the other agents. When you have a good 
plan, divvy up the work and check and test things carefully!
```

### Prompt 3: Fresh Eyes Review
```
Great, now I want you to carefully read over all of the new code you just wrote 
and other existing code you just modified with "fresh eyes" looking super 
carefully for any obvious bugs, errors, problems, issues, confusion, etc.
Carefully fix anything you uncover.
```

### Prompt 4: Check Messages
```
Check your inbox for any messages from other agents. Respond to questions, 
acknowledge completed work, and update your task status.
```

### Prompt 5: Status Report
```
Send a status update to the team about what you've completed, what you're 
working on, and any blockers or questions.
```

## Integration with Oracle Swarm

### Modified Ralph for Multi-Agent

Add `--multi-agent` flag to Ralph:

```bash
# Single agent (default)
./scripts/ralph.sh --fresh-eyes 100

# Multi-agent with MCP Agent Mail
./scripts/ralph.sh --multi-agent --agent-name "FrontendFalcon" --fresh-eyes 50
```

### Multi-Agent Prompt Template

When `--multi-agent` is set, add to task prompt:

```
## Multi-Agent Coordination

You are **{agent_name}**. 

Before starting:
1. Check inbox: `mcp-agent-mail inbox {agent_name} --limit 10`
2. Reserve files: `mcp-agent-mail reserve {allowed_paths}`

After completing:
1. Release files: `mcp-agent-mail release {allowed_paths}`
2. Send status: `mcp-agent-mail send --to team --subject "[{task_id}] Complete" --body "Implemented {subject}"`

If blocked:
- Send message to relevant agent asking for help
- Move to next task while waiting
```

## File Reservation (Conflict Prevention)

```bash
# Reserve files (advisory lock)
mcp-agent-mail reserve src/components/Button.tsx --agent FrontendFalcon

# Check who has what reserved
mcp-agent-mail reservations

# Release when done
mcp-agent-mail release src/components/Button.tsx --agent FrontendFalcon
```

Reservations are **advisory** — agents can override, but it signals intent.

## Message Examples

### Task Completion
```
From: BackendBear
To: team
Subject: [S2-T3] API endpoints complete

Implemented:
- POST /api/databases
- GET /api/databases/:id/tables
- POST /api/query

Tests passing. Frontend can now integrate.

Files released: src/api/**
```

### Question
```
From: FrontendFalcon
To: BackendBear
Subject: [S2-T5] Query response format?

What's the response format for POST /api/query?

Need to know:
- Success response shape
- Error response shape
- Pagination support?
```

### Coordination
```
From: CoreCobra
To: team
Subject: [COORDINATION] Database schema change

I'm about to modify the core schema in src/types/database.ts.

This will affect:
- BackendBear: API response types
- FrontendFalcon: State management types

Please acknowledge before I proceed.
```

## When to Use vs When Not

### Use MCP Agent Mail When:
- Running 2+ agent instances in parallel
- Different agents own different parts of codebase
- Complex dependencies between agents' work
- Need audit trail of agent decisions
- Want agents to self-coordinate

### Don't Use When:
- Single agent (Ralph default mode)
- Sequential task execution
- Simple project with no conflicts
- First time using Oracle Swarm (add complexity later)

## Alternative: Simple File Locking

If MCP Agent Mail is too complex, use simple file-based locks:

```bash
# In task prompt
## Coordination
Before modifying files:
1. Check for .lock files: `ls -la src/components/*.lock`
2. Create lock: `touch src/components/Button.tsx.lock`
3. Do your work
4. Remove lock: `rm src/components/Button.tsx.lock`

If lock exists, skip this task and move to next.
```

This is simpler but less powerful than MCP Agent Mail.

## Summary

| Feature | Single Agent (Ralph) | Multi-Agent (MCP Agent Mail) |
|---------|---------------------|------------------------------|
| Task selection | Ralph picks from `br ready` | Each agent picks from `br ready` |
| Conflict prevention | N/A (sequential) | File reservations |
| Communication | N/A | Inbox/outbox |
| Coordination | N/A | Messages + threads |
| Audit trail | progress.txt | Git + SQLite |
| Setup complexity | None | Moderate |

**Recommendation:** Start with single-agent Ralph. Add MCP Agent Mail when you need parallel agents.
