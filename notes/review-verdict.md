# Code Review Verdict: M1 + M2 backend

Judge pass over review-m1.md, review-m2.md, review-integration.md. Every claim
re-checked against source. Findings deduped into canonical IDs (V1…). Milestone
tag: **M1-now** = user can validate today; **M2-gated** = sits behind Spotify
auth / M2 features the user can't fully exercise yet.

Key reachability fact that reframes several findings: **the full-history scan
(ScanningView, step 5) is only reachable after passing OAuth (step 4).** OAuth's
only forward path is `connectSpotify()` success — there is no skip. So the M1
*picker* (canRead → groupChats → link counts) is testable now, but the M1
*scan* and everything downstream is effectively M2-gated in the wired flow.

---

## Confirmed issues (deduped, prioritized)

**V1 — MAJOR — `persistPlaylists` corrupts every prior playlist's `chatGUID`/`spotifyID`; model can't round-trip either.** `OnboardingState.swift:300-307` (+ model gap `:15-21` vs `Persistence.swift:5-12`, load-drop `:89-91`).
Failure: create playlist from chat A, then "create another" from chat B → row A is rewritten with `chatGUID = B` and `spotifyID = ""`; every non-current row loses its Spotify id and is re-pointed to the latest chat. Compounding: `loadPlaylists` maps `SavedPlaylist→Playlist` dropping both fields, so even one playlist loses them on relaunch — the fields are write-only.
Fix: give `Playlist` durable `spotifyID`/`chatGUID`, map each row from its own identity, not `pickedChat`/`name`.
Milestone: **M2-gated** — reported by all three; blast radius *today is zero* (nothing reads `SavedPlaylist.chatGUID`/`spotifyID` yet — confirmed by grep), but it silently mis-wires the M2 background watcher the moment it's built. Fix before M2 sync lands.

**V2 — MAJOR — Duplicate Spotify playlist / duplicate tracks (two independent mechanisms).** Transport: `SpotifyClient.send:75-77` retries **any** method on 5xx incl. non-idempotent `POST /me/playlists` and `/items` → a 5xx after the write applies duplicates it. App layer: `OnboardingState.createPlaylist:228-250` has **no in-flight guard** (contrast `connectSpotify:212` `!connecting`); `CreatingView.ran` is per-view `@State` reset by `.id(state.step)` (`OnboardingContainer:26`).
Failure: during an in-flight create, swipe back to step 6 and tap "Create playlist" again → second `createPlaylist` → second identical Spotify playlist (local `lists` dedups on name so Home hides it). Or a lost/late 5xx response retries the same batch.
Fix: retry 5xx only for GET; add a `creating` guard; on retry, remember the created playlist id and resume with `addItems` instead of re-creating.
Milestone: **M2-gated.**

**V3 — MAJOR — Timeout leaks the loopback `NWListener` + checked continuation; port stays bound and a retry can hang.** `SpotifyAuth.authorize:60-66`, `LoopbackAuthServer.waitForRedirect:28-65`.
`waitForRedirect` installs **no cancellation handler**; `listener.cancel()` fires only inside `finishOnce`. On the 300s timeout, `redirectTask.cancel()` never resumes the suspended continuation and never cancels the listener → `127.0.0.1:8888` stays bound, continuation leaks (`SWIFT_TASK_CONTINUATION_MISUSE`), and a retry builds a second listener on the same port (`allowLocalEndpointReuse`) whose inbound connection can land on the dead one → retry hangs to its own timeout.
Fix: wrap the continuation in `withTaskCancellationHandler`; on cancel/timeout call `listener.cancel()` and resume-throwing once.
Milestone: **M2-gated.**

**V4 — MAJOR — A queryless connection to :8888 wins the race and aborts a real auth with a bogus "state mismatch".** `LoopbackAuthServer.newConnectionHandler:53-59`, `readRequestLine:68-79`, consumed `SpotifyAuth.swift:68-70`.
`finishOnce` resolves on the **first** connection's `parseQuery`, even `[:]`. A `favicon.ico`/preconnect/port-probe with no `?code&state` → empty dict → `params["state"](nil) != state` → `SpotifyError.stateMismatch` thrown while the real redirect was still inbound. `readRequestLine` also returns `[:]` on a UTF-8 decode failure or a not-yet-complete buffer (single `receive`, no CRLF loop — m5 merges here).
Fix: ignore connections whose parse has neither `code` nor `error` (respond+close, keep listening); read until the request-line CRLF.
Milestone: **M2-gated.**

**V5 — MAJOR (latent) — Actor reentrancy lets two refreshes reuse one single-use refresh token → possible auth brick.** `SpotifyAuth.validAccessToken:78-85`, `refresh:105-121`, `postToken:145`. The type comment (`:24-27`) claims refreshes are serialized; **they are not** — actors are reentrant at the `await` in `postToken`, so two callers past expiry both read the same stored token and both POST it. Spotify rotation invalidates the first use; the second fails and can invalidate the whole grant → full re-auth.
Fix: coalesce with a shared `refreshInFlight: Task<Void,Error>?`; re-check validity after awaiting it.
Milestone: **M2-gated**, and **not triggered by today's call pattern** (create→addItems run serially, token valid for the ~1h session) — but the advertised safety is false and any future parallel call trips it. Fix before adding concurrent API calls / the background watcher.

**V6 — MAJOR — Stale `advance()` fires after a cancelled scan/OAuth and yanks the user forward.** `ScanningView:94-101`, `OnboardingState.performScan:169-204`; sibling in `OAuthConsentView:56`.
`performScan`'s background scan isn't cancellable, so after a swipe-back the continuation still resumes, `try? Task.sleep` swallows the `CancellationError`, and `state.advance()` runs relative to the *new* step → snaps the user back into Scanning (which re-runs the scan). The OAuth button uses an untethered `Task {}` (not `.task`), so swiping back to step 3 doesn't cancel it and success `advance()`s from step 3.
Fix: `guard !Task.isCancelled` before `advance()`; drive OAuth from `.task`, not a detached `Task`.
Milestone: **M2-gated** (Scanning sits behind OAuth).

**V7 — MAJOR — "Create another" forces a redundant full re-auth (F5) and mis-names the second playlist (F6).** `createAnother:313-319`, `OAuthConsentView:55-57`, `connectSpotify:209-225`, `seedNameIfNeeded:322-324`.
`createAnother` marches 2→3→4 and OAuth's button unconditionally calls `connectSpotify()` (no `connected` short-circuit) → reopens the browser + loopback every time, defeating "preserving auth." It also never clears `name`/`desc`, and `seedNameIfNeeded` only seeds when empty → run 2's Customize is pre-filled with run 1's name; if unedited, Spotify gets `name=run1` while `chatName=run2`.
Fix: short-circuit when `connected`; reset `name`/`desc` in `createAnother`.
Milestone: **M2-gated.**

**V8 — MAJOR — Returning user can't reach Home on relaunch; `didOnboard` is written but never read.** `OnboardingState.swift:31` (`step=1`), `:296` (write), `:310` (`go(to:0)` only from `goHome`), `App/FriendListApp.swift:6-7`.
`init` restores `lists` but always starts at Welcome; `go(to:0)` is reachable only from AllSetView (step 8). A user who onboarded + created a playlist, quit, and relaunched lands on Welcome and must re-walk the entire flow (re-auth + re-create) to see their persisted playlists. The one flag meant to fix it (`didOnboard`) is ignored (grep-confirmed).
Fix: at launch, if `didOnboard`, start at step 0 (Home).
Milestone: **M2-gated** — only bites once a create has persisted a playlist (a pure-M1 tester with empty `lists` *should* see Welcome).

**V9 — MINOR — `canRead()` conflates "readable" with "chat table non-empty".** `MessagesReader.swift:58-67`. `ok` is set only inside the row callback; a readable-but-empty `chat` table returns `SQLITE_DONE`, `ok` stays false → `canRead()==false`, so polling never flips `access` and the permission card never clears.
Fix: succeed on query completion regardless of rows (`PRAGMA schema_version`, or set the flag after `query` returns).
Milestone: **M1-now.** Rare (any iMessage/SMS creates a `chat` row), but it's the FDA gate — cheap to harden.

**V10 — MINOR — `accessPollTask` is never cancelled when the picker disappears.** `OnboardingState.swift:138-152`; `PickChatView` has no `.onDisappear` (verified). `[weak self]` doesn't stop the loop (state outlives the view), so navigating back without granting keeps waking every 1.5s for ~4 min, opening a fresh SQLite connection each time.
Fix: cancel `accessPollTask` in `PickChatView.onDisappear` (or on leaving step 2).
Milestone: **M1-now.** Low impact.

**V11 — MINOR — name+chatName dedup key is lossy: drops a real 2nd same-chat playlist and mis-links AllSet.** `completeCreation:288`, `persistPlaylists:301`, `AllSetView:13-15`. Two playlists from the same chat with the same name → 2nd not appended to `lists` and not persisted (vanishes locally though created on Spotify); and `lists.last?.externalURL` then points AllSet's "Open in Spotify" at the wrong (older) row.
Fix: key dedup on a stable id, not name+chatName; carry the just-created URL explicitly into AllSet.
Milestone: **M2-gated.**

**V12 — MINOR — `resumeAtPicker` FDA relaunch-resume is dead (M1 reviewer overstated as MAJOR).** `OnboardingState.swift:133/146`, `Persistence.swift:22-25`, `FullDiskAccess.swift:8`. Set/cleared but never read at launch, so a TCC-forced relaunch reopens at Welcome, not the picker.
Why minor not major: `probeAccessOnAppear` re-probes when the user reaches step 2 and the permission card already says "quit and reopen," so access still works — the dead marker costs a couple of clicks, not functionality.
Fix (optional): read `resumeAtPicker` at launch to jump to step 2. Milestone: **M1-now** (cosmetic).

**V13 — INFORMATIONAL — `recordSeen`/`seenTracks` is write-only today.** `OnboardingState.swift:293-295`, `Persistence.swift:49-59`. Cross-run dedup never consults the persisted set; the scan dedups per-run only. Acceptable as reserved M2 wiring — flagged, not a defect.

**Minor polish bundle (all CONFIRMED, low-value, M2-gated unless noted):**
- **m6** `PKCE.randomBytes:25` ignores `SecRandomCopyBytes` return → all-zero verifier/state if it ever fails. Trap on non-`errSecSuccess`. (crypto root; cheap.)
- **m7** `Keychain.set:16-26` delete-then-add is non-atomic and uses `AfterFirstUnlock` (not `…ThisDeviceOnly`). Prefer update-or-add + device-only.
- **m8** `SpotifyClient.addItems:33-40` 404 fallback conflates "endpoint renamed" with "playlist not found" → one wasted POST on a genuine 404 (not masking).
- **m9** `createPlaylist:238-243` per-callback `Task { @MainActor }` progress updates can reorder / leave the bar <1.0. Cosmetic. Use `await MainActor.run`.
- **m10** `Keychain.clearTokens:55-57` doesn't reset a live `SpotifyAuth`; its access token stays usable ~1h after "clear." Narrow today.

---

## Rejected / overstated

- **M1#5 locale regex `intl-[a-z]{2}`** — REJECTED as a live bug. Spotify's `intl-` prefixes are always 2-letter language codes; the reviewer already concedes "not a live defect." Brittleness note only. (`LinkParser.swift:29`.)
- **m11 fixed port + `allowLocalEndpointReuse` code interception** — NOT A BUG. Standard RFC 8252 loopback risk, fully mitigated by PKCE (stolen `code` is useless without the verifier). Informational.
- **M1 reviewer's MAJOR on `resumeAtPicker`** — OVERSTATED → downgraded to MINOR (V12); the picker re-probes on appear, so nothing is actually broken.
- **"No data races" / "no continuation leaks in performScan" / "NWListener needs no entitlement" / SQL-injection-clean / NULL ordering / blob byte-scan safety** — all three reviewers attacked these and correctly cleared them. Verified: agree, non-issues.

**Missed-by-a-reviewer note:** M1 and integration both examined the scan path but neither flagged that **ScanningView is unreachable without completing OAuth** — meaning the M1 full-scan cannot be validated today without real Spotify credentials. Only the *picker* half of M1 is independently testable now. Worth knowing before the user tries to "test M1."

---

## Fix order

### Must-fix before the backend is trustable
1. **V2** — guard `createPlaylist` re-entrancy; stop retrying 5xx on POSTs; resume-with-`addItems` on retry. (Duplicate playlists = the most user-visible data bug.)
2. **V1** — restructure the playlist model so `spotifyID`/`chatGUID` round-trip per row. (Structural; unblocks every M2 feature. Latent today but poisons M2 sync silently.)
3. **V3** — cancellation handler + `listener.cancel()` on timeout. (Leaked port makes a second auth attempt hang.)
4. **V4** (+m5) — only finish the loopback on `code`/`error`; read to CRLF. (Flaky auth failures on real machines.)
5. **V5** — coalesce refresh with an in-flight `Task`. (Do before any concurrent API use / background watcher.)
6. **V6** — `guard !Task.isCancelled` before `advance()`; drive OAuth from `.task`.
7. **V7** — short-circuit OAuth when `connected`; reset `name`/`desc` in `createAnother`.
8. **V8** — consult `didOnboard` at launch to land returning users on Home.
9. **V9, V10** — the two **M1-now** minors (empty-table false negative, uncancelled poll loop) — quick wins the user can hit while testing the picker.

### Polish / defer
- **V11** (lossy dedup key + wrong AllSet link), **V12** (dead FDA resume marker), **V13** (unused seen-set), **m6–m10**. All low blast radius; batch them after the must-fix set.

---

## Bottom line

The **M1 read layer is solid and trustworthy** — the SQL, the deliberate blob byte-scan, per-run dedup, and off-main thread-safety all hold up under scrutiny; the only M1-now defects are two minor edge cases (empty-`chat`-table false negative, an uncancelled 4-minute poll loop), and note the full scan can't actually be exercised until Spotify auth works. The **M2 layer is not yet trustworthy**: it carries four real major bugs (loopback leak/hang on timeout, a queryless-connection race that fails legit auths with a bogus "security check," a refresh-token reentrancy path that can brick the grant, and non-idempotent create/retry that duplicates playlists), plus a structural persistence bug that will silently mis-attribute every playlist's Spotify/chat identity once M2 reads those fields. Blast radius of the real bugs: duplicate or wrong-named Spotify playlists, transiently unreconnectable auth, and worst-case a bricked grant needing full re-auth — but **all of it is M2-gated**, so none of it blocks the user validating M1's picker today.
