# Friend List — macOS App Plan

**One-liner:** Pick a group chat. Friend List scans its whole history **on your Mac**, turns every Spotify link people shared into a playlist — then keeps that playlist updated as new songs come in. Private, local, set-and-forget.

---

## Product shape

A native **SwiftUI** app you install from the web. You open it once and pick a group chat; Friend List reads that chat's entire history locally, builds a Spotify playlist from every track link it finds, and then keeps running quietly in the background so the playlist grows as the group keeps sharing music. No dock icon after setup — it lives in the menubar and just runs.

**The flow is two phases per chat:**
- **Backfill (one-time):** scan the selected chat's full history → extract every Spotify link → dedup → create a playlist → bulk-populate it. A progress screen shows it working.
- **Live (ongoing):** after backfill, keep watching that chat and add new links as they arrive.

**Three pillars:**
- **Privacy-first.** No user data ever leaves the Mac. The only network calls are to Spotify's own OAuth and Web API. No servers of ours, no analytics, no telemetry, no account, no email, no name.
- **Instant payoff, then ambient.** You get a full playlist from the chat's history immediately; after that it maintains itself.
- **Simple.** Onboarding is a few screens: pick a chat, connect Spotify, watch it import.

---

## Why this shape (the feasibility reality)

| Approach | History + live? | Verdict |
|---|---|---|
| iOS app / Share Sheet | No | One tap per song; can't see history |
| iMessage app extension | No | Can only read messages *it* sent, never plain link bubbles |
| Message Filter extension | No | Unknown-sender SMS spam only, no exfiltration |
| **macOS app reading `chat.db`** | **Yes** | **The only path to both full history and live updates** |

The iPhone gives no way to read the message archive or observe the stream. macOS does: with **Full Disk Access**, `~/Library/Messages/chat.db` (SQLite) is readable — the *entire* history a chat has synced to this Mac, plus new messages as they land. iMessage syncs across every device on your Apple ID, so a Mac left running sees what your phone sees.

**Cost of this shape:** a Mac must stay signed into Messages and be awake to add new links in real time (it catches up on wake). History backfill needs whatever the chat has synced locally.

---

## Onboarding flow

Five screens. Fast, animated, minimal. A persistent **"On device · nothing leaves your Mac"** footer with a lock glyph sits on every screen.

**1. Welcome.**
- The **Messages-bubble → Spotify** hero mark drops into view with a spring settle.
- Title: **friend list**
- Subtext: *turn a group chat's shared songs into a Spotify playlist — and keep it growing*
- Primary button: **Continue**
- **Heads-up on setup (before anything invasive):** a small line noting setup needs a **Spotify account** and a one-time **Spotify developer-app** creation (a few clicks), and that **Premium** may be required — so requirements are known *before* Full Disk Access, not after.

**2. Pick a group chat.**
- **Move to /Applications first — the very first gate (before FDA).** Detect whether the app is running *translocated* (launched straight from the DMG under Gatekeeper quarantine → a randomized, read-only path) or from outside `/Applications`; if so, present a LetsMove-style move-and-relaunch prompt. A translocated path vanishes next login, so any FDA/launcher registration bound to it would silently break.
- **Full Disk Access is requested here — and it's clearly motivated:** *"to show your chats and read their history, on this Mac only."* Explainer + `x-apple.systempreferences:` deep link, then poll for the grant. **Local-only reassurance at the grant moment:** *"Friend List reads Messages only on this Mac, to find Spotify links. Your conversations are never uploaded, stored, or sent anywhere — we don't even have a server."*
- **Survive the FDA-grant relaunch.** Granting FDA doesn't kill the app, but the process can't see the new access until it relaunches (users often take macOS's *"Quit & Reopen"*). Persist an onboarding-step marker; on relaunch with `didOnboard == false`, `NSApp.activate` and resume at this picker screen with access in hand.
- Once granted, show a **chat picker**: group chats surfaced first (display name, participant/message counts, and a quick **"N Spotify links found"** preview from a fast pre-scan); DMs below. Select one (you can add more later, each gets its own playlist).

**3. Connect Spotify.** The one setup wrinkle — presented as a short, guided, step-numbered sequence (never a wall of instructions). No server behind Friend List, so each user brings **their own** Spotify developer app: you own it, so there's no shared 5-user cap, no manual allowlist, no email collected. **Requires Spotify Premium** (Spotify's dev-mode rule) — surfaced already at the Welcome heads-up so a Free user learns it before investing effort here, not after.

  - **Step 1 — Open the dashboard & create your key.** An **"Open Spotify Dashboard"** button (opens `developer.spotify.com/dashboard`). The user logs in with their normal Spotify account, accepts the developer terms if prompted, and clicks the green **Create app** button. *(Merged with Step 2 on one screen — opening the dashboard and creating the app read as a single motion.)*
  - **Step 2 — Fill in the form.** Show the exact fields to enter as a table, with the redirect URI as a **tap-to-copy box inside the cell** (never typed — the one typo-prone field):

    | Field | What to put |
    |---|---|
    | App name | `friendList` |
    | Description | `personal use` |
    | **Redirect URI** | **`friendlist://auth-callback`**  `[ 📋 Copy ]` — must be exact |
    | Which API/SDKs? | check ✅ **Web API** |

    Check the terms box → **Save** → **"I've saved it"**.
  - **Step 3 — Paste your Client ID.** *"Open **Settings** on your new app, copy the **Client ID**, and paste it here."* **Privacy emphasis lands here** — the exact moment a careful user wonders *"wait, where does this go?"*: a reassurance line by the paste field — *"🔒 This key lives only on this Mac. Friend List has no server — your Client ID, your songs, and your messages never leave your computer. We don't collect any of this."*
  - **Step 4 — Connect.** A **"Connect Spotify"** button → Authorization Code + **PKCE** via `ASWebAuthenticationSession` (custom URL scheme `friendlist://auth-callback`, `state` for CSRF) → the user clicks **Allow** once. Silent from then on (auto-refresh; one re-Allow every ~6 months per Spotify's refresh-token expiry).
- On success, create a private playlist (default name from the group chat's title, e.g. *"🎵 <Chat Name>"*, renameable) and store the refresh token in the Keychain.

**4. Import (backfill).**
- A progress screen runs the one-time historical import: *"Scanning 4,213 messages… found 87 Spotify links… adding 74 new tracks to the playlist…"* (deduped count shown).
- **YouTube, noted but deferred:** if YouTube links are found, show a quiet line — *"Also found 22 YouTube links — YouTube playlists are coming soon."* v1 counts them; it does not build a YouTube playlist (see non-goals / v2).
- Handles a large chat gracefully: batched Spotify calls, rate-limit aware, resumable if interrupted.

**5. Done.**
- "Your playlist is ready — <N> songs from <Chat Name>. It'll keep growing as the group shares more."
- Registers Friend List's bundled **LaunchAgent** via **`SMAppService.agent`** (`Program` = the app's own executable, `RunAtLoad` + `KeepAlive = {SuccessfulExit = false}`), which starts the headless/menubar live-scanning process, then hands off (single-instance contract) and verifies `SMAppService.status` (see Components 1).

**Branding:** app icon and mark are a fusion of the **Messages speech-bubble** and the **Spotify** mark — a bubble whose interior reads as Spotify's rings ("messages → music"). Playlist cover uses the same mark.

---

## Architecture

```
FriendList.app (SwiftUI, Developer ID signed + notarized)
  SINGLE executable — menubar-only (LSUIElement); no Dock icon
  ├─ EVERY launch → single-instance guard (C1): another instance already
  │      running (by bundle id, NSRunningApplication)? → activate it and exit
  ├─ First launch → onboarding (Welcome → Pick chat → Spotify → Import → Done)
  │      ├─ BACKFILL: scan selected chat's FULL history → links → dedup →
  │      │            create playlist → bulk-add (progress UI)
  │      └─ registers a bundled LaunchAgent via SMAppService.agent
  │         (Program = THIS same executable → one code identity;
  │          RunAtLoad → launch at login;
  │          KeepAlive = {SuccessfulExit = false} → restart on crash only)
  │      └─ register() spawns the launchd instance → onboarding instance
  │         calls NSApp.terminate → launchd-started instance is sole owner
  ├─ launchd starts this same bundle headless/menubar (still one cdhash)
  ├─ MenuBarExtra: status, pause/resume, "open playlist", add another chat,
  │      Quit → SMAppService.unregister() (bootout), ATTENTION state on breakage
  └─ In-app LIVE scanning loop (background Task, started at launch, headless)
        └─ poll chat.db every ~10s  (read-only, FRESH connection per poll, live WAL)
             └─ extract text (text column OR attributedBody blob)
                  └─ filter to TRACKED chats → route each to its playlist
                       └─ regex Spotify track links → track IDs
                            └─ dedup (per-playlist seen-set + Liked Songs, ISRC-aware)
                                 └─ Spotify Web API: add to that chat's playlist
             └─ advance last_seen ROWID past every terminally-resolved message
                (only a not-yet-enqueued failed add holds it → durable retry queue)
             └─ on unrecoverable failure → shared error state → menubar "Attention"
```

**Read-only** on `chat.db`. Onboarding UI, backfill, and the live loop are the **same executable** (one code identity / cdhash): the bundled LaunchAgent's `Program` is the app's own binary, so launchd starts the very same signed bundle. The Full Disk Access grant to FriendList.app therefore covers the launchd-started scanner (one identity, one grant), and everything shares in-process state directly (no IPC, no Keychain access-group sharing).

**Single-instance contract.** Exactly one live process at any time. `register()` (with `RunAtLoad`) starts a second, launchd-owned instance at the Done screen while the LaunchServices-started onboarding instance is still alive, and later Finder-opens would start more — so every launch first checks for another running instance by bundle id (`NSRunningApplication`); if one exists it activates that instance and exits immediately (*activate-existing-and-exit*). The onboarding instance calls `NSApp.terminate` right after `register()` so the launchd-started instance becomes sole owner. A duplicate that still slips through loses the advisory `flock` on the state file and exits 0 (clean). This preserves the single-process invariants the token-refresh serialization and single-writer state rely on.

**Lifecycle (login / crash / quit).** `RunAtLoad` starts the app at login; `KeepAlive = {SuccessfulExit = false}` restarts it only after a crash/abnormal exit, never after a clean `exit 0`. A plain process exit is treated as a crash and respawned, while the menubar **Quit** routes through `SMAppService.unregister()` (bootout) — a user quit actually stops the app and suspends auto-relaunch until re-enabled. Pause/resume is a separate in-process flag.

---

## Components

### 1. App shell, menubar & onboarding (`FriendListApp`, SwiftUI)
- A **menubar-only** app: `LSUIElement = true` (no Dock icon), presence via `MenuBarExtra`. An onboarding `WindowGroup` shows until setup completes (persisted `didOnboard`), plus a finer-grained **onboarding-step marker** so a mid-onboarding relaunch resumes at the right screen.
- **Survive the FDA-grant relaunch (M8).** On launch, if `didOnboard` is false, `NSApp.activate(ignoringOtherApps:)` and re-present onboarding from the persisted step marker (the pick-chat screen, now with access granted).
- **App-translocation / not-in-`/Applications` guard — the first gate (M3).** Before requesting FDA or registering the launcher, detect translocation/quarantine (`SecTranslocateIsTranslocatedURL`) or a non-`/Applications` path and run a LetsMove-style move-and-relaunch.
- Owns the Full Disk Access request UX (probe-read `chat.db`; on failure show explainer + deep link, poll for access).
- Registers a bundled **LaunchAgent** via **`SMAppService.agent`** (macOS 13+) whose `Program` is the app's **own executable** — same signed bundle, one code identity, covered by the FDA grant — with `RunAtLoad` + `KeepAlive = {SuccessfulExit = false}`. No separate helper binary.
- **Single-instance guard (C1):** (a) every launch, check for another running instance by bundle id and *activate-existing-and-exit*; (b) the onboarding instance calls `NSApp.terminate` right after `register()`; (c) a duplicate that slips through loses the advisory `flock` and exits 0.
- **Quit means quit; login/crash restart (MF1):** menubar **Quit** routes through **`SMAppService.unregister()`** (bootout) so a clean quit actually stops it (else `KeepAlive` respawns ~10s later); a plain exit is treated as a crash and respawned; `RunAtLoad` starts it at login. Pause/resume is an in-process flag, never an unregister.
- **Confirm registration is enabled (M4):** after registering, check `SMAppService.status`; a `.requiresApproval`/disabled state raises an **"Enable Friend List in Login Items"** attention item on the menubar machinery, deep-linking to the Login Items pane.
- **Attention/error state (M6):** the `MenuBarExtra` reflects a shared `@Observable` health state (auth revoked, FDA lost, playlist deleted). When unhealthy it swaps its icon and surfaces **"Attention needed — Reconnect Spotify"** (or FDA/playlist equivalent), reopening the relevant step. Scanning runs in-process, so the loop writes this state and the UI reads it directly.
- **"Add another chat"** menu action re-opens the picker → runs a backfill for the new chat (Component 2b) → adds it to the tracked set.

### 2a. Backfill importer (`BackfillImporter`)
- One-time historical import for a newly-selected chat. Query **all** of that chat's messages (`WHERE chat_guid = :guid`, no `last_seen` bound), extract Spotify links from `text`/`attributedBody`, dedup (Component 6), and bulk-populate the playlist.
- **Scale + rate limits:** a chat may hold hundreds of links. Batch Spotify calls — track-info/ISRC fetches via `GET /v1/tracks?ids=` (up to 50 ids), adds via `POST /v1/playlists/{id}/tracks` (up to 100 uris) — and respect the 30s rolling rate limit (honor `Retry-After`). Drive the Import progress UI (messages scanned / links found / tracks added / duplicates skipped / YouTube links counted).
- **Resumable:** persist backfill progress (a cursor + the per-playlist seen-set); if interrupted (quit, crash, network), resume without re-adding. On completion mark the chat `backfilled = true`.
- Failed adds go to the same **durable retry queue** as the live loop.

### 2b. In-app live scanning (`Scanner`)
- After backfill, the poll → filter → route → parse → dedup → add loop runs **inside the app process** on a background `Task`/serial queue, started at launch. That process is the one launchd starts from the bundled LaunchAgent (Component 1) — same executable, one code identity, FDA already covers it; `KeepAlive = {SuccessfulExit = false}` gives crash-restart without a second binary.
- Scans forward (`ROWID > last_seen`), filters to **tracked chats**, and **routes** each message to its chat's playlist.
- No UI of its own; drives the shared health state.
- **Single-writer** is inherent to one process (single-instance contract, Component 1); the advisory `flock` is the last-resort backstop.

### 3. chat.db reader (`MessagesReader`)
- Open `chat.db` **read-only** on a **fresh connection per poll/scan** (`sqlite3_open_v2(..., SQLITE_OPEN_READONLY, nil)` or GRDB `Configuration.readonly = true`). `chat.db` is a live WAL database Messages is actively writing; a long-lived handle caches pages and hides newly-arrived rows. Same-user + FDA lets the reader participate in the WAL protocol and see committed `-wal` rows. (Do **not** use any immutable flag — it hides new rows.)
- Live query (forward): `WHERE m.ROWID > :last_seen`. Backfill query (historical, per chat): `WHERE cmj.chat_id = :chat_id` with no ROWID lower bound.
  ```sql
  SELECT m.ROWID, m.text, m.attributedBody, m.is_from_me,
         h.id AS handle,                 -- sender (correct in group chats too)
         c.guid AS chat_guid,            -- stable conversation identity
         c.display_name AS chat_name,    -- mutable; convenience/display only
         c.style AS chat_style           -- 45 = 1:1 DM, 43 = group
  FROM message m
  LEFT JOIN handle h ON m.handle_id = h.ROWID
  LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
  LEFT JOIN chat c ON c.ROWID = cmj.chat_id
  WHERE <forward or backfill predicate>
  ORDER BY m.ROWID ASC
  ```
- **De-dup rows:** `chat_message_join` can emit a message under more than one chat; `GROUP BY m.ROWID` (or pick the chat deterministically) so a message isn't parsed twice.
- **Group vs DM + attribution:** each message maps to a `chat` via `chat_message_join`; `chat.style` distinguishes group (43) from 1:1 (45). `handle.id` is the *sender*; `chat_guid` is the *conversation* — both feed the picker and routing.
- **attributedBody quirk:** modern macOS stores link-message text in the `attributedBody` blob (`NSAttributedString`/`streamtyped`/`typedstream`), leaving `text = NULL`. Decode to recover the URL (`NSAttributedString(data:documentAttributes:)` for streamtyped, or a typedstream parser, with a `https://…` byte-scan fallback; `NSUnarchiver` is unavailable in Swift). The one non-trivial bit — validate on real `chat.db` at M1.

### 4. Link parser (`LinkParser`)
- **Spotify (v1 target):** `https?://open\.spotify\.com/(?:intl-[a-z]{2}/)?track/([A-Za-z0-9]+)` (allow the optional `/intl-xx/` locale segment; strip `?si=` share tokens); also accept `spotify:track:ID`. Output canonical `spotify:track:{id}`. Tracks only (albums/playlists/artists deferred).
- **YouTube (detected, deferred):** also match `youtube.com/watch?v=`, `youtu.be/`, `music.youtube.com` links and **count** them (surfaced in Import + a menubar tally), but v1 does **not** turn them into a playlist. Structured so a v2 YouTube backend can consume the same captured links.

### 5. Spotify client (`SpotifyClient`)
- **Auth:** Authorization Code + **PKCE** via `ASWebAuthenticationSession`. **Redirect = custom URL scheme** (`friendlist://auth-callback`) in `Info.plist` (`CFBundleURLTypes`) — no loopback server; the session captures the callback natively. (`ASWebAuthenticationSession(callbackURLScheme:)` takes the bare scheme `friendlist`.) Generate and verify a `state` param for CSRF. From the headless/menubar process, materialize a window + `presentationContextProvider` before presenting.
- **Bring-your-own client_id.** No embedded client_id, no server. Each user creates their own Spotify dev app and pastes its **client_id** (and confirms redirect URI). Each owns their own dev-mode app → no shared user cap, no allowlist, no email. Requires Spotify **Premium**.
- **Refresh-token rotation (critical).** Spotify PKCE refresh tokens are **single-use and rotate on every refresh**. The client must (a) **serialize** refreshes behind an in-process lock (trivial under the single-process design), and (b) on every refresh, **atomically overwrite** the stored refresh_token in the Keychain with the new one (write-then-swap). Access tokens expire hourly.
- **Auth failure → error state (M6):** a failed/invalid refresh surfaces an auth-error into the shared health state → menubar "Reconnect Spotify".
- **Keychain:** refresh token in the macOS Keychain (`Security`). Single process → no shared access group.
- **Playlists (per chat):** on adding a chat, `POST /v1/users/{me}/playlists` → private playlist named from the chat; persist `{chat_guid → playlist_id}`. `GET /v1/me` for user id. If a tracked playlist 404s (user deleted it), surface an attention action to recreate + re-persist.
- **Add:** `POST /v1/playlists/{id}/tracks` `{"uris":[…]}` (batch up to 100).
- **Scopes:** `playlist-modify-private user-library-read playlist-read-private` (drop `playlist-modify-public` — playlists are private). `playlist-read-private` is needed to read owned private playlists for dedup.

### 6. Dedup engine (`Deduper`) — see **Dedup strategy** below.

### 7. State store (`StateStore`)
- Application Support container (small SQLite or `Codable`). Holds:
  - **Tracked chats:** for each, `{ chat_guid, display_name, playlist_id, backfilled: Bool, seen-set (track IDs + ISRCs), retry queue }`. Per-playlist seen-set so dedup is scoped to that playlist.
  - **Global `last_seen` ROWID** for the forward live scan across all tracked chats.
  - The **durable retry queue** entries carry the track URI, target playlist, attempt count. (Whether to also store source chat/sender is a privacy choice — see Privacy.)
- **Single writer** by construction (one process; `flock` backstop).
- **Watermark seeding:** `last_seen` is set to `MAX(ROWID)` at the moment live tracking begins (first chat added). History is captured by **backfill**, not by rewinding the live watermark — so the live loop never re-scans the whole archive, while backfill intentionally imports each tracked chat's past. A chat added later is backfilled for its history and picked up going forward by the live scan (overlap is deduped).

### 8. Settings (in-app)
- GUI over the same values: Spotify **client_id** (re-editable — changing it clears stored tokens + drives re-auth), per-chat playlist names (rename → `PUT /v1/playlists/{id}`), pause/resume, **manage tracked chats** (add/remove, re-open picker), dedup toggles, optional sender filter, and an optional *"skip my own messages"* toggle. No user-edited config file as the primary interface.

---

## Tracked chats & scope

Friend List is **explicitly scoped** to the chats you pick — there is no "all chats" firehose. Each tracked chat maps to its own playlist (`{chat_guid → playlist_id}`), and the live scanner routes each incoming link to the right playlist.

- **Selection** is by `chat.guid` (stable across renames); `display_name` is shown in the picker for humans.
- **By default every sender in a tracked chat counts** (it's "all the songs shared in this chat," including your own). An optional *"skip my own messages"* toggle sets `is_from_me = 1` exclusion. An **advanced sender allow-list** (`allowed_handles`) can further restrict to specific people.
- **Handle normalization** (only if the advanced sender filter is used): canonicalize phone numbers → E.164 (`NSDataDetector`/`PhoneNumberKit`, locale region) and emails → lowercased/trimmed, matching config entries the same way. Chat-GUID matching needs no normalization.

---

## Dedup strategy (`Deduper`)

Goal: never add a song already present. Applies to **both** backfill and live adds; the per-playlist seen-set is the first cheap gate, the API checks are the authoritative backstop.

**Sources checked:**
1. **Target playlist** — `GET /v1/playlists/{id}/tracks` (paginated, 100/page) into a track set at startup/backfill; refreshed periodically; in-memory adds update it.
2. **Liked Songs** — `GET /v1/me/tracks/contains?ids={ids}` (batched). Requires `user-library-read`. **Note:** `contains` keys on **track ID only**, so Liked-Songs dedup is ID-level; full ISRC-level Liked-Songs matching would require a full-library scan and is an opt-in extra, not default.

**Matching key — ISRC-aware (playlist side):** Spotify gives different track IDs to the same recording (album vs single, remaster, clean vs explicit, regional). Dedup keys on **ISRC** (`track.external_ids.isrc`) as well as track ID:
- Cache keyed by both; for a new track fetch its ISRC (batched `GET /v1/tracks?ids=`) and skip if either the ID or ISRC already exists; fall back to track-ID-only when ISRC is missing.
- Also dedup **within** a backfill batch (the same link pasted 10 times → one add).

**Playlist-heavy users (opt-in):** also scan owned playlists (`GET /v1/me/playlists`, filtered to `owner.id == me`) into the cache. Heavier; off by default.

---

## Tech stack
- **Swift 5.9+ / SwiftUI**, macOS 13+ (`SMAppService`, `MenuBarExtra`, `LSUIElement`).
- **`ASWebAuthenticationSession`** (OAuth), **`Security`/Keychain** (tokens), **`SMAppService.agent`** (bundled LaunchAgent whose `Program` is the app's own executable — `RunAtLoad` + `KeepAlive = {SuccessfulExit = false}`; menubar **Quit** calls `SMAppService.unregister()`), **`AppKit`** (`NSRunningApplication` single-instance check + `NSApp.terminate` handoff, `SecTranslocate`), **`URLSession`** (Spotify Web API).
- SQLite for `chat.db`: raw `sqlite3` C API via a thin wrapper, or **GRDB.swift** (read-only config).
- Optional: **PhoneNumberKit** (only if the advanced sender filter ships in v1).
- No backend, no third-party network services. Xcode project; a **single app target** (one executable; the bundled `SMAppService.agent` LaunchAgent relaunches that same executable), no separate agent binary.

---

## Milestones

**M1 — Read the stream (prove the hard part).** Swift opens `chat.db` read-only and extracts link text from **both** `text` and `attributedBody`, for a specific chat's full history *and* a live forward read.
- ✅ Done when: a Spotify link in a chosen chat's history is parsed to a track ID, and a freshly-texted link is caught on a live read, on this machine.

**M2 — Spotify path (gate the risk first).** **First, verify writes are even possible:** from a *fresh Development-Mode* Spotify app, run a live `POST /v1/playlists/{id}/tracks` and confirm the track lands — this de-risks reports that Spotify's 2025-26 dev-mode tightening may block dev-mode playlist *writes* (if true it kills the core promise). Then: paste **your own client_id**, `ASWebAuthenticationSession` PKCE login (with `state`), token in Keychain, create a playlist, add a track; verify **refresh-token rotation** (new single-use token atomically written back).
- ✅ Done when: a live write from a fresh dev-mode app succeeds; auth yields a token and a known song lands in a new playlist; a forced refresh persists the rotated token and the next refresh still works.

**M3 — Backfill import.** Given a selected chat, scan its full history, dedup, create a playlist, and bulk-populate it with progress; batched + rate-limit aware; resumable.
- ✅ Done when: picking a real group chat produces a playlist containing its shared tracks with duplicates/re-releases skipped; a chat with hundreds of links imports without hitting rate-limit errors; interrupting and relaunching resumes without double-adding; YouTube links are counted and reported (not added).

**M4 — Onboarding UI.** The five animated screens (welcome → pick chat + FDA + translocation guard → Spotify setup/connect → import progress → done).
- ✅ Done when: a first-run user goes welcome → pick chat → create dev app + paste client_id → auth → watch the import → done; the picker lists real conversations with link-count previews.

**M5 — Live updates + lifecycle.** Register the bundled **LaunchAgent** via `SMAppService.agent`; launchd starts the same signed bundle headless to run the in-process forward loop (filter to tracked chats, route to playlists, dedup, retry, watermark). Enforce the **single-instance contract**, route **Quit** through `SMAppService.unregister()`, verify `SMAppService.status`, and validate the FDA grant covers the launchd-started process.
- ✅ Done when: a new link in a tracked chat lands within ~10s in that chat's playlist; already-present/ISRC-dupe/repeat links are no-ops; a failed add is retried (not lost); a revoked token flips the menubar to "Attention needed"; a crash is auto-restarted by `KeepAlive` without waiting for login; a **clean menubar Quit stays quit** while login-start and crash-restart still work; only **one** instance ever runs.

**M6 — Ship it.** Developer ID sign + notarize + staple (incl. Hardened Runtime + secure timestamp; the bundled LaunchAgent plist inside the signed bundle); package `.dmg`; verify the move-to-`/Applications` + FDA flow on a clean machine; web download page.
- ✅ Done when: downloaded on a clean Mac, it clears Gatekeeper, moves to /Applications, onboards, imports a chat, and keeps the playlist updated unattended after a reboot.

---

## Privacy (explicit)
- **No off-device data.** Network egress is only `accounts.spotify.com` (OAuth) and `api.spotify.com` (playlist/dedup). Nothing else.
- **No account/telemetry/analytics/allowlist.** We never ask for or store name, email, or contacts off the Mac. Each user owns their own Spotify dev app, so there's nothing to register users into.
- **Local only, minimal persistence.** Tokens in Keychain; message content is read, matched, and discarded. Persisted state is Spotify track IDs/ISRCs (the seen-set), the `{chat_guid → playlist_id}` map, and the retry queue. **Retry entries store only the track URI + target playlist + attempt count — not message text or sender** (a re-POST needs nothing more), keeping the "nothing about your conversations is stored" claim literally true.
- **Read-only** on `chat.db`; never writes to Messages.

---

## Distribution
- **Developer ID** signing + **notarization** + stapling → passes Gatekeeper.
- Delivered as a `.dmg` (drag to /Applications) from a simple web page.
- **Move-to-`/Applications` guard (translocation):** before any FDA/LaunchAgent registration, a LetsMove-style prompt moves the app out of the quarantined DMG path and relaunches, so registrations don't bind to a path that vanishes next login.
- **Full Disk Access** is the one manual grant; onboarding guides it and detects when granted.
- Auto-update via **Sparkle** — v2 (must re-register the `SMAppService.agent` after an in-place update so launchd runs the new binary; keep the Developer ID designated requirement stable so the FDA/TCC grant survives version bumps).

---

## Explicit non-goals (MVP)
- **YouTube playlists** — YouTube links are detected and counted, but building a YouTube playlist (Google OAuth + YouTube Data API) is deferred to v2.
- No iOS app, Share Sheet, or iMessage extension.
- No Windows/Linux — macOS only.
- No albums/playlists/artist links — tracks only.
- No cloud, multi-user, accounts, or any server of ours.
- Never writes to `chat.db`.

---

## Risks / open questions
- **Spotify may restrict Development-Mode writes (unverified, 2025-26).** Every user runs their own dev-mode app; if dev-mode `POST …/tracks` is blocked, the core promise dies. **Gated first** at M2 via a live write from a fresh dev-mode app.
- **Full Disk Access covers scanning — one code identity.** Single executable (one cdhash) onboards, backfills, *and* scans; the bundled `SMAppService.agent` LaunchAgent relaunches that same signed bundle, so the FDA grant covers the launchd-started scanner. Validate on a clean machine at M5.
- **attributedBody decoding** across macOS versions — main technical risk; validate on real `chat.db` at M1.
- **Backfill volume / rate limits** — a large chat means many Spotify calls; batch and honor `Retry-After` (M3). History depth is limited to whatever the chat has synced to this Mac.
- **BYO client_id + Premium** — real onboarding friction and an adoption constraint (the dev-app owner account must be the same Premium account used to authenticate).
- **Multi-Mac on one Apple ID** — two Macs tracking the same chat with independent seen-sets could double-add (the add API doesn't dedup); mitigate with a pre-add `contains`/snapshot re-check, or document single-Mac as the expectation.
- **WAL read-only** — same-user + FDA reads live rows; verify at M1 that fresh read-only connections see just-arrived messages.
- **Mac uptime / sleep** — live adds are deferred until wake; catches up via ROWID.

---

## v2 ideas (later)
- **YouTube playlists** — turn the already-captured YouTube links into a real playlist via the YouTube Data API (Google OAuth), as a second provider.
- Sparkle auto-update.
- Multiple chats → one combined playlist option (vs the default per-chat).
- Album/artist support; auto monthly playlist.
- Reaction-gated adds (only add if you 👍 the message).
- Block-lists / advanced per-chat sender rules.
- "Recently added" list with one-tap undo in the menubar.
