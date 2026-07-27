# Adversarial review — FriendList M1 data layer

Reviewer stance: skeptical, trying to *break* the code. Every claim below was
checked against the actual source and known macOS/SQLite behavior. Where I
couldn't find a real defect I say so rather than manufacture a nit.

Ranked most-severe first.

---

## 1. MAJOR — `persistPlaylists` corrupts every older playlist's `chatGUID` and wipes its `spotifyID`

**File:** `Sources/Onboarding/OnboardingState.swift:300-307` (with the model gap at
`Sources/Onboarding/OnboardingState.swift:15-21` vs `Sources/Backend/Persistence.swift:5-12`)

```swift
private func persistPlaylists(newSpotifyID: String) {
    let saved = lists.map { l in
        SavedPlaylist(spotifyID: l.name == (name.isEmpty ? selectedChatName : name) ? newSpotifyID : "",
                      name: l.name, songCount: l.songCount, chatName: l.chatName,
                      chatGUID: pickedChat?.guid ?? "", externalURL: l.externalURL)
    }
    Persistence.savePlaylists(saved)
}
```

The in-memory `Playlist` model has **no `spotifyID` and no `chatGUID`** fields —
`loadPlaylists()` drops both at init (`OnboardingState.swift:89-91`). So when a new
playlist is created, `persistPlaylists` rebuilds `SavedPlaylist` for *all* rows
from data it no longer has:

- `chatGUID: pickedChat?.guid ?? ""` is assigned to **every** row — including
  older playlists that came from a *different* chat. They get relabeled with the
  most-recently-picked chat's GUID.
- `spotifyID` is set only on the row whose `name` matches the current playlist
  name; **every other row gets `""`**, permanently losing its real Spotify id.
- The `spotifyID` match is by **name string**, so two playlists sharing a name
  (default name == chat name) collide.

**Failure scenario (inputs → wrong result):**
1. Create "Beach Trip" from chat A (guid `A`). Persisted `{name:"Beach Trip", chatGUID:A, spotifyID:id1}`.
2. `createAnother()` → pick chat B (guid `B`), create "Ski Squad".
3. `persistPlaylists` writes: `Beach Trip → {chatGUID:B, spotifyID:""}`, `Ski Squad → {chatGUID:B, spotifyID:id2}`.
   Beach Trip is now attributed to the wrong chat and has lost its Spotify id.

Any M2 feature that keys off `SavedPlaylist.chatGUID`/`spotifyID` (refresh,
per-chat dedup, "update playlist") will act on corrupt associations. The
`recordSeen` dedup map (`OnboardingState.swift:293-295`) is keyed correctly and is
unaffected, which masks the bug during onboarding but not afterward.

**Fix direction:** give `Playlist` durable `spotifyID`/`chatGUID` fields (or persist
from a source that still has them) and map each row from its *own* identity, not
the currently-picked chat.

---

## 2. MAJOR — `resumeAtPicker` and `didOnboard` are write-only dead state; FDA relaunch-resume is not implemented

**Files:** `Sources/Onboarding/OnboardingState.swift:133, 146, 296`;
`Sources/Backend/Persistence.swift:22-32`; `App/FriendListApp.swift:3-15`;
`Sources/Onboarding/OnboardingContainer.swift:8`

`Persistence.resumeAtPicker` is set `true` in `requestAccess()` and `false` in the
poll success path — but a full-tree grep shows **it is never read anywhere**.
Same for `Persistence.didOnboard` (set `true` at `OnboardingState.swift:296`, never
read). `OnboardingState.step` initializes to `1` and `OnboardingContainer`
constructs a fresh `OnboardingState()` with no launch-time consultation of either
marker.

**Failure scenarios:**
- The entire reason `resumeAtPicker` exists — `FullDiskAccess.swift:6-8` documents
  that macOS *may require a relaunch* to gain FDA, so the app "persist[s] a resume
  marker … and re-probe[s] on launch." That re-probe/resume **does not exist**. A
  user who grants FDA and is forced to relaunch reopens at Welcome (step 1), not
  the picker; the promised resume is a no-op.
- `didOnboard` is never consulted, so a returning user who already finished
  onboarding is dropped back at Welcome and re-runs the whole flow instead of
  landing on Home.

Severity major (broken documented behavior + returning-user regression), though
arguably outside strict M1 scan scope.

---

## 3. MINOR — `canRead()` conflates "readable" with "chat table non-empty"; false negative locks the picker

**File:** `Sources/Backend/MessagesReader.swift:58-67`

```swift
func canRead() -> Bool {
    do {
        let db = try SQLiteReadOnly(path: dbPath)
        var ok = false
        try db.query("SELECT 1 FROM chat LIMIT 1") { _ in ok = true }
        return ok
    } catch { return false }
}
```

`ok` is only set inside the row callback. If `chat.db` is fully readable (FDA
granted) but the `chat` table has **zero rows** (fresh Mac where Messages was
opened but never used), the query returns `SQLITE_DONE` with no rows, `ok` stays
`false`, and `canRead()` returns `false`.

**Failure scenario:** user grants FDA, but `startAccessPolling`
(`OnboardingState.swift:141-150`) keeps seeing `canRead() == false` for all 160
iterations and never sets `access = true` / calls `reloadChats()`. The permission
card stays up forever despite access being granted.

The deny case is handled correctly (SQLite opens lazily; the read fails at
`step` with `CANTOPEN`/`IOERR` → `catch` → `false`), so the probe is reliable
*except* for the empty-table edge. Fix: return `true` on query success regardless
of rows (e.g. `SELECT 1` with no `FROM`, or `PRAGMA schema_version`, or set a flag
in a `defer` after `query` returns without throwing).

---

## 4. MINOR — `accessPollTask` is never cancelled when the picker disappears

**Files:** `Sources/Onboarding/OnboardingState.swift:138-152`;
`Sources/Onboarding/Screens/PickChatView.swift` (no `.onDisappear`)

`startAccessPolling` cancels any *previous* task at entry, but nothing cancels the
task when `PickChatView` goes away. `OnboardingState` outlives the view (owned by
`OnboardingContainer` for the whole flow), and `[weak self]` doesn't stop the loop —
`self?` is still alive. If the user opened Settings, then navigated back
(Back/swipe) without granting, the task keeps waking every 1.5s for up to ~4
minutes, opening a fresh SQLite connection each time. Not expensive, but it's an
uncancelled background loop touching `chat.db` after the UI that requested it is
gone. Minor. (The `[weak self]` + `Task.isCancelled` scaffolding suggests
cancellation was intended but no caller invokes it.)

---

## 5. MINOR — Spotify locale regex only allows 2-letter `intl-` prefixes

**File:** `Sources/Backend/LinkParser.swift:29`

```
open\.spotify\.com/(?:intl-[a-z]{2}/)?track/([A-Za-z0-9]{22})
```

The optional locale group is fixed at exactly two letters + `/`. Today's Spotify
share URLs use 2-letter language codes (`intl-de`, `intl-es`, `intl-pt`), so this
is currently fine. But if a URL carries any non-2-letter segment between
`open.spotify.com/` and `track/`, the optional group fails to match, `track/` is no
longer adjacent, and **the whole URL is missed** (not just the locale stripped).
Low likelihood given current Spotify behavior; flagged as a brittleness risk, not
a live defect.

---

## 6. MINOR — `completeCreation` dedup can silently drop a real second playlist

**File:** `Sources/Onboarding/OnboardingState.swift:288`

Append guard is `!lists.contains { $0.name == pl.name && $0.chatName == pl.chatName }`.
Default `name == selectedChatName` and `chatName == selectedChatName`. If a user
creates two playlists from the *same* chat without renaming, the second has an
identical `(name, chatName)` key, is not appended to Home, and (because
`persistPlaylists` maps `lists`) is not persisted either — even though it was
already created on Spotify. It just vanishes from the app. Edge case; minor.

---

## Areas attacked but NOT buggy (verified, stated honestly)

- **SQLite NULL ordering (`ORDER BY last_date DESC`)** — `MessagesReader.swift:83-89`.
  `last_date` is `MAX(m.date)`, NULL for a chat with no messages. SQLite treats
  NULL as smaller than all values, so under `DESC` NULLs sort **last** — empty
  chats fall to the bottom of the picker, which is the desired behavior. Reading a
  NULL column via `sqlite3_column_int64` yields `0` (`lastDate = 0`), unused for
  ordering. **Not a bug.**

- **`recentLinkCounts` window with < 40 000 messages** — `MessagesReader.swift:210`.
  `m.ROWID > (SELECT MAX(ROWID) FROM message) - 40000`. With e.g. 5 000 messages
  the RHS is `-35000` and `ROWID > -35000` matches **every** row. The negative
  threshold doesn't break anything — it simply scans the whole (small) table,
  exactly what you'd want. **Not a bug.** (Caveat, not a defect: if rows were
  deleted, `MAX(ROWID)` overstates the count and the window covers fewer than
  40 000 real messages — an approximation the code already labels "approximate.")

- **`GROUP BY m.ROWID` in `scan`** — `MessagesReader.swift:139-146`. The query is
  already filtered to a single `cmj.chat_id = ?`, so multi-chat fan-out isn't the
  risk here; the `GROUP BY` is defensive against duplicate `chat_message_join`
  rows for the same `(chat_id, message_id)`. Bare non-aggregated columns all come
  from the same message row, so values are identical within a group. **Not a bug.**

- **SQL injection** — every input is bound (`chatGUID` via `.text`,
  rowids/window via `.int`, `SQLiteReadOnly.query` uses `sqlite3_bind_*`). No
  string interpolation into SQL anywhere. `.text` uses the TRANSIENT destructor so
  SQLite copies the bytes. **Clean.**

- **Blob byte-scan losing an ASCII URL** — `LinkParser.swift:58-60`,
  `MessagesReader.swift:179-185`. The comment's claim holds: ASCII bytes
  (0x00–0x7F) can **never** be consumed as part of a UTF-8 multibyte sequence,
  because continuation bytes must be 0x80–0xBF. So `String(decoding:as:UTF8.self)`
  replaces only the surrounding invalid bytes with U+FFFD and leaves any all-ASCII
  `https://open.spotify.com/track/…` / `spotify:track:…` run fully intact. In
  `streamtyped` `attributedBody` and `bplist00` `payload_data`, an all-ASCII URL is
  stored as a contiguous ASCII run (bplist ASCII string type 0x5; typedstream
  stores the raw string bytes), so the byte-scan finds it. A URL never spans two
  source columns because each column is concatenated whole with `\n`. **Not a bug.**
  (Residual, not demonstrated: only fails if a URL were stored non-contiguously or
  as UTF-16 — which ASCII URLs are not.)

- **22-char Spotify id length** — `LinkParser.swift:29,32`. Spotify track ids are
  always 22 base62 chars (base62 of a 16-byte value). The capture is correctly
  anchored by `track/` / `spotify:track:`, and grabs exactly the first 22 chars.
  **Not a bug.**

- **`MessagesReader` thread safety** — it's a value struct (`let dbPath`, `let
  parser`) copied into the worker closure; `LinkParser`'s regexes are `static let`
  `NSRegularExpression`, which Apple documents as thread-safe for matching. The
  `db.query` callback runs **synchronously** in the `while sqlite3_step` loop on
  the single `DispatchQueue.global` thread, so mutations of `ordered`/`seen`/
  `youtube`/`scanned` (`MessagesReader.swift:148-169`) are serial — **no data
  race.** The `progress` closure only forwards a local value struct to
  `DispatchQueue.main.async`. **Not a bug.**

- **`performScan` continuation** — `OnboardingState.swift:179-195`. Both paths
  resume exactly once (success `cont.resume` in `do`, error `cont.resume` in
  `catch`); `reader.scan` is `throws` and fully wrapped, so there's no path that
  neither returns nor throws. **No double-resume, no leak.**
