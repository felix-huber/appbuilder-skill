# /ship — Create Release Plan

## Goal
Generate `artifacts/08-release.md` with rollout steps, monitoring, and rollback plan.

## Prerequisites
- `artifacts/07-verification.md` exists (gates passed)
- Recommended: `/oracle code` completed for final review
- Recommended: Devin Review passed (see below)

## Pre-Ship: Devin Code Review

Before creating the release plan, run Devin's free AI code review:

```bash
# If you have a PR open
./scripts/devin_review.sh <pr_number>

# Or with full URL
./scripts/devin_review.sh https://github.com/owner/repo/pull/123
```

Devin Review provides:
- **Bug detection** (severe/non-severe) with confidence levels
- **Logical code grouping** (not alphabetical)
- **Copy/move detection** (avoids false "full delete + insert" diffs)
- **Context-aware Q&A** about the codebase

Fix any severe bugs before proceeding.

## Inputs
- `artifacts/07-verification.md`
- `artifacts/03-plan.md` (rollout section)
- `artifacts/01-prd.md` (feature description)

## Output
- `artifacts/08-release.md`

## Steps

### 1. Validate prerequisites
```bash
if [ ! -f artifacts/07-verification.md ]; then
  echo "Run /gates first to verify the build."
  exit 1
fi
```

### 2. Check verification status
Read `artifacts/07-verification.md` and confirm:
- Overall status is READY or READY WITH WARNINGS
- No blockers listed

If blockers exist:
> Cannot create release plan. Fix blockers listed in verification report first.

### 3. Generate release plan

Create `artifacts/08-release.md`:

````markdown
# 08 — Release Plan

## Release Summary

**Version**: v1.0.0
**Date**: [planned date]
**Type**: [Major/Minor/Patch]

### What's Shipping
- Feature 1: [description]
- Feature 2: [description]
- Bug fix: [description]

### Not Shipping (Deferred)
- [feature pushed to next release]

## Pre-Release Checklist

- [ ] All gates pass (`artifacts/07-verification.md`)
- [ ] Code reviewed and approved
- [ ] Documentation updated
- [ ] Changelog updated
- [ ] Version bumped in package.json
- [ ] Git tag created
- [ ] Stakeholders notified

## Rollout Steps

### Phase 1: Staging (Day 0)
1. Deploy to staging environment
2. Run smoke tests
3. Internal team verification
4. **Go/No-Go Decision Point**

### Phase 2: Canary (Day 1-2)
1. Enable feature flag for 5% of users
2. Monitor error rates and metrics
3. Check support channels
4. **Go/No-Go Decision Point**

### Phase 3: Gradual Rollout (Day 3-5)
1. Increase to 25% of users
2. Monitor for 24 hours
3. Increase to 50% of users
4. Monitor for 24 hours
5. **Go/No-Go Decision Point**

### Phase 4: Full Release (Day 6+)
1. Enable for 100% of users
2. Remove feature flag (or keep for kill switch)
3. Mark release complete

## Feature Flags

| Flag | Purpose | Default | Kill Switch? |
|------|---------|---------|--------------|
| `FF_NEW_FEATURE` | Enable new feature | false | Yes |

### Flag Activation Commands
```bash
# Enable for percentage
feature-flags set FF_NEW_FEATURE --percentage 5

# Enable for all
feature-flags set FF_NEW_FEATURE --enabled true

# Disable (kill switch)
feature-flags set FF_NEW_FEATURE --enabled false
```

## Monitoring

### Key Metrics
| Metric | Baseline | Threshold | Alert |
|--------|----------|-----------|-------|
| Error rate | 0.1% | > 0.5% | PagerDuty |
| P95 latency | 150ms | > 300ms | Slack |
| API success rate | 99.5% | < 99% | PagerDuty |

### Dashboards
- [Production Dashboard](link)
- [Error Tracking](link)
- [User Analytics](link)

### Alerts
- Error rate spike: #oncall-channel
- Latency degradation: #oncall-channel
- Feature flag change: #releases-channel

## Rollback Plan

### Triggers for Rollback
- Error rate > 1% for 5 minutes
- P95 latency > 500ms for 10 minutes
- Critical bug reported by 3+ users
- Data integrity issue detected

### Rollback Steps

#### Quick Rollback (Feature Flag)
```bash
# Disable feature immediately
feature-flags set FF_NEW_FEATURE --enabled false
```
Time to effect: < 1 minute

#### Full Rollback (Deployment)
```bash
# Revert to previous version
deploy rollback --to previous

# Or specific version
deploy rollback --to v0.9.5
```
Time to effect: 5-10 minutes

### Post-Rollback
1. Notify stakeholders
2. Create incident report
3. Analyze root cause
4. Plan fix timeline

## Customer Communications

### Internal Announcement
- When: Day of release
- Channel: #announcements
- Content: Feature summary + known issues

### External Announcement (if applicable)
- When: After 100% rollout stable
- Channel: Blog / Email / In-app
- Content: Feature benefits + how to use

### Support Preparation
- FAQ document: [link]
- Known issues: [link]
- Escalation path: [contact]

## Post-Release Verification

### Day 1 Checks
- [ ] Error rates normal
- [ ] No critical bugs reported
- [ ] Metrics within thresholds

### Week 1 Checks
- [ ] User adoption metrics
- [ ] Performance stable
- [ ] Support ticket volume normal

## Sign-off

| Role | Name | Approved | Date |
|------|------|----------|------|
| Engineering | | [ ] | |
| Product | | [ ] | |
| QA | | [ ] | |
````

### 4. Optional: Oracle ops review
For complex releases, run Oracle with ops lens:

```bash
./scripts/oracle_single_lens.sh plan ops artifacts/08-release.md artifacts/03-plan.md
```

Apply any issues to the release plan.

### 5. Save
Write to `artifacts/08-release.md`.

## Next step

After the release plan is created and the actual shipping is done, **auto-run /retro** to capture learnings:

```bash
# After shipping is confirmed complete, execute /retro logic
```

**Note:** Only run /retro after the actual deployment/release is done, not immediately after creating the release plan.
