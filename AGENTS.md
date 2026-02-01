# Agents — Oracle Swarm Extension

**Rules**: See `CLAUDE.md`

---

## Ralph Agent Roles

**Implementer**
- Implements ONE task
- Runs verification before claiming completion
- Does NOT commit (Ralph handles that)

**Reviewer**
- Fresh context
- Output `NO_ISSUES_FOUND` or `[P1|P2|P3]` issues with file:line

**LLM Judge**
- Binary: `LLM_PASS` or `LLM_FAIL` with 1-line reason

**Council** (optional)
- Analyst: correctness, architecture, perf
- Sentinel: anti-patterns, security
- Designer: UI/UX, accessibility
- Healer: fixes issues, re-runs verification
