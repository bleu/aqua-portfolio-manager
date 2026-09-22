# Documentation style

Apply the [ASD-STE100 skill](https://github.com/danyuchn/asd-ste100-skill) as a clarity guide.
Its dictionary coverage is advisory, so do not claim certified STE compliance.

- State current behavior directly. Keep decision history in ADRs.
- Give each subject one primary document. Link to it instead of repeating the explanation.
- Use one instruction per sentence and one topic per paragraph.
- Limit instructions to 20 words and descriptions to 25 words per sentence where precision permits.
- Use active voice and consistent terms. Preserve identifiers, units, conditions, and requirement strength.
- Keep a scenario when it changes an action, result, or security boundary.

## Code comments

Keep comments for API contracts, units, invariants, rounding, and reasons the code cannot express.
Remove comments that repeat a name, statement, assertion, or surrounding explanation.
Put regression context beside the regression test.
Keep test directives, license notices, numerical bounds, and limitations of test oracles.

## Review

Check links and commands. Compare rewrites for lost conditions or stronger claims.
Treat automated style findings as review aids, not proof of factual equivalence.
