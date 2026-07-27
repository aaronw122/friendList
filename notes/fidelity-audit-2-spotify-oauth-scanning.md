# Fidelity Audit 2 — Spotify keys (3) · OAuth (4) · Scanning (5)

READ-ONLY audit. Spec = `design_handoff/README.md` (cross-checked vs `FriendList Onboarding.dc.html`).
Legend: ✅ match · ⚠️ minor deviation · ❌ wrong/missing · 🛈 intentional (per brief, not a bug).

---

## Screen 3 — Spotify developer keys (`SpotifyKeysView.swift`)

| Element | Spec | Implemented | Verdict | Note |
|---|---|---|---|---|
| Heading copy | "Sorry — Spotify makes us do this" | same | ✅ | |
| Heading type | 26/800, tracking −0.03em, ink | 26/800, tracking −0.78, ink | ✅ | |
| Body type | 14pt, #6B6459, lh 1.5, maxW 470 | ui(14,400) body, lineSpacing 7, maxW 470 | ✅ | |
| Body copy | "…genuinely yours, not ours." | appends "A free Spotify account is fine." | ⚠️ | Extra sentence not in spec/HTML and not among listed corrections (line 22) |
| Step badge size/radius | 22×22, radius 7 | 22×22, radius 7 | ✅ | |
| **Step badge fill** | **#F1EDE4** | **Palette.well #F7F5F0** | ❌ | Wrong token (line 160) |
| Step badge numeral | 12/700, #6B6459 | ui 12/700, Palette.body | ✅ | |
| Step gap / content gap | 16 between steps, 13 to content | spacing 16; HStack spacing 13 | ✅ | |
| Redirect code field | bg #F7F5F0, 1px #EAE5DB, r9, pad 9×12 | well, line 1px, codeField 9, 9×12 | ✅ | |
| Code text | mono 12.5, #2A2622 | mono 12.5, fieldInk | ✅ | |
| **Copy button text color** | **#5D574E** | **Palette.body #6B6459** | ⚠️ | Wrong color (line 268) |
| Copy button box | bg #E9E4DA, 11.5/700, pad 5×11, r7 | #E9E4DA, 11.5/700, 5×11, r7 | ✅ | |
| Copy label flip | "Copy"→"Copied" 1400ms | 1400ms via Task.sleep | ✅ | |
| Footer | "Back" link / "Connect Spotify" | same | ✅ | |
| Primary enable gate | enabled once Client ID present | trims whitespace, non-empty | ✅ | |
| **4-step restructure** | expanded: Login / Dashboard+Create / Form / paste Client ID | 4 StepRows w/ exact form values | 🛈 | Correction implemented; App name "friendList", desc "personal use", ✅ Web API, Redirect+Copy all present |
| **No Client Secret field** | removed | only Client ID field | 🛈 | Correction implemented |
| **Redirect URI value** | friendlist://auth-callback | SpotifyConfig.redirectURI = same | 🛈 | Correction consistent everywhere |
| Client ID input | (redesigned single field) | LabeledField mono, r10, pad 10×13, 14pt | 🛈 | Redesigned field; radius 10 & 14pt-mono differ from old 2-input spec (r9/13pt) — acceptable as part of redesign |

## Screen 4 — OAuth consent (`OAuthConsentView.swift`)

| Element | Spec | Implemented | Verdict | Note |
|---|---|---|---|---|
| Badge | 66×66 #1DB954 circle, bars 30/24/17×4 r2, 4pt gaps | matches | ✅ | |
| Badge shadow | 0 10px 22px rgba(29,185,84,.32) + inset bottom | spotifyBadge (r11,y10) + gradient overlay | ✅ | inset approximated |
| Heading | "Now the easy part" 26/800, 16pt below badge | ui 26/800 tracking, padTop 16 | ✅ | |
| Body copy | "Sign in to Spotify…A browser window will open." | same | ✅ | |
| Body type | 14pt body, maxW 400, centered | ui(14,400), maxW 400, centered | ✅ | |
| Body top gap | HTML 8px below heading | padTop 12 | ⚠️ | 12 vs 8 (line 28) |
| Scope card box | well, r12, pad 14×18, 8pt row gap | well, row r12, 14×18, spacing 8 | ✅ | |
| **Scope card width** | inline-block (hugs content) | full sheet width (no maxWidth) | ⚠️ | Card stretches full width instead of content-hugging pill |
| Granted rows text | #4A4459 | Palette.privacyText #4A4459 | ✅ | |
| Granted dots | #1DB954 | Palette.spotify | ✅ | |
| **Excluded row text color** | **#9A9184** | **Palette.faint #A79E90** | ⚠️ | Wrong color (line 75) |
| Excluded dot | #D8D2C6 | Color(hex:"D8D2C6") | ✅ | |
| Dot size / gap | 6pt dot; HTML 9px gap | 6pt; spacing 10 | ✅ | gap 10 vs 9 trivial |
| Footer | "Back" / "Authorize with Spotify" | same | ✅ | |
| **Scope copy rewrite** | 3 granted (private playlists / read playlists / Liked Songs) + 1 excluded; "Search the Spotify catalog" removed | 4 rows exactly matching | 🛈 | Correction implemented; rows mirror SpotifyConfig.scopes; excluded line reads "…no listening history, no posting, no following" |

## Screen 5 — Scanning (`ScanningView.swift` / `LoaderScaffold`)

| Element | Spec | Implemented | Verdict | Note |
|---|---|---|---|---|
| Spinner | 46×46, 4pt, track #EFEBE3, accent arc, 360/0.8s linear | matches (trim .25, round cap) | ✅ | |
| Heading copy | "Reading {chat}" | "Reading \(selectedChatName)" | ✅ | |
| Heading type | 22/800, tracking −0.03em, 20pt below spinner | ui(22,800), padTop 20, **no tracking** | ⚠️ | Missing −0.03em tracking (line 55–56) |
| Status line | 13.5 #6B6459, min-h 20 | ui(13.5) body, minHeight 20 | ✅ | |
| Progress bar | 300×6, r3, track #EFEBE3, accent, 400ms ease | 300×6, r3, spinnerTrack, accent, easeInOut .4 | ✅ | |
| Counter | mono 12, #A79E90, "{n} songs found" | mono(12) faint, "\(found) songs found" | ✅ | |
| Status seq / timings | 0/500/1500/2500/3200 + 350ms; 0/22/58/88/100% | exact match | ✅ | |
| Count timing | at 58%: count=60%; at 88%: full | found=links*0.6 then links | ✅ | |

---

## Intentional (not bugs) — verified consistent

- **PKCE, no Client Secret** — `SpotifyKeysView` has only a Client ID field; no `clientSecret` anywhere in Sources. ✅
- **Redirect URI `friendlist://auth-callback`** — single source `SpotifyConfig.redirectURI`; used by field, copy, and callback scheme "friendlist". No stale `friendlist://callback` in Sources. ✅
- **4-step Spotify setup** — Login → Dashboard+Create → Form (exact values) → paste Client ID. Form values `friendList` / `personal use` / Redirect+Copy / ✅ Web API all present. ✅
- **OAuth scope rewrite** — 3 granted lines mapped to real scopes + 1 excluded; "Search the Spotify catalog" removed. Matches `SpotifyConfig.scopes` (`playlist-modify-private`, `playlist-read-private`, `user-library-read`). ✅

## App-wide note
"Back" uses `LinkButton`, which underlines only on hover; spec describes a "plain underlined link". Consistent across all sheet screens — design choice, not screen-specific.
