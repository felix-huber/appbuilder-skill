# Project Overview

## What is AppBuilder Skill?

AppBuilder Skill is a meta-workflow framework for building applications using AI agents (Claude Code, Codex, GPT-5.2 Pro). It implements artifact-driven development with automated review loops.

## Core Philosophy

> "85% planning, 15% implementation" — Doodlestein Methodology

Planning tokens are cheaper than implementation tokens. Iterate reviews until stable.

## Key Components

| Component | Purpose |
|-----------|---------|
| **Artifact Chain** | Brief → PRD → UX → Plan → Tasks → Code |
| **Oracle Review** | GPT-5.2 Pro convergence loops (0 blockers/majors) |
| **Ralph** | Autonomous task execution with fresh contexts |
| **Beads** | Git-backed task tracking for AI agents |
| **Lint** | 20 AI-specific rules catching common mistakes |

## Iteration Requirements

| Phase | Minimum Passes |
|-------|----------------|
| Plan review | 4-5 |
| Beads review | 6-9 |
| Fresh eyes | Until stable |
| Oracle | Until converged |

## Non-Negotiables

1. Browser Oracle only (never API mode)
2. Artifacts are truth (update before code)
3. No evidence = not done (show commands + outputs)
4. Iterate until convergence (don't skip reviews)
