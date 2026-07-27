# Round 1 Challenge — Devil's Advocate

Role: skeptical senior engineer attempting to DISPROVE each Critical/Must-fix finding
against the ACTUAL plan (`PLAN.md`). Verdicts judge *reality*, not severity.

Rule applied: "doesn't crash" ≠ "works". If the issue genuinely yields wrong output, CONCEDE.

---

## Critical

### C1 — immutable=1 breaks the poll loop → **CONCEDE (real)**
Plan §2 literally specifies `file:...?mode=ro`, `immutable=1`. `immutable=1` tells SQLite
the file cannot change: it disables locking **and ignores the `-wal`/`-shm` sidecars**.
`chat.db` on modern macOS is WAL-mode and actively written by Messages, so recent messages
live in the WAL until a checkpoint. An immutable open reads only the last-checkpointed main
file → new links are invisible (persistent connection: forever; per-poll reconnect: until an
unrelated checkpoint lands). This is exactly the messages we care about being unseeable.
Not a phantom — the flag choice is stated in the plan and defeats the core purpose. Real.

### C2 — watermark advances with no failed-add recovery → **CONCEDE (real)**
Architecture shows `add → persist last_seen ROWID` as a linear per-cycle step with no
success gate. Natural reading = advance unconditionally each poll. Spotify `POST .../tracks`
fails routinely (401 token expiry, 429 rate limit, transient 5xx). A failed add + advanced
ROWID = that song is never revisited = silently missing from the playlist = wrong output
("auto-adds new ones" is the whole feature). Dedup can't save it — the song isn't anywhere.
Partially acknowledged in impl_notes ("batch-commit ordering… resolve at M3"), but
acknowledgment ≠ resolution: no durable retry/pending queue exists in the plan, and M3's
"no missed messages" acceptance only exercises happy-path + restart, not mid-run add failure.
Real.

### C3 — undefined initial cursor → first run mass-adds history → **CONCEDE (real)**
State stores last-seen ROWID; the bootstrap value on a stateless first run is undefined.
Query is `WHERE m.ROWID > :last_seen`. The natural default (0/NULL→0) returns the entire
message history → every Spotify link a friend ever sent gets parsed and added. Dedup only
suppresses songs already in the playlist/Liked Songs; old friend links you never added flood
in. Mass, unwanted mutation of a live playlist on first launch = wrong output. Real.

---

## Must-fix

### M1 — missing `playlist-read-private` scope → dedup 403 → **CONCEDE (real)**
Scopes in §4: `playlist-modify-private playlist-modify-public user-library-read`. The target
playlist is private (modify-private; non-goal "single private playlist"). Verified against
Spotify docs: **owned/followed non-collaborative private playlists are returned/readable only
with `playlist-read-private`**; `GET /v1/me/playlists` won't surface them, and reading a
private playlist's tracks 403s without it. Dedup source #1 (target playlist) and the opt-in
all-playlists scan both depend on reads the granted scopes don't cover → dedup silently fails
→ duplicate adds. Concrete, documented API-contract error. Real.

### M2 — OAuth callback receiver undefined → **DISPROVEN (not a real defect)**
§4 assigns Auth ("Authorization Code + PKCE, one-time browser login") to `spotify.py`, and
Setup names the loopback redirect URI. Capturing the auth code IS part of "browser login" —
a loopback listener is an ordinary implementation detail inside the already-owned auth
responsibility, and PKCE can even be completed by manual redirect-URL paste with no server.
No stated component is broken; this is granularity, not a gap that yields wrong behavior.

### M3 — config missing client_id / redirect_uri → **DISPROVEN (not a real defect)**
§1 enumerates *user-tunable runtime behavior* (playlist, poll, filters, dedup flags, state).
`client_id`/`redirect_uri` are static, non-secret app credentials naturally owned by
`spotify.py`'s auth module (constant/env), not user knobs. Setup creating them in the Spotify
dashboard does not obligate the config schema to hold them. Any implementer wires the
client_id spotify.py provably needs; omission from the §1 bullet list is not a correctness
defect. Same class as M2.

### M4 — read-vs-write race on attributedBody → **DISPROVEN (theoretical, unproven)**
Predicated on the unverified assumption that Messages COMMITS the message row in one
transaction and writes `attributedBody` in a *separate later* transaction. SQLite transactions
are atomic: a read-only reader sees a committed row complete-with-blob or does not see the row
at all — no partial payload from a single-transaction insert. The prosecution does not
establish the split-commit behavior, and the plan already earmarks attributedBody extraction
as the #1 risk to validate against the real `chat.db` at M1, where any true settle-window would
surface. Burden unmet → not a demonstrated real problem. (Riskiest of the disproves; noted in
holistic.)

### M5 — dedup_all_my_playlists ownership check → **DISPROVEN (not a real defect)**
The plan already states the correct intent: "scan every **owned** playlist." Filtering
`/me/playlists` by `owner.id == me` (and fetching current-user id) is the obvious, trivial
implementation of that stated intent, not a missing plan decision. The feature is opt-in and
default **off**. Adding `GET /v1/me` to the client is impl-note granularity; the plan's word
"owned" already precludes the wrong (scan-followed-too) behavior the finding fears.

---

## Holistic assessment

Even discarding every DISPROVEN item, the four CONCEDED issues are all on the core add-loop and
compound catastrophically **simultaneously**:

- **First launch (C3 + M1):** scans full history and floods the playlist with every historical
  friend link, while the private-playlist dedup reads 403 (M1) so even songs already present are
  re-added as duplicates — a double flood.
- **Steady state (C1):** the immutable open never observes newly-arrived messages, so after the
  flood the daemon adds *nothing new* — it fails the one job it exists for.
- **Whenever an add does fire (C2):** any transient Spotify failure advances the watermark and
  silently drops that song.

**Verdict: NOT correct output.** With C1–C3 + M1 co-occurring the feature both over-adds
(historical flood + duplicates at startup) and under-adds (blind to new links forever, plus
silent loss on failures) — the two failure modes that matter most, together, on day one.
