---
name: testing-anti-patterns
description: "Use when writing or reviewing tests, adding mocks, refactoring test code, deciding whether a test is worth writing, or about to add a test-only method to a production class. Triggers include \"review this test\", \"mock this\", \"why is my test flaky\", \"test pitfalls\", \"mocking strategy\", \"should I mock\", \"this test feels wrong\", \"integration vs unit\", \"test setup is huge\", \"test breaks when I refactor\", \"is this test worth writing\", \"change detector\", \"the test passes but the bug shipped\", \"does this test actually catch anything\", \"how do I test a script\", \"how do I test a prompt or a skill\", \"mutation testing\". Covers five iron laws against: testing mock behaviour, test-only methods in production, mocking without understanding dependencies, incomplete mocks, and tests-as-afterthought; plus the design-time gate (name the break a test catches, no change detectors, behaviour not source text, your code not the framework) and the mutation check. Cross-references tdd (TDD prevents these anti-patterns; if you find yourself testing mock behaviour, you violated TDD; tdd also owns the tautological-test rule). Localised version of obra/superpowers/test-driven-development/writing-good-tests.md (upstream renamed the source from testing-anti-patterns.md in v6.2.0)."
metadata:
  version: 1.1.0
---

# Testing Anti-Patterns

> **Skill marker**: When applying this skill, begin your reply with `[skill: testing-anti-patterns]` on its own line so the transcript shows the skill fired. If multiple skills fire on the same reply, emit each marker on its own line at the top: transparency over neatness.

## Overview

A test exists to catch a specific break. Two things have to be true of every test: it can name the break it catches, and it exercises the real thing. Most of the anti-patterns below are the second one failing; the first fails more quietly, and it is the one that produces a green suite protecting nothing.

**Core principle:** test what the code does, not what the mocks do, and never write a test you cannot make fail on purpose.

**Following strict TDD prevents these anti-patterns.** A test written first and watched failing against real code has already proven it can fail, and only earns a mock once the real dependency proves slow or external. See the `tdd` skill for the writing-side discipline; this skill is the review-side and mock-introduction-side counterpart.

## The Iron Laws

```
1. NEVER test mock behaviour
2. NEVER add test-only methods to production classes
3. NEVER mock without understanding dependencies
4. NEVER write a test that cannot name the break it catches
5. NEVER assert on source text when you can run the artefact
```

## Naming the break (the design-time gate)

Laws 4 and 5 fire earlier than the rest of this skill: before the test body exists, at design time. The anti-patterns further down are about mocks getting in the way of real behaviour. This section is about a test that never had a chance of catching anything in the first place.

Before writing the test body, answer: **what production change should make this test fail, and is that change a bug or a decision?** A test earns its place by catching a wrong branch, a missing side effect, a wrong argument, a boundary case, or a broken contract. If the only answer is "someone changed their mind", the test is not protecting behaviour.

### No change detectors

If only intentional decisions can fail a test (a constant's value, exact message wording, private structure), it fires on every redesign and sleeps through real bugs. It costs maintenance and buys nothing. Test the behaviour that depends on the decision, not the decision itself:

```typescript
// BAD: change detector; fails when someone retunes the constant
expect(MAX_RETRIES).toBe(5);

// GOOD: the behaviour the constant governs
// "a failing call is retried 5 times and the 6th attempt never happens"
```

### Behaviour, not text

Asserting that a script, skill, or config *contains* an exact line proves only that the source is the source. Run the artefact against controlled inputs and assert its outputs, side effects, or exit codes.

This one matters more here than in a typical codebase: **this vault is itself a corpus of documents that instruct agents**, which is exactly the situation where a grep-the-text test looks reasonable and verifies nothing. A document that instructs an agent is tested through the consuming agent's behaviour (see `author-skill`). Prose written for humans earns no test at all.

### Your code, not the framework

Test the contract your code makes at its boundaries: the route you register, the query you emit, the payload you produce. Upstream mechanics are their maintainers' tests to write. The classic miss is asserting that your router invokes a registered handler, which is the framework's test, not yours. When upstream behaviour genuinely surprised you, write one narrow characterisation test that names the assumption.

The same boundary applies inside your own code. Constructors, getters, constants, and trivial forwarding earn tests only when they validate, normalise, default, derive, enforce, or cause a side effect. Otherwise assert the first consumer-visible result that depends on them.

### Gate function

```
BEFORE writing the test body:
  Name the production change that would make this test fail.

  Cannot name one            -> redesign around an observable behaviour
  "The source text changed"  -> run the artefact and assert its effects
  Only intentional decisions -> change detector; test the behaviour
                                that depends on the decision

  Confirm the expected value is derived WITHOUT the code under test.
  IF it reuses the code's own logic or helpers:
    Replace it with a literal or a hand-checked fixture
```

On that last check: an expectation computed by the code under test passes no matter what that code does. The `tdd` skill covers this as the Tautological Tests anti-pattern with a worked example; it is not repeated here.

## Anti-Pattern 1: Testing Mock Behaviour

The violation:

```typescript
// BAD: testing that the mock exists
test('renders sidebar', () => {
  render(<Page />);
  expect(screen.getByTestId('sidebar-mock')).toBeInTheDocument();
});
```

Why this is wrong:

- You are verifying the mock works, not that the component works.
- Test passes when the mock is present, fails when it is not.
- Tells you nothing about real behaviour.

The user's correction in code review: "Are we testing the behaviour of a mock?"

The fix:

```typescript
// GOOD: test the real component, or do not mock it
test('renders sidebar', () => {
  render(<Page />);  // do not mock sidebar
  expect(screen.getByRole('navigation')).toBeInTheDocument();
});

// OR if sidebar must be mocked for isolation:
// do not assert on the mock; test Page's behaviour with sidebar present
```

### Gate function

```
BEFORE asserting on any mock element:
  Ask: "Am I testing real component behaviour, or just mock existence?"

  IF testing mock existence:
    STOP. Delete the assertion or unmock the component.

  Test real behaviour instead.
```

## Anti-Pattern 2: Test-Only Methods in Production

The violation:

```typescript
// BAD: destroy() is only used in tests
class Session {
  async destroy() {  // looks like production API
    await this._workspaceManager?.destroyWorkspace(this.id);
    // ... cleanup
  }
}

// In tests
afterEach(() => session.destroy());
```

Why this is wrong:

- Production class polluted with test-only code.
- Dangerous if accidentally called in production.
- Violates YAGNI and separation of concerns.
- Confuses object lifecycle with entity lifecycle.

The fix:

```typescript
// GOOD: test utilities handle test cleanup
// Session has no destroy(); it is stateless in production

// In test-utils/
export async function cleanupSession(session: Session) {
  const workspace = session.getWorkspaceInfo();
  if (workspace) {
    await workspaceManager.destroyWorkspace(workspace.id);
  }
}

// In tests
afterEach(() => cleanupSession(session));
```

### Gate function

```
BEFORE adding any method to a production class:
  Ask: "Is this only used by tests?"

  IF yes:
    STOP. Do not add it.
    Put it in test utilities instead.

  Ask: "Does this class own this resource's lifecycle?"

  IF no:
    STOP. Wrong class for this method.
```

## Anti-Pattern 3: Mocking Without Understanding

The violation:

```typescript
// BAD: mock breaks test logic
test('detects duplicate server', () => {
  // Mock prevents config write that test depends on.
  vi.mock('ToolCatalog', () => ({
    discoverAndCacheTools: vi.fn().mockResolvedValue(undefined)
  }));

  await addServer(config);
  await addServer(config);  // should throw, but will not
});
```

Why this is wrong:

- The mocked method had a side effect the test depended on (writing config).
- Over-mocking to "be safe" breaks actual behaviour.
- Test passes for the wrong reason or fails mysteriously.

The fix:

```typescript
// GOOD: mock at the correct level
test('detects duplicate server', () => {
  // Mock the slow part; preserve behaviour the test needs.
  vi.mock('MCPServerManager');  // just mock slow server startup

  await addServer(config);  // config written
  await addServer(config);  // duplicate detected
});
```

### Gate function

```
BEFORE mocking any method:
  STOP. Do not mock yet.

  1. Ask: "What side effects does the real method have?"
  2. Ask: "Does this test depend on any of those side effects?"
  3. Ask: "Do I fully understand what this test needs?"

  IF the test depends on side effects:
    Mock at a lower level (the actual slow or external operation),
    OR use test doubles that preserve necessary behaviour.
    NOT the high-level method the test depends on.

  IF unsure what the test depends on:
    Run the test with the real implementation FIRST.
    Observe what actually needs to happen.
    THEN add minimal mocking at the right level.

  Red flags:
    - "I will mock this to be safe"
    - "This might be slow, better mock it"
    - Mocking without understanding the dependency chain
```

## Anti-Pattern 4: Incomplete Mocks

The violation:

```typescript
// BAD: partial mock; only fields you think you need
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' }
  // Missing: metadata that downstream code uses
};

// Later: breaks when code accesses response.metadata.requestId
```

Why this is wrong:

- **Partial mocks hide structural assumptions.** You only mocked the fields you know about.
- **Downstream code may depend on fields you did not include.** Silent failures.
- **Tests pass but integration fails.** Mock is incomplete; real API is complete.
- **False confidence.** Test proves nothing about real behaviour.

The iron rule: mock the COMPLETE data structure as it exists in reality, not just the fields your immediate test uses.

The fix:

```typescript
// GOOD: mirror real API completeness
const mockResponse = {
  status: 'success',
  data: { userId: '123', name: 'Alice' },
  metadata: { requestId: 'req-789', timestamp: 1234567890 }
  // All fields the real API returns
};
```

### Gate function

```
BEFORE creating mock responses:
  Check: "What fields does the real API response contain?"

  Actions:
    1. Examine the actual API response from docs or examples.
    2. Include ALL fields the system might consume downstream.
    3. Verify the mock matches the real response schema completely.

  Critical:
    If you are creating a mock, you must understand the ENTIRE structure.
    Partial mocks fail silently when code depends on omitted fields.

  If uncertain: include all documented fields.
```

### Completeness is not specificity

A mock can mirror the real structure completely and still verify nothing. Completeness is about the fields the double carries; specificity is about what you assert of it.

When arguments, call counts, or ordering are part of the contract, assert them. A fake that accepts anything confirms only that it was reachable. And give each branch its own fixture or spy (success, error, malformed), so that the wrong branch cannot satisfy the expectation:

```typescript
// BAD: one permissive double for every branch
const send = vi.fn().mockResolvedValue({ ok: true });
// the error path "passes" because the success double answered it

// GOOD: a double per branch, arguments asserted
const send = vi.fn()
  .mockResolvedValueOnce({ ok: true })
  .mockRejectedValueOnce(new Error('upstream 503'));
expect(send).toHaveBeenCalledTimes(2);
expect(send).toHaveBeenNthCalledWith(1, { id: 'req-1', retry: false });
```

## Anti-Pattern 5: Integration Tests as Afterthought

The violation:

```
implementation complete
no tests written
"ready for testing"
```

Why this is wrong:

- Testing is part of implementation, not optional follow-up.
- TDD would have caught this.
- Cannot claim complete without tests.

The fix:

```
TDD cycle:
1. Write failing test
2. Implement to pass
3. Refactor
4. THEN claim complete
```

See the `tdd` skill for the cycle in detail and `completion-gate` for the post-implementation verification gate.

## When Mocks Become Too Complex

Warning signs:

- Mock setup is longer than the test logic.
- Mocking everything to make the test pass.
- Mocks missing methods that real components have.
- Test breaks when the mock changes (not when behaviour changes).

The user's question in review: "Do we need to be using a mock here?"

Consider: integration tests with real components are often simpler than complex mocks.

## TDD Prevents These Anti-Patterns

Why TDD helps:

1. **Write the test first.** Forces you to think about what you are actually testing.
2. **Watch it fail.** Confirms the test exercises real behaviour, not mocks.
3. **Minimal implementation.** No test-only methods creep in.
4. **Real dependencies.** You see what the test actually needs before mocking.

If you are testing mock behaviour, you violated TDD. You added mocks without watching the test fail against real code first.

## The mutation check

Run this before you call a test file finished. Mentally mutate the production code; at least one test should fail for each realistic mutation:

- Wrong constant or argument
- Wrong branch handler
- Missing state change or side effect
- Empty or default return
- Missing validation for zero, empty, nil, unauthorised, or malformed input

A mutation that nothing catches marks that behaviour as unprotected, or marks the test that claims to cover it as tautological. Either way the suite is reporting confidence it has not earned.

This is the cheapest way to find a change detector after the fact: a change detector survives every mutation on this list, because none of them is an intentional decision.

## Quick Reference

| Anti-Pattern | Fix |
|---|---|
| Assert on mock elements | Test the real component or unmock it |
| Test-only methods in production | Move to test utilities |
| Mock without understanding | Understand dependencies first; mock minimally |
| Incomplete mocks | Mirror the real API completely |
| Permissive doubles | Assert arguments, counts, ordering; one double per branch |
| Tests as afterthought | TDD; tests first |
| Over-complex mocks | Consider integration tests |
| Cannot name the break | Redesign around an observable behaviour |
| Asserts a constant or exact wording | Change detector; test the behaviour that depends on it |
| Greps a script or document's text | Run the artefact and assert its effects |
| Tests the framework's mechanics | Test your boundary contract instead |
| Test file looks finished | Run the mutation check |

## Red Flags

Mock-side:

- Assertion checks for `*-mock` test IDs.
- Methods only called in test files.
- Mock setup is more than 50 percent of the test.
- Test fails when you remove the mock.
- Cannot explain why the mock is needed.
- Mocking "just to be safe".
- One permissive double answers several branches.

Design-side (these are the ones a green suite hides):

- Setup and assertion share the same object, guaranteeing equality.
- The test can fail only through a panic, a crash, or a missing selector.
- The test fails on every intentional change and never on accidental breakage.
- Expected values are hidden behind loops, builders, or helpers.
- The test greps source text, or asserts that a removed symbol stays removed.
- The test would still matter if only the framework remained.
- The test exists for coverage, checking no side effect or outcome.

## Cross-references

- `tdd`: writing-side TDD discipline. If you are about to add a mock, you have already moved past RED; revisit the discipline.
- `completion-gate`: the post-implementation verification gate. Anti-pattern violations surface in code review (Layer 2) before push.
- `subagent-delegation`: when delegating test-writing to a sub-agent, brief them on these iron laws upfront so the sub-agent does not introduce them.
- `author-skill`: how a document that instructs an agent gets tested, which is through the consuming agent's behaviour, never by grepping the document's own text. The behaviour-not-text rule above is the testing-side statement of the same thing.

## Bottom Line

**Every test names the break it catches, and exercises the real thing.**

Mocks are tools to isolate, not things to test. If TDD reveals you are testing mock behaviour, you have gone wrong: test real behaviour, or question why you are mocking at all.

And if you cannot say what production change would turn a test red, the test is decoration. A suite full of tests that cannot fail is worse than a smaller one that can, because it reports confidence nobody has earned.
