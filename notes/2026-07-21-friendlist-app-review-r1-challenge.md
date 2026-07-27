# Friend List — R1 Review Challenge (Defense / "is it REAL?")

Role: skeptical senior engineer testing whether each R1 finding is a *real* defect
(not a phantom / misread / context-blind / theoretical-only / already-addressed).
Severity is the Judge's job — I only test reality, and CONCEDE when the plan genuinely
produces wrong behavior or breaks the core promise (auto-add friend-sent songs,
privately, set-and-forget).

Two platform facts were verified against primary sources rather than assumed:
- **Spotify PKCE refresh tokens**: the Auth-Code-with-PKCE flow *always* returns a new
  refresh token on refresh, and a PKCE refresh token is **single-use** — it can be
  exchanged exactly once, then is invalid (Spotify dev community / docs). So persisting
  the rotated token, with a single refresh owner, is a hard requirement, not a nicety.
- **Spotify dev-mode quota**: as of Mar 9 2026, dev mode caps at **5 users** (was 25),
  one dev-mode client ID per developer, Premium required; extended quota requires a
  legally registered business + 250k MAU (organizations only since May 15 2025).

---

## Critical

### C1 — FDA won't cover the separate agent binary — **CONCEDE**
macOS TCC Full Disk Access is keyed per-executable code identity; this is a real
platform fact, not an assumption. The plan's architecture runs `chat.db` reads in a
*separate* `friendlist-agent` binary, and the happy-path assumption that the app's grant
propagates to it is genuinely unreliable — if it doesn't, the agent's reads are denied
and the core "seeing" function silently never runs. The plan *does* flag this (Risks
bullet 1) and offers "guide granting it explicitly," so the finding's "silently never
runs" is only the *unmitigated* path — but the underlying defect (a design that hinges
on an unreliable TCC propagation, or forces a second manual grant on a headless helper
users can't easily locate) is real. Conceded; note the plan already acknowledges it and
the single-executable fix is the clean resolution.

### C2 — Shared-client_id public distribution non-viable under quota — **CONCEDE**
Verified platform fact. Dev mode = 5 users/app, one dev-mode client ID per developer;
extended quota needs a registered business + 250k MAU (orgs only). The plan states as a
design decision "One Spotify developer app backs all installs" and promises web download
/ public distribution. Those two cannot coexist: a single shared client_id serves ≤5
users. The plan flags this (Risks: "must request extended quota... or stays
personal/allow-listed. Decide before M5") — so it's acknowledged and deferred, not a
phantom — but the stated shared-client_id + public-download model is genuinely blocked.
Conceded; BYO-client_id (or personal-only) is the real resolution.

---

## Must-fix

### M1 — Two concurrent writers to shared state container — **DISPROVEN**
Misread. The plan describes **StateStore** (Component 8: last_seen, seen-set, retry
queue — agent-owned runtime state) and **Settings** (Component 9: playlist name, pause,
scope, dedup toggles — app-owned) as *distinct components with distinct data*. "Same
container" means same Application Support **directory**, not the same file; two writers to
one directory is not corruption. The natural partition (agent owns runtime state, app
owns settings) already is the finding's own fix. Nothing in the plan says a single file
with two writers to identical records. Under-specified at most, and explicitly moot under
C1's single executable.

### M2 — Refresh-token rotation: ownership + persistence — **CONCEDE**
Grounded in verified Spotify behavior: PKCE **always** issues a new refresh token and the
token is **single-use**. So (a) if the rotated token isn't atomically persisted on every
refresh, the *next* refresh uses a dead token and auth silently dies — adds stop,
set-and-forget broken; and (b) two holders (app + agent) of one single-use token means
one loses the race. The plan says "store the refresh token in Keychain... silent
access-token refresh" but never specifies persisting the rotated value or a single
refresh owner. Real correctness defect against a confirmed platform fact. Note: the
two-writer race is narrow in steady state (app closed post-onboarding) and moot under C1,
but the single-use persistence requirement bites even a lone writer. Conceded.

### M3 — Watermark advancement can silently drop adds — **DISPROVEN**
Misread of the plan's own wording. §Daemon loop says the watermark advances past every
*terminally-resolved* message and "the **only** thing that holds the watermark is an add
that failed *before* its URI reached the durable retry queue." That is precisely
"stop at the first unresolved message; never advance past a hole" — the finding's exact
proposed fix. The failed-before-enqueue message *holds* (blocks) the watermark, so
advancement is contiguous by construction. No dropped adds. Phantom.

### M4 — Dev-mode email allowlist contradicts privacy — **DISPROVEN**
Context-blind / contingent. The plan **never collects user email** anywhere. The
email-allowlist obligation only materializes if one specifically chooses the
"shared-client_id + dev-mode + distribute to strangers" path — which the plan explicitly
leaves undecided and offers alternatives to ("stays personal/allow-listed" OR extended
quota, decide at M5). A consequence of an un-made decision is not a present contradiction
in the plan, and it's moot under C2's BYO-client_id resolution (each user owns their app,
no allowlist). Not a real defect of the plan as written.

### M5 — Denied/never-granted FDA has no path — **DISPROVEN**
Not a functional defect. The plan already specifies probe-read detection + explainer +
`x-apple.systempreferences:` deep link + poll-for-access (Component 1 / Onboarding 2).
That mechanism *works* for the grant case. Permanent denial can't be "skipped" because
the app genuinely cannot function without FDA — so looping/paused is the honest behavior,
and a "still waiting / try again" nudge is a UX refinement already captured as L4, not a
missing capability. No wrong behavior produced.

### M6 — Revoked Spotify token has no recovery — **DISPROVEN**
The escape hatch already exists: the plan's `MenuBarExtra` is explicitly for "status,
pause/resume, open playlist" — a revoked-token/"Reconnect Spotify" state is a natural use
of the existing status surface, not a missing capability. Token revocation is a
user-initiated / Spotify-side edge (password change, manual revoke), not normal
set-and-forget operation. The finding flags an unspecified detail (how the agent signals
the UI), not a design gap. "Never needs opening" is a day-to-day claim; the menubar is the
already-planned exception surface.

### M7 — Privacy section contradicts what is persisted — **DISPROVEN**
Misquote. The finding drops the plan's caveat. §Privacy reads "only Spotify track IDs are
persisted (seen-set), never message content or contact identifiers **beyond what
filtering needs locally**." `allowed_chats` / `allowed_handles` *are* exactly the
filtering identifiers the caveat admits. The actual privacy **pillar** is "no user data
leaves the Mac" — every field cited (filter lists, retry-queue source chat/sender) is
local-only, so the pillar is intact. The only residue is the retry queue's source
chat/sender, a trivially trimmable local convenience field, not an off-device leak. No
real contradiction with the promise.

### M8 — FDA grant forces relaunch; resume unspecified — **DISPROVEN**
Premise is overstated. macOS does **not** force-relaunch an app when FDA is granted; it
offers an optional "Quit & Reopen" the user can defer. The plan's fresh-connection
poll-for-access covers the live-grant case without any relaunch. Even in the worst case
(user manually quits & reopens), `didOnboard` false just replays ~2 onboarding screens —
now with FDA working and the picker populated. Annoying, not broken. UX polish, not a
functional defect.

---

## Verdict summary

| ID | Verdict | One-line reason |
|----|---------|-----------------|
| C1 | CONCEDE | Real platform fact: separate agent binary needs its own FDA; app-grant propagation is unreliable → core "seeing" can silently fail (plan flags it). |
| C2 | CONCEDE | Verified: dev mode = 5 users/1 client ID, extended quota needs 250k MAU/registered org — shared client_id + public download can't coexist. |
| M1 | DISPROVEN | Misread: StateStore vs Settings are distinct data; "container" = directory, not one file; natural single-writer partition (moot under C1). |
| M2 | CONCEDE | Verified: PKCE refresh tokens are single-use & always rotate — no atomic persist / single owner → auth silently dies (set-and-forget breaks). |
| M3 | DISPROVEN | Misread: plan already holds the watermark at the first not-yet-enqueued failed add = the exact "stop at first hole" fix. |
| M4 | DISPROVEN | Plan never collects email; allowlist need only under an undecided distribution path; contingent, not committed (moot under C2 fix). |
| M5 | DISPROVEN | Probe + explainer + deep link + poll already specified; permanent-denial handling is UX (L4), and FDA is genuinely mandatory to function. |
| M6 | DISPROVEN | Menubar status surface already exists for exactly this; revocation is an edge, not normal operation — an unspecified detail, not a gap. |
| M7 | DISPROVEN | Finding drops the caveat "beyond what filtering needs locally"; filter lists are that; all on-device → privacy pillar intact. |
| M8 | DISPROVEN | macOS doesn't force-relaunch on FDA grant; poll covers live grants; worst case replays 2 screens with FDA now working. |

Tally: **2 CONCEDE (C1, C2) + 1 CONCEDE (M2) = 3 conceded; 7 disproven (M1, M3–M8).**

---

## Holistic — do the survivors, taken together, break the core promise?

The seven disproven findings (M1, M3–M8) are UX under-specification and misreads of the
plan's own text; even co-occurring they don't stop friend-sent songs from being auto-added
privately and hands-off. The three conceded items are the real ones, and each
independently threatens a *different* leg of the promise: **C1** the "seeing"
(agent may not read `chat.db`), **C2** the "download it" public distribution (≤5 users on
a shared client_id), and **M2** the "set-and-forget" longevity (single-use token not
persisted → auth silently dies). Crucially all three are already named in the plan's own
Risks section with viable mitigations (single-executable to unify TCC identity;
BYO-client_id or personal-only for quota; persist the rotated single-use token under one
owner) — so with those applied the core promise holds, and only the *unmitigated* plan
degrades.
