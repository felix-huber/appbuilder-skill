# Codex Configuration for Oracle Swarm

Oracle convergence loops take **60-90 minutes per run**. Codex needs special configuration to handle this.

## Quick Setup

Add to `~/.codex/config.toml`:

```toml
# Oracle Swarm optimized settings
model = "gpt-5.2-codex"
approval_policy = "auto"

# Increase timeouts for long-running processes
[model_providers.openai]
stream_idle_timeout_ms = 7200000  # 2 hours (default: 5 min)
stream_max_retries = 10           # More retries for dropped connections
request_max_retries = 6           # More retries for failed requests

# Enable skills
[features]
skills = true
```

## Key Settings Explained

### `stream_idle_timeout_ms`
Default is 300,000 (5 minutes). Oracle runs can be silent for 30+ minutes while GPT-5.2 Pro thinks. Set to 7,200,000 (2 hours) to prevent premature disconnection.

### Background Terminal Behavior
Codex runs long commands in background terminals. The process keeps running even if Codex "moves on" - you can check with `/ps`.

## Instructions for Codex (Add to AGENTS.md)

```markdown
## Long-Running Oracle Processes

Oracle CLI commands take 60-90 minutes to complete. When running Oracle:

1. **DO NOT interrupt or timeout** - Oracle is working even when silent
2. **Check progress with**: `tail -f artifacts/06-oracle/*/oracle-*.log`
3. **Check if running**: `pgrep -fl oracle`
4. **Expected silence**: GPT-5.2 Pro "thinking" can take 30+ minutes with no output

After Oracle completes, apply feedback from the latest `*_product.md` file.
```

## Running Codex with Skills

```bash
# Start with skills enabled
codex --enable skills

# Or permanently enable in config.toml
# [features]
# skills = true
```

## Skill Invocation

| Claude Code | Codex Equivalent |
|-------------|------------------|
| `/oracle ux` | `$oracle-integration` or describe the task |
| `/prd` | `$cmd-prd` |
| `/ux` | `$cmd-ux` |
| `/plan` | `$cmd-plan` |

## Alternative: Tell Codex What's Happening

Instead of relying on config, you can include context in your prompt:

```
Run ./scripts/oracle_converge.sh ux artifacts/02-ux.md artifacts/01-prd.md

IMPORTANT: This process takes 60-90 minutes. The Oracle CLI calls GPT-5.2 Pro 
via browser automation, which includes extended thinking time. Do NOT interrupt.

After completion, apply the feedback from the newest file in artifacts/06-oracle/ux/
```

## Monitoring Long Runs

While Oracle runs:
```bash
# Check process is alive
pgrep -fl oracle

# Watch logs
tail -f artifacts/06-oracle/ux/oracle-round*.log

# Check for output files
ls -la artifacts/06-oracle/ux/
```

## Troubleshooting

### Codex says "no output" but process is running
This is normal. Oracle uses GPT-5.2 Pro with extended thinking (30+ minutes of silence).

### Process seems stuck
1. Check `pgrep -fl oracle` - if running, wait
2. Check log file for "thinking..." messages
3. Browser window should show ChatGPT activity

### Codex times out
Add to your prompt: "This takes 90 minutes. Do not timeout or interrupt."
