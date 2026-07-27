# Friend List — R2 Review Consolidated

Counts: **Critical 1 · Must-fix 7 · Medium 12 · Low 6 · Impl-notes 11**
Reviewers: agent1 (macOS/Swift), agent2 (Spotify OAuth/distribution), agent3 (Product/Privacy/UX).
All three confirm R1 fixes C1 (single executable), C2 (BYO client_id), M2 (rotating refresh), M6 (attention state) genuinely resolved. Most new issues are side-effects of the C1 menubar-only collapse and C2 BYO model.

## Critical
- **[C1] FDA grant kills the app mid-onboarding; menubar-only relaunch has no step-resume and may not re-present the onboarding window** — §Onboarding 2 "Scope" + Components §1 — persist an onboarding-step marker, resume post-grant at the scope/picker screen, and `NSApp.activate` + present the onboarding window on relaunch when `!didOnboard` — **NEW** (from C1 menubar-only collapse). *(agent3)*

## Must-fix
- **[M1] No crash/exit recovery — `SMAppService.mainApp` launches at login only; lost LaunchAgent `KeepAlive`, so a crash kills scanning until next login** — §Architecture, Components §1–2, M4 — add a minimal `SMAppService.agent` watchdog plist (same bundled exe, no FDA) with `KeepAlive`, OR explicitly document login-only recovery; add crash-restart to M4 acceptance — **NEW** (from C1 collapse). *(agent1 + agent2 — strong overlap)*
- **[M2] BYO onboarding omits the Spotify "User Management" self-add step → dev-mode auth fails ("user not registered in the Developer Dashboard")** — §Onboarding 3, Components §5 — add sub-step "add your own Spotify account under User Management" with exact dashboard path; add a non-owner-preauthorized account to M2/M3 acceptance — **NEW** (from C2 BYO). *(agent1 Must-fix; agent2 Low + agent3 impl-note flag "verify" — overlap, severity disputed)*
- **[M3] App translocation (first run from DMG/quarantine) invalidates the path/cdhash-keyed FDA grant AND the recorded login-item path** — §Onboarding 2–4, §Distribution — detect not-in-/Applications or translocated state and require move to /Applications *before* requesting FDA or registering the login item — **NEW** (surfaced by C1 path-keyed TCC). *(agent2)*
- **[M4] Login-item registration may be declined / require approval; the "never open again" ambient promise then breaks silently** — §Onboarding 4, Components §1/4 — detect `SMAppService.status != .enabled` and surface an "enable Friend List in Login Items" attention item — carried-over (elevated). *(agent3 Must-fix + agent1 Low — overlap)*
- **[M5] Denied / never-granted FDA still has no failure state** — Components §1, §Onboarding 2 — define an explicit "not granted — try again / can't continue" state plus a graceful installed-but-paused end state — carried-over. *(agent3)*
- **[M6] Privacy claim ("Local only … nothing beyond filtering") contradicts the persisted retry queue, which stores source chat + sender** — §Privacy vs Components §8 — store only the track URI in the retry queue, OR amend the privacy claim to admit chat/sender are persisted locally for retry — carried-over (partial). *(agent3)*
- **[M7] BYO Premium + own-dev-app requirement is disclosed on screen 3, AFTER the invasive FDA grant on screen 2 → non-Premium user hits a dead end** — §Onboarding 2→3 — gate/disclose Premium + create-your-own-app requirement on Welcome, before the FDA grant — **NEW** (from C2 BYO ordering). *(agent3)*

## Medium
- **[Med1]** Editing client_id in Settings silently invalidates stored tokens, no forced re-auth — §Components 9 vs §5 — clear Keychain tokens + playlist ID, drive "Reconnect Spotify" — carried-over. *(agent2 Med + agent1 Low — overlap)*
- **[Med2]** Custom-scheme redirect `friendlist://auth-callback` may be rejected for newly-created Spotify apps — §Components 5, §Onboarding 3 — verify at M2 on a fresh dev app; fall back to `http://127.0.0.1:<port>/callback` — NEW/design. *(agent1)*
- **[Med3]** App Nap will throttle/suspend the ~10s poll in a windowless LSUIElement app — §Components 2 — wrap scan loop in `ProcessInfo.beginActivity` to opt out — **NEW** (from menubar-only). *(agent1)*
- **[Med4]** "Requires Premium" appears unnecessary — playlist/library Web API works on free accounts — §Onboarding 3, §Components 5 — verify at M2, drop requirement if it works. *(agent1)*
- **[Med5]** Link regex still misses internationalized paths (`open.spotify.com/intl-xx/track/ID`) — §Components 4 — allow optional `/intl-[a-z]{2}` segment; force an intl link in M4 — carried-over (unaddressed). *(agent1)*
- **[Med6]** Multi-Mac on same Apple ID → duplicate playlist adds (independent per-Mac seen-sets, add API doesn't dedup) — §Dedup, §State — pre-add `contains`/snapshot re-check, or document single-Mac as a non-goal. *(agent1)*
- **[Med7]** Liked Songs dedup is track-ID-only, contradicting the "ISRC-aware" claim — §Dedup source 2 — state ID-only, or make full-library ISRC scan the opt-in path — carried-over. *(agent2)*
- **[Med8]** Cancelled/failed OAuth during onboarding has no state (Done unreachable) — §Onboarding 3 — define retry/cancel copy — carried-over. *(agent3)*
- **[Med9]** Deleted-playlist recovery action unspecified (no onboarding step to reopen; re-auth won't recreate) — M6/Architecture, Components §1 — on 404 recreate playlist + re-persist ID — carried-over (partial). *(agent3)*
- **[Med10]** No redirect-URI-mismatch / mistyped-client_id error path — opaque Spotify web-sheet failure — §Onboarding 3, §Components 5 — validate the client_id/redirect round-trip in Connect and show a targeted error — **NEW** (from BYO). *(agent3 Med + agent2 Low — overlap)*
- **[Med11]** Dev-app-owner account must equal the Premium/auth account, unstated — Component 5, §Onboarding 3 — state "use the same Premium Spotify account for both" — **NEW** (from BYO). *(agent3)*
- **[Med12]** Screen-2 grant copy overclaims "never uploaded, stored, or sent" despite local seen-set/retry queue — §Onboarding 2 — reword to "never leaves this Mac" — carried-over. *(agent3)*

## Low
- **[L1]** Watermark wording still reads as per-message; make the rule explicit: "highest ROWID such that all lower ROWIDs are terminally resolved; stop at first hole" — §Scanning loop. *(agent1)*
- **[L2]** `playlist-modify-public` scope unnecessary (playlist created private) — drop it to minimize consent — §Components 5. *(agent2)*
- **[L3]** Welcome hero still uses Spotify mark instead of the Messages+Spotify fusion branding — §Onboarding 1 vs §Branding. *(agent3)*
- **[L4]** Scope question says "certain group chats" but picker lists DMs — reword to "…certain chats?" — §Onboarding 2. *(agent3)*
- **[L5]** FDA poll has no timeout/skip nudge — after N seconds show "still waiting / open Settings again" — Components §1. *(agent3)*
- **[L6]** Persistent "nothing leaves your Mac" footer tensions screen 3 (opens browser dev dashboard) — footer copy that survives the browser step — §Onboarding footer. *(agent3)*

## Impl-notes
Messages DB parsing:
- attributedBody: `NSUnarchiver` deprecated/unavailable in Swift for typedstream blobs — use `NSAttributedString(data:documentAttributes:)` (streamtyped) or a typedstream parser with a `https://…spotify` byte-scan fallback. *(agent1)*
- `chat_message_join` LEFT JOIN emits multiple rows for a message in >1 chat → duplicate parse passes; add `GROUP BY m.ROWID`/`DISTINCT` or pick one chat deterministically. *(agent1)*
- Read-only WAL open may return `SQLITE_READONLY_CANTLOCK` when `-shm` can't be created; confirm fresh per-poll read-only connections see just-arrived rows (M1). *(agent1)*

OAuth / auth:
- OAuth `state` (CSRF) param unmentioned on the ASWebAuthenticationSession round-trip — generate + verify it. *(agent2)*
- Keep the redirect consistent: `ASWebAuthenticationSession(callbackURLScheme:)` takes bare `friendlist`, dashboard/Info.plist register `friendlist://auth-callback`. *(agent2)*
- Re-auth from the LSUIElement menubar-only app needs an ASWebAuthenticationSession presentation anchor — materialize a window/`presentationContextProvider`. *(agent2)*
- Confirm whether a dev-app owner must self-add under User Management (Development Mode) at M2 — if required, softens the "no allowlist/email" claim (see M2). *(agent1 + agent3)*

Distribution / packaging:
- Notarization needs Hardened Runtime + secure timestamp + entitlements for network client, Keychain, and app-sandbox-off/FDA — enumerate them. *(agent2)*
- Advisory `flock` dup-launch guard is largely redundant (LaunchServices blocks a second GUI instance); keep as belt-and-suspenders in Application Support. *(agent1)*
- Document exact TCC probe + `x-apple.systempreferences:` FDA deep-link target per macOS version. *(agent3)*

Branding / misc:
- Casing "friend list" (Welcome title) vs "Friend List" (playlist/app) — pick one (carryover). *(agent3)*
