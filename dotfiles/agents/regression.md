### Regression Testing

Before the `Red → Green → Refactor` cycle begins, **assess** automated test coverage of the existing behaviour the change will touch. The assessment is mandatory. Adding regression tests is not: it depends on what the assessment finds.

- **Coverage is adequate** when existing automated tests would fail if the behaviour the change touches broke. Go straight to TDD, and do not add a regression step to the plan.
- **Coverage is poor** when that behaviour has no tests, or only tests that would still pass if it broke (happy path only, mocked away, asserting on implementation rather than outcome). Only then add regression tests, and only for the gaps found. Do not backfill the wider functional area.

If you can't tell whether coverage is adequate, show the user the evidence and ask. Don't add tests by default.

