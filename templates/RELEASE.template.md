# 08 — Release Plan

## Release Summary
- **Version**: v1.0.0
- **Date**: [planned date]
- **Type**: Major/Minor/Patch

### What's Shipping
- Feature 1: …
- Feature 2: …

### Not Shipping (Deferred)
- …

## Pre-Release Checklist
- [ ] All gates pass
- [ ] Code reviewed
- [ ] Docs updated
- [ ] Changelog updated
- [ ] Version bumped

## Rollout Steps

### Phase 1: Staging
1. Deploy to staging
2. Run smoke tests
3. Internal verification
4. **Go/No-Go**

### Phase 2: Canary (5%)
1. Enable for 5% of users
2. Monitor 24 hours
3. **Go/No-Go**

### Phase 3: Full Release
1. Enable for 100%
2. Monitor 48 hours
3. Mark complete

## Monitoring
- Error rate: < 0.5%
- P95 latency: < 300ms

## Rollback Plan
1. Disable feature flag
2. If critical: `deploy rollback --to previous`
