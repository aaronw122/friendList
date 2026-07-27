# Round 2 Verdict — Referee

Verified independently against `PLAN.md`, both R2 positions, and the R1 verdict. Re-raised
items were checked for genuinely new evidence per the round-2 standard.

## Per-issue verdicts

- C1: DOWNGRADED (Impl-note) - The prosecution's WAL semantics are misapplied to this deployment. SQLite's read-only-WAL restriction ("reader must be able to write the `-shm` wal-index") bites cross-user or read-only-filesystem readers; this daemon runs as the same user that owns `~/Library/Messages/` and its sidecars, so even under `mode=ro` the connection participates in the WAL shared-memory protocol and sees every committed transaction, including rows still in `-wal`. The row-hiding failure mode is specific to `immutable=1`, which the plan (§2 line 53) explicitly bans with the correct rationale — this is the community-standard chat.db recipe. The plan already designates exactly this question as the M1 charter ("prove the hard part," live-read acceptance test) and its #1 risk. R2's own panel split 2:1 toward impl-note. Not fully dismissed: keep a named M1 verification step ("fresh `mode=ro` poll sees a message sent seconds ago, Messages running"), with snapshot-copy (db+`-wal`+`-shm` copied together) documented as the fallback if verification ever fails. NEW item, judged on merits.
- M1: DOWNGRADED (Medium) - The two mechanisms are redundant, not conflicting: tracing the poison-row scenario against the plan as written (§5 lines 77–78 + seen-set line 102), the persisted seen-set plus API dedup make both the tail re-scan and the queue retry idempotent — no duplicate adds, no lost songs, and `WHERE ROWID > watermark` still delivers every newer message past a stuck cursor. Output stays correct, so the Must-fix bar ("ambiguous enough to cause wrong architecture") is not met: either architecture an implementer derives from the wording produces a correct playlist. What survives is real but sub-Must-fix: a permanently-poisoned row stalls the watermark forever and the re-scan tail grows without bound — a robustness/spec-hygiene defect all three reviewers correctly smelled. Adopt the prosecution's own fix as a spec edit: advance the watermark past every terminally-resolved row (added / enqueued / no-link / filtered / dedup-skipped); durable retry queue is the sole owner of failures, with bounded max-attempts → dead-letter. Medium, not impl-note, because it changes a sentence of the spec, not just tuning. NEW item, judged on merits.
- M2: DISMISSED - Re-raise of R1-M4 (already downgraded to an M1-verification note) with zero new evidence: the load-bearing premise — Messages commits the row first and `attributedBody` in a later transaction — remains asserted, never demonstrated, in both rounds. SQLite exposes rows only at commit; the documented late-landing data on link bubbles is preview `payload_data`/`message_summary_info`, which the plan does not read. "Settle-window" is a rewording, not new grounding. R1's disposition stands: M1's decode-against-real-chat.db milestone is where a true settle window would surface, and the localized fix (hold watermark on rows younger than N seconds) can be added then if evidence appears.
- M3: DISMISSED - Re-raise of R1-M5 (dismissed) with no new evidence; "missing `GET /v1/me` in the client contract" is the same argument restated as an API-surface gap. The plan's word "owned" (line 100) *is* the decision — `owner.id == me` via `GET /v1/me` is its trivial, faithful implementation. Feature is opt-in and default-off, and dedup is a skip-gate: its worst failure is an extra duplicate that the seen-set and target-playlist checks still catch. Cannot silently corrupt the default path.
- M4: DISMISSED - Re-raise of R1-M2 (dismissed), verbatim, no new evidence. §4 line 71 assigns the PKCE browser login to `spotify.py` and Setup step 2 (line 135) names the loopback redirect URI `http://127.0.0.1:PORT/callback`; the listener that catches `?code=` is what that responsibility means. One-time, attended, fails loudly at setup — structurally incapable of silent wrong output at runtime.
- M5: DISMISSED (stands at R1's Low) - Re-raise of R1-M3 (downgraded to Low), re-escalated to Must-fix with no new reasoning — a pure severity move that fails the reality test: nothing runs until `client_id`/`redirect_uri` are wired, so the gap surfaces loudly at build/setup time and can never produce silent wrong output. The Low stands: add `client_id` and `redirect_uri`/`callback_port` as one line in §1 Config.

## Holistic Assessment

Composing every downgraded/dismissed item simultaneously: the daemon opens chat.db same-user
via fresh `mode=ro` connections and sees new rows (C1 — verified at M1 by design); a poison
add stalls the watermark while the seen-set keeps the re-scan and queue idempotent, so newer
songs keep landing and no duplicates appear (M1); the settle-window scenario remains
undemonstrated and is empirically gated by the same M1 milestone (M2); the ownership filter is
off-by-default and skip-only (M3); auth wiring gaps are build-time-loud (M4, M5). The
aggregate worst case is a permanently-stuck cursor with an ever-growing (but idempotent and
locally-gated) tail re-scan — degraded hygiene, not silent data loss, missed messages, or
duplicate adds. No escalation is warranted.

**Verdict: no Critical or Must-fix survives Round 2.** The plan is implementable as written.
Two edits should be made before build, both small: (1) the M1 Medium — rewrite the watermark
rule as "advance past every terminally-resolved row; the durable retry queue solely owns
failures, bounded attempts → dead-letter"; (2) the M5 Low — add `client_id` +
`redirect_uri`/`callback_port` to §1 Config. Keep C1 and M2 as named verification checkpoints
inside milestone M1, with snapshot-copy as the documented C1 fallback. A note on process: the
defense went 6-for-6 disproving findings, which I spot-checked for false negatives — its C1
SQLite semantics and M1 idempotency trace both verify against the plan text, and its two
concessions (M1 wording, M5 config line) match exactly the residuals this verdict orders
fixed. The review has converged; further rounds would re-litigate settled ground.
