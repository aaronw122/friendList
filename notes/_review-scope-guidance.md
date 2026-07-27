# Review Scope Guidance (shared)

You are reviewing a PLANNING DOCUMENT, not code. Plan reviews catch structural/architectural
issues. They are NOT for implementation-level details discovered while writing/testing code.

## Worth catching in plan review (fix now)
- Missing components, phases, or endpoints that other parts of the plan depend on
- Type/contract mismatches between frontend and backend definitions
- Incorrect API flags/params that would silently produce wrong behavior
- Architectural gaps (endpoint referenced but never defined)
- Inconsistencies between sections (field defined in one place, missing in another)

## Better discovered during implementation (log as Impl-note, do NOT fix)
- Exact algorithm params / tuning values / thresholds
- Threading edge cases, lock contention, queue overflow behavior
- Runtime perf details (memory, exact timeouts)
- Math precision requiring benchmarks/output inspection
- Production hardening (disk checks, graceful shutdown, retry backoff curves)
- Defensive coding patterns that emerge naturally when writing tests

## The test
"Would discovering this during implementation cause significant rework or wrong architecture?"
If YES -> fix in plan. If NO -> Impl-note.

## Severity classification (TWO STEPS, mandatory per issue)
1. Apply the scope test above. If NO -> classify as **Impl-note** regardless of how severe it
   sounds. Missing function params, unwired arguments, dead code paths, incorrect thresholds =
   ALWAYS Impl-notes (caught immediately when writing/running code).
2. Only if it passes the scope test (a real plan-level problem causing rework), assign severity:
   - **Critical** — bugs/crashes/data loss/security at the architectural level
   - **Must-fix** — significant structural/design/contract-consistency problems
   - **Medium** — should fix before implementation but won't block
   - **Low** — nice to have, deferrable
   - **Impl-note** — real but implementation-level; will NOT trigger plan fixes or new rounds

## Output
Group findings by severity. For each: one-line description + exact plan section/heading it refers
to + a concrete suggested fix. Be precise; no filler.
