# Session Tasks

Current session: [YYYY-MM-DD]
Goal: [One sentence describing what you're trying to accomplish]

## Plan

- [ ] Step 1: [Specific action]
- [ ] Step 2: [Specific action]
- [ ] Step 3: [Specific action]

## Verification

- [ ] How to verify step 1 works
- [ ] How to verify step 2 works
- [ ] How to verify step 3 works

## Progress

<!-- Mark items complete as you go, add notes -->

## Results

<!-- High-level summary of what was accomplished -->

## Lessons

<!-- Any corrections or learnings to add to lessons.md -->

---

## Example (delete when using)

```markdown
Current session: 2026-02-01
Goal: Add user authentication to the API

## Plan

- [ ] Step 1: Add JWT middleware to Express app
- [ ] Step 2: Create /login and /logout endpoints
- [ ] Step 3: Protect existing routes with auth middleware

## Verification

- [ ] curl /protected returns 401 without token
- [ ] curl /login with valid creds returns JWT
- [ ] curl /protected with valid JWT returns 200
```
