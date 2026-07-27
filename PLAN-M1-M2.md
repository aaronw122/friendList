# Friend List — M1 + M2 Implementation Plan (v2)

**Scope:** make the existing onboarding UI actually work end-to-end — read the selected group chat's history locally (M1), then authenticate with Spotify via PKCE and write the tracks into a real playlist (M2). This supersedes the M1/M2 sections of `PLAN.md` where they conflict; see **What changed** below.

**Status going in:** the full onboarding UI is built (SwiftUI + SpriteKit) but every action is mocked — hardcoded sample chats, boolean "auth", timed fake loaders, a local mock playlist. Nothing touches `chat.db` or the Spotify API. This plan replaces those mocks with real services behind the same `OnboardingState`.

---

## What changed since the original PLAN.md (why a v2)

| Area | Original plan | Now |
|---|---|---|
| **Dedup** | ISRC-aware; checks target playlist + Liked Songs + owned playlists | **In-app only**: a track is added once per chat; if the same track is sent again in that chat, skip it. No reading of playlists or library. |
| **Scopes** | `playlist-modify-private user-library-read playlist-read-private` | **`playlist-modify-private` only** |
| **Auth** | PKCE, custom scheme | PKCE, **no client secret**, **loopback redirect `http://127.0.0.1:<port>/auth-callback`** (custom scheme `friendlist://` is empirically rejected at `/authorize` for apps created after 2025-04-09 — see M2.1) |
| **Onboarding UX** | 5 sheet screens | Rebuilt: content on a persistent desk/objects background (no sheet), objects only on Welcome+Home, global Back + swipe, chat picker with search/recency/pins, split Log-in/Dashboard Spotify steps |
| **Premium** | "required" | **Required after all** — not for the API calls themselves, but Spotify's Feb-2026 dev-mode rule (effective 2026-03-09) requires the **app owner** to hold active Premium for a Development-Mode app to function. Because this is BYO-client-id, the user *is* the owner → **Premium is a hard precondition.** Onboarding must state it. |
| **Spotify endpoints** | `POST /users/{id}/playlists`, `POST /playlists/{id}/tracks` | **`POST /v1/me/playlists`**, **`POST /v1/playlists/{id}/items`** (the `/tracks` path is deprecated) — verified against live docs |

---

## Architecture seam (how the backend wires to the existing UI)

The UI is driven by `OnboardingState` (`@Observable`). Keep the UI untouched; inject real services and have the (currently mock) actions call them. Define a thin protocol layer so the UI has no direct dependency on SQLite/URLSession:

```
protocol MessagesReading   // M1: enumerate chats, scan a chat's links
protocol LinkParsing       // M1: text -> [spotify track id], + youtube count
protocol SpotifyAuthing    // M2: PKCE login, token refresh (Keychain-backed)
protocol SpotifyAPI        // M2: me(), createPlaylist(), addItems()
protocol SeenStoring       // in-app dedup: per-chat set of added track ids
```

`OnboardingState` gains injected services (default = real; previews/tests = fakes). The wiring points that change from mock → real:
- **Pick chat step:** `chats` comes from `MessagesReading.groupChats()` instead of the hardcoded array.
- **Connect Spotify:** the button runs `SpotifyAuthing.login(clientID:)` (real `ASWebAuthenticationSession`).
- **Scanning:** `MessagesReading.scan(chat:)` + `LinkParsing` drive `scanPct/found/scanLabel`.
- **Creating:** `SpotifyAPI.createPlaylist` + `addItems` (deduped via `SeenStoring`) drive `createPct/createLabel`.
- **Home / All-set:** real playlist id + external URL; persisted so it survives quit.

No functional UI change — only the data behind it becomes real.

---

## Cross-cutting prerequisites (do these first — the plan previously omitted both)

### C1. Stable code-signing identity (unblocks the M1 FDA dev loop)
`project.yml` currently sets `CODE_SIGN_IDENTITY: "-"` (ad-hoc) and `DEVELOPMENT_TEAM: ""`. Ad-hoc signing mints a **new cdhash every rebuild**; TCC keys the Full Disk Access grant on signature + bundle id, so every rebuild reads as a new app and **silently drops the FDA grant** — which would force re-granting FDA on nearly every M1 iteration. Fix (no paid Apple account needed): create a stable **self-signed certificate** in the login keychain and point `CODE_SIGN_IDENTITY` at it (or use a real `DEVELOPMENT_TEAM`). Do this before any M1 testing.

### C2. Persist `OnboardingState` (the current object is ephemeral)
`OnboardingState` is `@State`-held with no persistence and no `didOnboard`. The plan's FDA relaunch-resume and "Home survives quit" both require durable state. Add:
- A persisted **step marker + `didOnboard`** flag (UserDefaults or a small file) so the FDA "Quit & Reopen → relaunch → resume at picker with access" loop works.
- Persisted **`{chat_guid → playlist_id}` + playlist external URL** (Application Support, `Codable` or small SQLite) so Home shows the real playlist after relaunch.
- The **per-chat seen-set** (`SeenStore`, see M2.4) lives here too.

---

## M1 — Read the stream (`chat.db` → Spotify links)

**Goal / done-when:** picking a real group chat lists your actual conversations (with a per-chat "N Spotify links found" preview); the scan parses that chat's history and yields real `spotify:track:{id}`s from **both** the `text` column and the `attributedBody` blob, on this machine.

### 1. Full Disk Access
- On the pick-chat step, probe-read `~/Library/Messages/chat.db`. On failure, show the existing permission card, deep-link to `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles`, and poll for the grant.
- **Survive the grant relaunch:** persist an onboarding-step marker; on relaunch with `didOnboard == false`, reactivate and resume at the picker with access in hand. (macOS "Quit & Reopen" kills the process; the current process can't see new access until relaunch.)

### 2. `MessagesReader` (read-only SQLite)
- Open with `SQLITE_OPEN_READONLY` on a **fresh connection per query** (chat.db is a live WAL DB; a long-lived handle hides new rows). Do **not** use any immutable flag. Raw `sqlite3` C API via a thin wrapper (or GRDB read-only config).
- **Enumerate group chats** for the picker: join `chat` / `chat_message_join` / `message` / `handle`. **Group-detection predicate (ordered, per the canonical `imessage-exporter` source, which distinguishes by participants — not by any single magic column):**
  1. **Primary:** `COUNT(chat_handle_join.handle_id) > 1` (participant count).
  2. **Trusted secondary:** `chat.style = 43` (group) / `45` (DM).
  3. **Weak tertiary:** `chat.room_name IS NOT NULL` — corroborating hint only (has SMS/MMS failure modes).
  - Caveat: a group decayed to a single remaining participant misclassifies as a DM under strict `> 1` — acceptable edge, note it in code.
  - Return `{guid, display_name, message_count, last_message_date}`. Sort by `last_message_date` for recency.
- **Pre-scan link count:** for the picker's "N links" preview, run a fast count of Spotify-link matches per chat (cap work — scan most-recent N messages or use a `LIKE '%open.spotify.com%'` prefilter on `text`, plus a bounded `attributedBody` pass).
- **Per-chat backfill query:** `WHERE cmj.chat_id = :id ORDER BY m.ROWID ASC`, `GROUP BY m.ROWID` (a message can join multiple chats). Columns: `ROWID, text, attributedBody, is_from_me, handle.id, chat.guid`.

### 3. `attributedBody` decoding (the main technical risk)
- Modern macOS stores link-message text in the `attributedBody` blob (`NSArchiver`/`streamtyped`/`typedstream`, **non-keyed**) with `text = NULL`.
- **Decode order (corrected — byte-scan is PRIMARY):**
  1. Try `text` if non-null.
  2. **Primary for the blob: byte-scan.** `String(decoding: blob, as: UTF8.self)` (lossy U+FFFD replacement cannot corrupt an all-ASCII `https://open.spotify.com/track/…` or `spotify:track:…` run), then regex over it. Simplest and most macOS-version-robust for a link-only use case.
  3. **Tertiary source:** byte-scan `message.payload_data` too (rich URL-preview balloons store the URL there).
  - **Removed:** `NSAttributedString(data:documentAttributes:)` — a **dead path** (it decodes RTF/RTFD/HTML/DocFormat document blobs, and *throws* on a typedstream blob). `NSKeyedUnarchiver` also fails (not keyed archiving); `NSUnarchiver` is unavailable in Swift.
  - **Optional polish:** a real typedstream parser (Madrid's `TypedStreamDecoder` / imessage-exporter's `streamtyped`) only if formatted-text fidelity ever matters — not needed for links.
- **Validate on a real `chat.db` early** — this is the make-or-break M1 detail and varies by macOS version. Confirm byte-scan pulls `spotify:track:` ids from real blobs on **this** machine (macOS 26.5.2) before building further.

### 4. `LinkParser`
- Spotify (v1 target): `https?://open\.spotify\.com/(?:intl-[a-z]{2}/)?track/([A-Za-z0-9]+)` (allow `/intl-xx/`, strip `?si=`); also `spotify:track:ID`. Output canonical `spotify:track:{id}`. Tracks only.
- YouTube: match + **count** only (surface a quiet "also found N YouTube links" line); do not build a YT playlist (v2).

### 5. Wire into the UI
- Replace `OnboardingState.chats` with real enumerated group chats; the picker's search/recency already work over that list.
- **Pinned chats — open question:** Messages' pinned conversations are stored outside `chat.db` (a preferences plist), so pins may not be readable. Options: (a) drop the pin feature, (b) let the user pin within Friend List (local), (c) best-effort read of the plist. **Decide during M1.**
- Real scan drives `scanPct/found/scanLabel`; keep the existing status-line cadence but from real progress.

### M1 risks
- `attributedBody` decoding across macOS versions (validate first).
- FDA grant + relaunch resume.
- Pre-scan performance on large chats (bound the work; show a spinner).
- Pins not available from `chat.db`.

---

## M2 — Spotify path (PKCE auth + real playlist write), in-app dedup

**Two external gates first (~10 min each — run BEFORE any M2 code; either failing reshapes the auth core and onboarding copy):**
1. **Owner Premium.** Confirm the account creating the Spotify app holds active Premium. Since 2026-03-09 a Development-Mode app only functions if its **owner** has Premium; BYO-client-id means the user is the owner. No Premium → flow is dead for that user; Premium becomes stated onboarding copy.
2. **Redirect-URI feasibility.** On a fresh Dev-Mode app, try to save **and authorize** a redirect URI. Expect the custom scheme `friendlist://auth-callback` to be **rejected** at `/authorize` (`INVALID_CLIENT: Insecure redirect URI`) for any app created after 2025-04-09 → pivot to **loopback `http://127.0.0.1:<port>/auth-callback`** (only HTTPS + `127.0.0.1`/`[::1]` literals are accepted; `localhost` is also banned).

**Note on the old "dev-mode can't write" fear:** it was *unfounded* — dev-mode writes work. `POST /v1/me/playlists` and `POST /v1/playlists/{id}/items` both survive the Feb-2026 changes (which only removed some batch-GET/browse endpoints). The real gates are the two above.

### 1. PKCE auth (`SpotifyAuth`) — loopback listener (not custom scheme)
- **Redirect mechanism:** bind a local `NWListener` on `127.0.0.1:<ephemeral port>`, build `redirect_uri = http://127.0.0.1:<port>/auth-callback`, open the authorize URL in the user's browser, and catch the `GET /auth-callback?code=…&state=…` on the socket; respond with a tiny "you can close this tab" HTML page, then tear the listener down. `ASWebAuthenticationSession(callbackURLScheme:)` matches **custom schemes only, never `http`** — so it can't capture a loopback redirect and is dropped. Remove the `friendlist` scheme from `Info.plist` (the redirect literal is already isolated in `SpotifyConfig`, so this is a one-file config change plus the listener implementation). *(Keep the custom-scheme + ASWebAuthenticationSession path only if external gate #2 unexpectedly passes.)*
- Generate `code_verifier` (43–128 chars) + `code_challenge` (S256) + `state` (CSRF). Authorize URL: `GET https://accounts.spotify.com/authorize?response_type=code&client_id=…&redirect_uri=http://127.0.0.1:<port>/auth-callback&code_challenge_method=S256&code_challenge=…&scope=playlist-modify-private&state=…`. **Validate `state`** on the callback before exchanging.
- Token exchange: `POST https://accounts.spotify.com/api/token` (form: `grant_type=authorization_code`, `code`, `redirect_uri` (must match exactly, port included), `client_id`, `code_verifier`). No client secret.
- **Refresh-token rotation (critical, corrected):** Spotify PKCE refresh tokens rotate single-use — **but the refresh response does NOT always include a new `refresh_token`**. Serialize refreshes behind an in-process lock; overwrite the stored refresh token in Keychain **only when the response contains a non-empty `refresh_token`**, otherwise keep the existing one. (Overwriting with an absent/nil field permanently bricks auth.) Access tokens expire hourly.
- Loopback caveat: the redirect port must be free at auth time; pick an ephemeral port from the bound listener rather than hardcoding. During onboarding a window already exists for the browser hand-off.

### 2. `SpotifyClient` (verified current endpoints)
- `GET /v1/me` → user id + display name.
- `POST /v1/me/playlists` `{name, public:false, description}` → 201 + playlist `id` and `external_urls.spotify`.
- `POST /v1/playlists/{id}/items` `{uris:[…]}` — **batch ≤ 100 URIs/request**; append (omit `position`).
- Rate limits: honor `Retry-After` on 429; exponential backoff on 5xx; surface auth failures (401 after refresh) to a shared error state.

### 3. Keychain (`Security`)
- Store the rotating **refresh token** and the **client id**. Define stable service/account keys; accessibility `kSecAttrAccessibleAfterFirstUnlock`. Update = delete+add or `SecItemUpdate` atomically. **On client-id change, clear stored tokens** and force re-auth. Handle locked-Keychain and duplicate-item cases.

### 4. In-app dedup (`SeenStore`)
- Per-chat `Set<TrackID>` of tracks already added to that chat's playlist. During scan/backfill: collect unique track ids in order; add each once; skip any already in the set (a song sent 10× → one add). Also dedup **within** the batch. **No Spotify reads.**
- Persist the seen-set + `{chat_guid → playlist_id}` + playlist external URL in Application Support (small SQLite or `Codable`). This is what makes Home/All-set survive quit.

### 5. Wire into the UI
- **Client ID field:** trim/validate (non-empty, plausible format); store; changing it clears tokens.
- **Connect Spotify:** real PKCE login; on success `GET /v1/me`.
- **Creating:** create the private playlist (name/description from the Customize step), then add the deduped track URIs in ≤100 batches; drive `createPct/createLabel` from real batch progress.
- **All-set / Home:** real playlist name + external Spotify URL; "Open in Spotify" opens it; the playlist persists on Home across relaunches.

### M2 risks
- **Dev-mode writes blocked** (gate — prove first).
- Refresh-token rotation correctness (serialize + atomic Keychain swap).
- `ASWebAuthenticationSession` presentation context.
- Custom-scheme callback registration + `state` validation.

---

## Tech stack (unchanged from PLAN.md except scope reductions)
Swift / SwiftUI, macOS 14+. `ASWebAuthenticationSession`, `Security`/Keychain, `URLSession`. SQLite via raw `sqlite3` or GRDB (read-only). No backend, no non-Spotify network.

## Privacy (reaffirmed, now literally true)
Network egress only to `accounts.spotify.com` (OAuth) and `api.spotify.com` (playlist create/add). Message content is read, matched, and discarded. Persisted state = added track ids (the seen-set), `{chat_guid → playlist_id}`, playlist URL. No library/playlist reads, no telemetry, no account of ours.

## Milestones / done-when
- **M1 done:** a real group chat is pickable; its history scans to real `spotify:track:` ids from `text` + `attributedBody`, on this Mac.
- **M2 gate done:** a live `POST /playlists/{id}/items` from a fresh dev-mode app lands a track.
- **M2 done:** paste Client ID → browser Allow → a new private playlist is created and populated with the chat's deduped tracks; refresh rotation persists; Home shows the real, openable playlist after relaunch.

## Open questions to resolve during build
1. **Redirect-URI feasibility** (external gate #2) — does a fresh dev app accept/authorize any native redirect, and specifically must we use loopback vs custom scheme? *(Resolved-in-plan: assume loopback; confirm on live dashboard.)*
2. **Owner Premium** (external gate #1) — does the user's account have Premium? If not, M2 is blocked and onboarding must say so up front.
3. **Pins** — readable from `chat.db`? Confirmed **no** (stored in a prefs plist outside chat.db). Decide: drop the pin feature, or make pinning app-local. Leaning app-local (matches the persisted state we're adding in C2).
4. `attributedBody` byte-scan validated on a real chat.db on this machine (macOS 26.5.2)? *(First M1 task.)*
5. Pre-scan cost for the picker's per-chat link counts on very large chats (bound the work).
6. FDA deep-link anchor `x-apple.systempreferences:…?Privacy_AllFiles` is the legacy pre-Ventura anchor — validate on macOS 26; if it no-ops, fall back to opening System Settings + on-screen instructions rather than depending on the deep link.
7. Live-WAL read robustness — if intermittent `SQLITE_READONLY_RECOVERY`/`DIRTY` appears, copy `chat.db` + `-wal` + `-shm` to a temp dir and scan the copy (keep live reads for cheap picker counts).
