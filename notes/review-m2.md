# M2 Spotify Auth — Adversarial Security Review

Reviewer: skeptical senior eng (security focus). Date: 2026-07-26.
Scope: PKCE, LoopbackAuthServer, Keychain, SpotifyAuth, SpotifyClient, SpotifyService, SpotifyConfig, OnboardingState (connect/create), OAuthConsentView.

External facts verified this session:
- Spotify `POST /v1/playlists/{id}/items` is the current endpoint; `/tracks` is deprecated (Feb-2026 changelog). Max 100 URIs/request. So the `/items`-then-`/tracks` fallback is legitimate insurance, and 100-chunking is correct.
- Spotify PKCE refresh tokens **are single-use / rotated**; the old refresh token is invalidated on use, and presenting an already-used token can invalidate the whole grant. The refresh response **may omit** `refresh_token`. This confirms the "only overwrite when present" guard is correct AND that concurrent refreshes are dangerous.
- App is **non-sandboxed** (`app-sandbox=false`, `network.client=true`), so `NWListener` accepting inbound loopback connections needs no `network.server` entitlement. Not a bug today (would break if ever sandboxed).

---

## CRITICAL / MAJOR

### M1. Timeout path leaks the NWListener and the checked continuation (port stays bound)
`SpotifyAuth.authorize` SpotifyAuth.swift:62-66, `LoopbackAuthServer.waitForRedirect` LoopbackAuthServer.swift:28-65.

`redirectTask = Task { try await server.waitForRedirect() }` … `defer { redirectTask.cancel() }`, and `withTimeout(seconds: 300)` throws `timedOut` if the redirect never arrives. `waitForRedirect` suspends inside `withCheckedThrowingContinuation` and installs **no cancellation handler**. Cancelling `redirectTask` sets `isCancelled` but never resumes the continuation and never calls `listener.cancel()` (that only happens inside `finishOnce`, which is only invoked by a real connection or a listener `.failed` state).

Failure scenario: user opens the authorize page, closes the tab / never approves. After 300s `authorize` throws timedOut, but:
- the `NWListener` stays bound to `127.0.0.1:8888` for the life of the process,
- the checked continuation is leaked → `SWIFT_TASK_CONTINUATION_MISUSE` runtime warning,
- a subsequent "Authorize" retry constructs a new listener on 8888; the stale one is still there. `allowLocalEndpointReuse` may let the new bind succeed, but now **two** listeners exist and inbound connections can land on the dead one (whose continuation is gone) — the retry can hang until its own 300s timeout.

Fix: give `waitForRedirect` a real cancel path — `cont` captured in `withTaskCancellationHandler`, and on cancel/timeout call `listener?.cancel()` + resume-throwing once. Or have `authorize` hold the server and `defer { listener.cancel() }` unconditionally.
Severity: **major**.

### M2. "Serializes refreshes" is false — actor reentrancy allows a concurrent single-use-token stampede that can brick auth
`SpotifyAuth.validAccessToken` SpotifyAuth.swift:78-85, `refresh` 105-121, `postToken` 145.

The type comment (SpotifyAuth.swift:24-27) claims refreshes are serialized. They are not. `refresh()` reads the stored refresh token, then `await`s `URLSession.shared.data` in `postToken` — a suspension point. Actors are **reentrant at await**, so while task A is suspended in the network call, task B can enter `validAccessToken`, still see `accessToken` expired (A hasn't returned/`apply()`d yet), and call `refresh()` reading the **same** stored refresh token. Both POST the same single-use token.

Per Spotify's rotation semantics (verified), the first use invalidates that refresh token; the second request fails, and presenting an already-used token can invalidate the entire grant → **permanent brick, forcing full re-auth**. There is no in-flight-refresh coalescing (no shared `Task<Void,Error>` guard).

Trigger surface in M2 is narrow but real: two `SpotifyClient` operations awaiting `validAccessToken()` concurrently after the access token has expired (e.g., a long onboarding session past the ~1h token life, or any future parallel API calls). The code advertises safety it doesn't have.

Fix: coalesce — store `private var refreshInFlight: Task<Void, Error>?`; first caller creates it, others `await` it; clear on completion. Re-check `accessToken` validity *after* acquiring the in-flight result.
Severity: **major** (data-loss / brick; conditional trigger).

### M3. A queryless request to :8888 wins the race and aborts a legitimate auth with a bogus "state mismatch"
`LoopbackAuthServer.newConnectionHandler` LoopbackAuthServer.swift:53-59, `readRequestLine` 68-79, `finishOnce` 31-37; consumed at SpotifyAuth.swift:68-70.

`finishOnce` resolves on the **first** connection whose `readRequestLine` completes, with whatever `parseQuery` returns — including `[:]`. Any request to `127.0.0.1:8888` that carries no `?code&state` (a browser `favicon.ico`/preconnect that actually sends a request line, a security tool probing the port, a stray tab) resolves the continuation with an empty dict. Back in `authorize`: `params["error"]` is nil, `params["state"]` is nil which `!= state` → throws `SpotifyError.stateMismatch`. The user sees "failed a security check" even though the real redirect was on its way. Same empty-dict result if `String(data:encoding:.utf8)` fails or the buffer lacks `\r\n` yet (readRequestLine returns `[:]` rather than reading more).

Fix: don't finish on an empty/`code`-less parse — ignore that connection (respond/close but keep listening) and only `finishOnce` when `code` or `error` is present, still bounded by the outer timeout.
Severity: **major** (reliability; user-visible auth failure).

### M4. Non-idempotent POSTs are auto-retried on 5xx → duplicate tracks / duplicate playlists
`SpotifyClient.send` SpotifyClient.swift:75-77 (`case 500..<600 where attempt < 3`).

`send` transparently retries **any** method on 5xx, including `POST /me/playlists` and `POST /playlists/{id}/items`. These are not idempotent (no idempotency key — Spotify offers none). If Spotify returns 5xx *after* having applied the write (or the response is lost), the retry adds the same ≤100-URI batch again → **duplicate tracks**, or creates a **second playlist**. The 429 retry has the same shape but is safe-ish (429 means not-processed).

Compounding at the app layer: `OnboardingState.createPlaylist` (OnboardingState.swift:236) calls `client.createPlaylist` unconditionally, and its `catch` (247-249) leaves the user on the Creating screen; `back()` from step 7 goes to Customize (step 6), and re-running create calls `createPlaylist` again → yet another playlist even if the first POST actually succeeded before the failure.
Fix: only retry 5xx for idempotent GETs (or cap POST retries to network-level "definitely not sent" errors). At the app layer, remember a created playlist id and resume with `addItems` instead of re-creating.
Severity: **major** (data correctness).

---

## MINOR

### m5. Single `receive()` can truncate the request line (no read loop)
`readRequestLine` LoopbackAuthServer.swift:69. `minimumIncompleteLength: 1` returns on the first byte available; there is no loop to accumulate until `\r\n`. On loopback the request line (~250 bytes) almost always arrives in one segment, so this is low-risk, but a split segment would drop the `code` and surface as M3's bogus state-mismatch. Robust servers read until the CRLF terminating the request line.
Severity: minor.

### m6. `SecRandomCopyBytes` return value ignored
`PKCE.randomBytes` PKCE.swift:25 (`_ = SecRandomCopyBytes(...)`). If it ever fails, `bytes` stays all-zero → predictable `code_verifier` and `state`. Vanishingly unlikely, but this is the crypto root of the flow; it should throw/trap on non-`errSecSuccess`.
Severity: minor (defense-in-depth).

### m7. Keychain write is delete-then-add (non-atomic) and not device-only
`Keychain.set` Keychain.swift:16-26. `delete` then `SecItemAdd`: if the process dies between, the refresh token is gone (recoverable — user re-auths, so low impact). `SecItemUpdate`-or-add would be atomic. Also `kSecAttrAccessibleAfterFirstUnlock` (not `…ThisDeviceOnly`) is acceptable but weaker than ideal for a rotating secret; items aren't `kSecAttrSynchronizable` so they won't iCloud-sync today.
Severity: minor.

### m8. 404 fallback conflates "endpoint renamed" with "playlist not found"
`SpotifyClient.addItems` SpotifyClient.swift:33-40. A genuine "playlist deleted/not found" also returns 404, so a real error triggers a pointless second POST to `/tracks` (also 404) before the error finally surfaces. Not masking (the error still propagates), just a wasted request and a slightly misleading control path. Since the playlist was just created, low probability.
Severity: minor.

### m9. Per-callback `Task { @MainActor }` progress updates can reorder / land < 1.0
`OnboardingState.createPlaylist` OnboardingState.swift:238-243. Each progress callback spawns an unstructured `Task`; execution order of multiple such Tasks on the main actor is not guaranteed to match creation order → the bar can jump backward. The service's final `progress(1,"Done")` Task races with the direct `createPct = 1` at line 244; a delayed earlier-fraction Task can run last and leave the bar at ~0.95. Cosmetic but visible. Prefer `await MainActor.run` inside the (already awaited) call chain, or a serial `MainActor`-isolated setter.
Severity: minor.

### m10. `clearTokens()` doesn't reset an in-memory `SpotifyAuth`
`Keychain.clearTokens` Keychain.swift:55-57 only deletes the keychain refresh token. A live `SpotifyAuth` actor still holds a valid `accessToken`/`expiresAt` (~1h). In the current flow `SpotifyService.connect` always builds a fresh `SpotifyAuth` (SpotifyService.swift:34), so the stale token isn't reachable after a client-id change — but there's no explicit "disconnect" that invalidates the cached actor, and the access token remains usable for up to an hour after "clearing." Narrow today; worth a comment or an explicit reset.
Severity: minor.

### m11. Fixed loopback port + `allowLocalEndpointReuse` — code interception, PKCE-mitigated
`LoopbackAuthServer` :41, `SpotifyConfig.redirectURI` :17. Because the redirect URI is a fixed `127.0.0.1:8888`, a co-resident local process could pre-bind the port (reuse flag eases races) and capture the authorization `code`. This is the known RFC 8252 loopback risk; it is **mitigated by PKCE** — the attacker never sees the `code_verifier`, so a stolen `code` can't be exchanged. Acceptable for a desktop app; noting for completeness.
Severity: informational.

---

## Verified SOLID (attacked, held up)

- **CSRF/state ordering:** `state` is checked (SpotifyAuth.swift:69) *before* `exchangeCode` (72), and `error` is handled first (68). Correct.
- **Verifier entropy/encoding:** 64 random bytes → ~86 base64url chars, within RFC 7636's 43–128; base64url mapping strips `=`, swaps `+//` correctly. `S256` challenge correct.
- **Refresh-guard logic is correct and necessary:** only overwrites the stored refresh token when a non-empty one is returned (SpotifyAuth.swift:118-120). Not inverted. Spotify confirmed to omit `refresh_token` on many refreshes, so the guard prevents bricking. Good.
- **URL construction:** `base = …/v1` (no trailing slash) + `appendingPathComponent(path.dropFirst())` yields `https://api.spotify.com/v1/me/playlists` and `…/v1/playlists/{id}/items` — `/v1` preserved, no double-encoding. Correct.
- **Chunking:** `chunked(100)` via `stride(by:100)` + `min($0+100,count)` — no off-by-one; empty input → `[]`. Correct, matches Spotify's 100 max.
- **Privacy posture:** scope is least-privilege `playlist-modify-private`; `createPlaylist` sends `public:false`; consent UI mirrors the single scope. Correct.
- **Redirect literal:** `http://127.0.0.1:8888/auth-callback` matches Spotify's post-2025 loopback rule (no custom scheme, no `localhost`). Correct.
