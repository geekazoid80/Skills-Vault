---
name: tdd
description: Use when implementing any new feature, fixing any bug, or making any behaviour change in production code, BEFORE writing the implementation. Triggers include "implement X", "fix the Y bug", "add a Z method", "refactor A to do B", "build feature C", "red-green-refactor", "test-first", "write tests for", "TDD this", "integration test for", "make this testable". NOT for throwaway prototypes, generated code, or pure config edits (ask the user). Defers to the project's own test stack and conventions (Vitest/pytest/Go testing/etc., ephemeral-DB scaffolds documented in the project's AGENTS.md). Cross-references completion-gate (TDD fires BEFORE writing; completion-gate fires AT or AFTER claiming done) and subagent-delegation (when delegating implementation to a sub-agent, brief them with the TDD discipline upfront). Localised version that folds obra/superpowers/test-driven-development (philosophy plus rationalisation prevention) and mattpocock/skills/engineering/tdd (tactical workflow plus anti-pattern guidance).
metadata:
  version: 1.1.0
---

# Test-Driven Development

> **Skill marker**: When applying this skill, begin your reply with `[skill: tdd]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

Write the test first. Watch it fail. Write minimal code to pass. Refactor. Move to the next test.

**Core principle:** if you did not watch the test fail, you do not know if it tests the right thing.

**Violating the letter of these rules is violating the spirit of these rules.**

This skill is the lifecycle hook BEFORE writing implementation code. Its sibling `completion-gate` is the hook AT or AFTER claiming done. Use both in sequence on every chunk that touches production code.

## When to Use

**Always:**
- New features
- Bug fixes (write a failing test that reproduces the bug, THEN fix)
- Refactoring with behaviour change (refactoring without behaviour change is fine without TDD if covered by existing tests)
- Any code that will run in production

**Exceptions (ASK the user):**
- Throwaway prototypes (mark them clearly; do not let them ship)
- Generated code (the generator should be TDD-developed; the output need not be)
- Configuration files
- One-off ad-hoc scripts that will not be re-run

Thinking "skip TDD just this once because of X"? Stop. That is rationalisation. See the table below.

## Agree the seams before writing any test

A seam is the public boundary you test at: the interface where behaviour is observable without reaching inside. Tests live at seams, never against internals. (`greedy-with-constraints` carries the full vocabulary; this is the testing-side rule.)

**Before writing any test, write down the seams under test and confirm them with the user.** No test is written at an unconfirmed seam.

The reason is triage, not ceremony. You cannot test everything, so agreeing the seams up front puts the testing effort on critical paths and complex logic instead of spreading it evenly across every edge case. The question to ask: "What is the public interface here, and which seams should we test?"

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Wrote the code before the test? **Delete it.** Start over.

No exceptions:

- Don't keep the deleted code as "reference".
- Don't "adapt" it while writing tests (that is just tests-after with extra steps).
- Don't peek at it while writing the test.
- Delete means delete.

Implement fresh from the test.

## The Red-Green-Refactor Cycle

```
RED            : write one failing test
verify RED     : run it, confirm it fails for the expected reason
GREEN          : write minimal code to pass
verify GREEN   : run it, confirm it passes (and other tests still pass)
REFACTOR       : clean up while staying GREEN
next           : back to RED with the next behaviour
```

### RED: write one failing test

One test. One behaviour. Clear name describing what the system should do (not how).

Good:
```typescript
test('retries failed operations 3 times before throwing', async () => {
  let attempts = 0;
  const operation = () => {
    attempts++;
    if (attempts < 3) throw new Error('transient');
    return 'success';
  };

  const result = await retryOperation(operation);

  expect(result).toBe('success');
  expect(attempts).toBe(3);
});
```
Tests real behaviour through the public interface. Name reads like a specification.

Bad:
```typescript
test('retry works', async () => {
  const mock = jest.fn()
    .mockRejectedValueOnce(new Error())
    .mockRejectedValueOnce(new Error())
    .mockResolvedValueOnce('success');
  await retryOperation(mock);
  expect(mock).toHaveBeenCalledTimes(3);
});
```
Vague name. Tests the mock's call count, not the system's behaviour.

Requirements per RED test:

- One behaviour, not "and".
- Real code paths, mocks only when unavoidable (network, time, randomness).
- Name reads as a specification: "system X does Y when Z".

### Verify RED: watch it fail

**MANDATORY. Never skip.** Run the test. Confirm three things:

- It fails (not errors).
- The failure message matches what you expected (not a typo, not a missing import).
- It fails because the feature is missing, not because of plumbing.

Test passes? You are testing existing behaviour. Re-write the test.

Test errors out? Fix the error first, then re-run until it fails for the right reason.

### GREEN: write the minimal code to pass

Simplest code that satisfies the test. No speculative parameters. No "I might need X later". No refactoring of unrelated code.

Good:
```typescript
async function retryOperation<T>(fn: () => Promise<T>): Promise<T> {
  for (let i = 0; i < 3; i++) {
    try {
      return await fn();
    } catch (e) {
      if (i === 2) throw e;
    }
  }
  throw new Error('unreachable');
}
```

Bad:
```typescript
async function retryOperation<T>(
  fn: () => Promise<T>,
  options?: {
    maxRetries?: number;
    backoff?: 'linear' | 'exponential';
    onRetry?: (attempt: number) => void;
    timeoutMs?: number;
  }
): Promise<T> {
  // YAGNI; the test asks for none of this
}
```
Over-engineered. The test did not ask for any of those options.

### Verify GREEN: watch it pass

**MANDATORY.** Run the test. Confirm:

- The new test passes.
- All other tests still pass (no regressions introduced).
- Output is pristine: no warnings, no swallowed errors, no console-log leakage.

If the new test fails: fix the code, not the test.

If other tests fail: fix the regressions before moving on.

### REFACTOR: clean up while staying GREEN

After GREEN only. Never refactor while RED.

Refactor candidates to look for:

- **Duplication.** Extract a function or class.
- **Long methods.** Break into private helpers; keep the tests on the public interface.
- **Shallow modules** (large interface, thin implementation). Combine or deepen. See `greedy-with-constraints` for the deep-modules principle.
- **Feature envy.** Move logic to where the data lives.
- **Primitive obsession.** Introduce value objects.
- **Existing code** that the new code reveals as problematic.
- **Project conventions** you noticed during the GREEN write that you should now apply.

After each refactor step, re-run the affected tests. Stay green.

### Next

Back to RED with the next behaviour. One behaviour at a time.

## Anti-Pattern: Horizontal Slicing

**DO NOT write all tests first, then all implementation.** That is "horizontal slicing" and it produces bad tests.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED -> GREEN: test1 -> impl1
  RED -> GREEN: test2 -> impl2
  RED -> GREEN: test3 -> impl3
  ...
```

Why horizontal slicing is bad:

- Tests written in bulk test *imagined* behaviour, not *actual* behaviour.
- You commit to the test structure before understanding the implementation, then either contort the implementation or rewrite the tests.
- Tests become insensitive to real changes (they test the shape of things, not the system's behaviour).
- You outrun your headlights.

**Vertical slices via tracer bullets:** one test, one implementation, then the next. Each cycle teaches you something that informs the next test.

## Anti-Pattern: Tautological Tests

A test whose assertion recomputes the expected value the same way the code does passes by construction. It can never disagree with the implementation, so it verifies nothing while looking like coverage.

```
WRONG (recomputes the expectation):
  const expected = items.reduce((sum, i) => sum + i.price, 0);
  expect(calculateTotal(items)).toBe(expected);

RIGHT (independent expectation):
  expect(calculateTotal([{price: 10}, {price: 5}])).toBe(15);
```

The same failure wears other costumes: a snapshot generated from the code under test and then asserted against, or a constant asserted equal to itself.

**Rule:** the expected value comes from an independent source of truth. A known-good literal, a worked example, or the spec. Never from re-running the implementation's own logic inside the test.

## Good Tests vs Bad Tests

| Quality | Good | Bad |
|---|---|---|
| Minimal | One behaviour. If "and" appears in the name, split it. | "validates email AND domain AND whitespace" |
| Clear name | Name describes the behaviour as a specification | `test('test1')`, `test('it works')` |
| Public interface | Exercises the system the way a real consumer would | Tests private methods, asserts on internal state |
| Real code paths | Uses real implementations where possible | Mocks every collaborator, tests the mock's behaviour |
| Survives refactor | Behaviour unchanged means the test still passes | Renaming an internal function breaks the test |
| Shows intent | Reads as documentation of what the system does | Obscures intent behind setup ceremony |

If a test breaks during a refactor that did not change behaviour, the test was testing implementation, not behaviour. Rewrite the test.

### Worked examples

Integration-style test (good): exercises through the public interface, behaviour-focused name, no mocks of internal collaborators:

```typescript
test('user can checkout with valid cart', async () => {
  const cart = createCart();
  cart.add(product);
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe('confirmed');
});
```

Implementation-detail test (bad): mocks an internal collaborator, asserts on its call shape, breaks on harmless refactors:

```typescript
test('checkout calls paymentService.process', async () => {
  const mockPayment = jest.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

External-bypass test (bad): verifies through a side channel rather than the system's interface; couples the test to storage internals:

```typescript
// BAD: bypasses the interface to verify
test('createUser saves to database', async () => {
  await createUser({ name: 'Alice' });
  const row = await db.query('SELECT * FROM users WHERE name = ?', ['Alice']);
  expect(row).toBeDefined();
});

// GOOD: verifies through the interface
test('createUser makes the user retrievable', async () => {
  const user = await createUser({ name: 'Alice' });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe('Alice');
});
```

## When to Mock and Where

Mock at **system boundaries** only:

- External APIs (payment gateways, email providers, vendor SDKs).
- Databases, sometimes; prefer a real test database with the project's ephemeral-DB scaffold (see project AGENTS.md).
- Time and randomness.
- The file system, sometimes.

Do NOT mock:

- Your own classes and modules.
- Internal collaborators within the same module.
- Anything you control and can exercise directly.

### Designing for mockability

Even at boundaries, design interfaces that are easy to mock cleanly.

**Use dependency injection.** Pass external dependencies in rather than creating them internally:

```typescript
// Easy to mock
function processPayment(order, paymentClient) {
  return paymentClient.charge(order.total);
}

// Hard to mock
function processPayment(order) {
  const client = new StripeClient(process.env.STRIPE_KEY);
  return client.charge(order.total);
}
```

**Prefer SDK-style interfaces over generic fetchers.** Specific functions for each external operation, not one generic dispatcher with conditional logic:

```typescript
// GOOD: each function is independently mockable
const api = {
  getUser:     (id)     => fetch(`/users/${id}`),
  getOrders:   (userId) => fetch(`/users/${userId}/orders`),
  createOrder: (data)   => fetch('/orders', { method: 'POST', body: data }),
};

// BAD: mocking requires conditional logic inside the mock
const api = {
  fetch: (endpoint, options) => fetch(endpoint, options),
};
```

The SDK approach gives one specific shape per mock, no conditional logic in test setup, and clear visibility into which endpoints a test exercises.

For the full set of mocking pitfalls and gate functions (testing mock behaviour, test-only production methods, mocking without understanding, incomplete mocks), see the `testing-anti-patterns` skill.

## Why Order Matters

| Excuse | Reality |
|---|---|
| "I will write tests after to verify it works" | Tests-after pass immediately. Passing immediately proves nothing. |
| "I already manually tested the edge cases" | Manual testing is ad-hoc; no record, cannot re-run, easy to forget under pressure. |
| "Deleting X hours of work to start over with TDD is wasteful" | Sunk cost fallacy. Working code without real tests IS the technical debt. |
| "TDD is dogmatic; pragmatic means adapting" | TDD IS pragmatic: faster than debug-after, prevents regressions, documents behaviour, enables refactor. |
| "Tests-after achieve the same goals; spirit not ritual" | No. Tests-after answer "what does this do?" Tests-first answer "what should this do?" Different question, different answer. |
| "30 minutes of tests after gives me coverage" | Coverage is not proof the test catches what it should. You never saw it fail. |

## Common Rationalisations

| Excuse | Reality |
|---|---|
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I will test after" | Tests passing immediately prove nothing. |
| "Already manually tested" | Ad-hoc is not systematic. No record, cannot re-run. |
| "Deleting hours of work is wasteful" | Sunk cost. Keeping unverified code is technical debt. |
| "Keep as reference, write tests first" | You will adapt it. That is testing-after. Delete means delete. |
| "Need to explore first" | Fine. Throw away the exploration. Start with TDD. |
| "Test is hard, design is unclear" | Listen to the test. Hard to test means hard to use. Simplify the interface. |
| "TDD will slow me down" | TDD is faster than debugging. Pragmatic equals test-first. |
| "Existing code has no tests" | You are improving it. Add tests for what you touch. |
| "This is different because..." | It is not. |

## Red Flags: STOP and Start Over

- Code written before the test.
- Test added "after, just to confirm".
- Test passes immediately on first run.
- Cannot explain why the test failed when run during RED.
- Rationalising "just this once".
- "I already manually tested it".
- "Tests-after achieve the same purpose".
- "It is about spirit, not ritual".
- "Keep as reference" or "adapt the existing code".
- "Already spent X hours; deleting is wasteful".
- "TDD is dogmatic; I am being pragmatic".
- "This is different because..."

**All of these mean the same thing: delete the production code, start over with TDD.**

## When the Test is Hard to Write

| Problem | What it usually means | What to do |
|---|---|---|
| Cannot figure out how to write the test | The interface is unclear. | Write the wished-for API in the test first. The test becomes the design. |
| Test is too complicated | The design is too complicated. | Simplify the interface. If the test gets simpler, the design got better. |
| Must mock everything | The code is too coupled. | Use dependency injection. Pull collaborators in via constructor or function parameters. |
| Test setup is huge | Coupling and over-broad scope. | Extract setup helpers. Still complex? Narrow the unit under test. |

If you cannot make the test simple, the system is telling you something. Listen.

## Worked Example: Bug Fix

**Bug:** `submitForm` accepts an empty email string.

**RED:** write the failing test:

```typescript
test('submitForm rejects empty email with a clear error', async () => {
  const result = await submitForm({ email: '' });
  expect(result.error).toBe('Email required');
});
```

**Verify RED:**

```bash
$ pnpm test
FAIL: expected 'Email required', got undefined
```

Failure message matches what we expected. Good.

**GREEN:** minimal code:

```typescript
function submitForm(data: FormData) {
  if (!data.email?.trim()) {
    return { error: 'Email required' };
  }
  // existing logic continues here
}
```

**Verify GREEN:**

```bash
$ pnpm test
PASS
```

All tests pass.

**REFACTOR:** if other fields will need similar validation, extract a `validateRequired(field, name)` helper. Run the tests after the extraction. Stay green.

## Project-stack pointers

This skill is language-agnostic. For the actual test commands, fixtures, and ephemeral-DB scaffolds in your current project, defer to the project's `AGENTS.md` (or `CLAUDE.md`):

- The project's preferred test runner and command (`pnpm test`, `pnpm test:watch`, `pytest`, `go test`, etc.).
- The project's pattern for tests that need a real DB (e.g. ephemeral-SQLite-via-Prisma scaffolds, dockerised Postgres fixtures, in-memory variants).
- The project's pattern for HTTP / controller tests (e.g. supertest, NestJS testing module, FastAPI TestClient).
- The project's mocking conventions (`vi.fn()`, `jest.fn()`, `unittest.mock.patch`, etc.) and what is allowed vs. discouraged.
- The project's coverage gates (if any) and reporting commands.

Single source of truth: do not re-document the project's test stack here; reference the project's own docs. If the project's docs are silent or stale, raise it as a gap (PR against the project's AGENTS.md) before improvising.

## Verification Checklist

Before marking a TDD chunk complete:

- [ ] Every new function or method has a test.
- [ ] You watched each test fail (RED) before writing the code (GREEN).
- [ ] Each test failed for the expected reason (feature missing, not typo or import error).
- [ ] You wrote the minimal code to pass each test.
- [ ] All tests pass.
- [ ] Output is pristine (no warnings, no swallowed errors).
- [ ] Tests use real code paths where possible; mocks only when unavoidable.
- [ ] Edge cases and error paths are covered.

If any box is unchecked: you skipped TDD on that piece. Start over for that piece.

After this checklist passes, the chunk transitions into the `completion-gate` lifecycle (Layers 1, 2, 3) for in-flight checks, code-review, and the final completion gate.

## Cross-references

- `completion-gate`: fires AT or AFTER claiming done. The TDD verification checklist above feeds into completion-gate Layer 3 (the iron law of verification).
- `testing-anti-patterns`: the review-side and mock-introduction-side counterpart. Five iron laws against testing mock behaviour, test-only production methods, mocking without understanding, incomplete mocks, and tests-as-afterthought. Fires alongside this skill on test-quality concerns.
- `subagent-delegation`: when delegating implementation to a sub-agent, the brief must include the TDD discipline (write the test first, watch it fail, then write minimal code). Sub-agents that ship code without a failing test first are violating this skill.
- `forward-compatible-schemas`: when TDD introduces a schema change, the schema change must follow the additive-only rule.
- `greedy-with-constraints`: when TDD designs a new API surface, default to the tightest reasonable interface (and the deep-modules + design-for-testability sections of that skill).

## Bottom Line

Write the test first. Watch it fail. Write minimal code to pass. Refactor. Move on.

If you skipped any of those steps, you did not do TDD; you wrote tests-after, and tests-after prove nothing. Delete the code and start over.
