# Handoff: FriendList — Onboarding + Home (macOS)

## Overview
FriendList is a macOS menu-bar-style utility that reads a group chat in Messages **locally**, finds song links, and turns them into a Spotify playlist that keeps growing as people keep sharing.

This bundle covers the complete first-run experience — an animated welcome scene, chat selection, Spotify developer-key setup, OAuth, two loading states, playlist customization, and the post-onboarding home screen.

## About the Design Files
The files in this bundle are **design references created in HTML**. They are prototypes demonstrating intended look, motion, and behavior — **not production code to port directly**.

The target is a **native Swift / SwiftUI macOS app**. The task is to recreate these designs in SwiftUI using native components and platform conventions. Concretely:

- HTML/CSS layout → SwiftUI `VStack` / `HStack` / `ZStack` / `Grid`
- The physics scene → **SpriteKit** (`SKScene` with `SKPhysicsBody`, `SKSpriteNode`) hosted in a `SpriteView`, or SwiftUI Canvas + a custom solver. Matter.js is the reference for *feel*, not the implementation.
- Sheet slide-down transition → SwiftUI `.transition(.move(edge: .top))` with a spring animation
- The window itself → a fixed-size `NSWindow` (760×560 content area), `.titled` style with a centered title, non-resizable during onboarding

Do not embed a WebView.

## Fidelity
**High fidelity.** Colors, typography, spacing, radii, shadows, and copy are final. Recreate pixel-accurately, substituting native SwiftUI equivalents where a CSS effect has no direct analogue (see *Known CSS→SwiftUI gaps* at the end).

---

## Window

| Property | Value |
|---|---|
| Content size | 760 × 560 pt, fixed (non-resizable) |
| Title bar | 36pt tall, background `#F3F0EA`, 1px bottom border `rgba(35,30,25,.07)` |
| Title | "FriendList", 12pt / semibold(600) / `#8B8377`, centered |
| Corner radius | 14pt |
| Traffic lights | Standard macOS (the HTML draws fakes at 11px: `#F0655A`, `#F1BE43`, `#5FC559`) |
| Body background | Vertical gradient `#FDFBF7` → `#F4F0E8` |
| Window shadow | `0 32px 70px -20px rgba(40,33,25,.45)` |

The **stage** is the full content area below the title bar (760 × 524). Every screen renders on top of the persistent physics scene.

---

## Screens / Views

### 1. Welcome (`step 1`)

**Purpose:** first impression; establishes the playful tone and gives the user something to fidget with.

**Layout:** physics objects fall from above the top edge and settle. Centered text block anchored 87pt from the top; the CTA is anchored **212pt from the bottom** (not relative to the text — it must not shift when copy reflows).

**Components**

| Element | Spec |
|---|---|
| Wordmark | "FriendList" — Plus Jakarta Sans, 60pt, weight 800, tracking `-0.035em`, `#1D1B18`, line-height 1.0, subtle white text shadow `0 2px 0 rgba(255,255,255,.9)` |
| Subhead | "Turn a group chat's songs into a Spotify playlist — and keep it growing." — 17pt, weight 500, `#5D574E`, line-height 1.45, max width 400pt, 20pt below wordmark, centered |
| Kicker | "ALWAYS LISTENING · NEVER UPLOADING" — IBM Plex Mono, 12pt, tracking `.06em`, uppercase, `#9A9184`, 10pt below subhead |
| Primary CTA | "Continue" — 15pt / 700 / white on `#9B85F2`, padding 14×44, radius 13pt, shadow `0 8px 18px rgba(90,68,190,.35)` + inner top highlight `inset 0 2px 0 rgba(255,255,255,.35)` + inner bottom shade `inset 0 -3px 0 rgba(0,0,0,.12)`. Hover: translateY(-2pt), deeper shadow. Active: translateY(+1pt). |
| CTA caption | "or toss the stuff around a bit first" — 11.5pt, `#A79E90`, 10pt below the button |

**On Continue:** every *other* solid object (index % 2 == 0) is removed from the simulation and plays a 340ms pop — `scale 1 → 1.45 → 1.7` with `opacity 1 → 1 → 0`, staggered 55ms apart. After 420ms the sheet drops in.

---

### 2. Pick a group chat (`step 2`)

**Purpose:** choose the source chat, and reassure about privacy before anything is read.

The privacy notice is deliberately the **first thing** on the screen, above the heading.

| Element | Spec |
|---|---|
| Privacy card | Background `#F4F1FB`, radius 12pt, padding 12×14, 20pt bottom margin. 18×18pt rounded-square icon (radius 5pt) in `#9B85F2` with `inset 0 -2px 0 rgba(0,0,0,.14)`, 10pt gap. Text 12.5pt, line-height 1.5, `#4A4459`; lead sentence bold in `#2E2840`. |
| Privacy copy | **"Everything stays on your Mac."** "FriendList reads Messages locally to spot song links. Your texts are never uploaded, stored, or seen by anyone — including us." |
| Heading | "Pick a group chat" — 26pt / 800 / `-0.03em` / `#1D1B18` |
| Subhead | "Just one to start. You can add more chats whenever you like." — 14pt, `#6B6459`, 7pt below |
| Permission state | Shown when Full Disk Access has not been granted. Dashed border 1.5pt `#DED8CC`, radius 14pt, padding 26pt, centered. Title 14pt/600 `#3A352E`: "FriendList needs Full Disk Access to read Messages". Sub 12.5pt `#8A8275`: "macOS will ask you to confirm in System Settings." Button "Grant access" — 14pt/700 white on accent, padding 11×24, radius 11pt. |
| Chat list | Shown after access. Border 1pt `#EAE5DB`, radius 13pt, max height 184pt, scrolls. Rows: 11×14 padding, 1pt bottom divider `#F2EEE6`, 11pt gap. Selected row background `#F4F1FB`. |
| Row radio | 15×15pt circle. Unselected: 2pt border `#D8D2C6`. Selected: 5pt border in accent (filled-ring look). |
| Row name | 14pt / 700 / `#2A2622` |
| Row count | IBM Plex Mono 11pt `#A79E90`, right-aligned |
| CTA | "Continue", bottom-right, disabled until a chat is selected |

**Sample data** (replace with real Messages queries): the boys · 48 links; brunch club · 31; Cabin Trip 2026 · 12; roommates · 9; sunday runners · 6; Fam · 3.

**Real implementation note:** this requires Full Disk Access to read `~/Library/Messages/chat.db` (SQLite). Query `chat` joined to `chat_handle_join` / `message` to enumerate group chats. Per the user's decision the picker shows **chat name only** — no avatars, no member lists.

---

### 3. Spotify developer keys (`step 3`)

**Purpose:** the unavoidable friction step. Tone is warm, honest, and brief about why.

| Element | Spec |
|---|---|
| Heading | "Sorry — Spotify makes us do this" — 26pt / 800 |
| Body | "Spotify only lets small apps like this one run on keys you create yourself. It takes about three minutes, and it means the playlist and the account are genuinely yours, not ours." — 14pt, `#6B6459`, line-height 1.5, max width 470pt |
| Step badges | 22×22pt, radius 7pt, `#F1EDE4`, numeral 12pt/700 `#6B6459`, 13pt gap to content, 16pt between steps |
| Step 1 | "Open the [Spotify developer dashboard](https://developer.spotify.com/dashboard) and hit *Create app*. Name it anything — "FriendList" works." |
| Step 2 | "Paste this as the Redirect URI:" + code field — background `#F7F5F0`, 1pt border `#EAE5DB`, radius 9pt, padding 9×12. Code in IBM Plex Mono 12.5pt `#2A2622`: `friendlist://callback`. Copy button: `#E9E4DA`, 11.5pt/700 `#5D574E`, padding 5×11, radius 7pt; label flips to "Copied" for 1400ms. |
| Step 3 | "Copy your two keys over:" + two side-by-side inputs (equal columns, 10pt gap), placeholders "Client ID" and "Client secret". Inputs: 1.5pt border `#EAE5DB`, radius 9pt, padding 10×12, IBM Plex Mono 13pt, background `#FDFCFA`. Focus border `#B6A6F0`. |
| Footer | "Back" plain underlined link (left) / "Connect Spotify" primary (right) |

Store the client secret in the **Keychain**, never in `UserDefaults`.

---

### 4. OAuth (`step 4`)

**Purpose:** the actual Spotify authorization, and a plain statement of scopes.

| Element | Spec |
|---|---|
| Badge | 66×66pt circle, `#1DB954`, centered. Contains three stacked white bars (30/24/17 × 4pt, radius 2pt, 4pt gaps) — a simplified Spotify glyph. Shadow `0 10px 22px rgba(29,185,84,.32)`, `inset 0 -4px 0 rgba(0,0,0,.12)`. **Use the official Spotify logo asset in production, per their brand guidelines.** |
| Heading | "Now the easy part" — 26pt / 800, 16pt below badge |
| Body | "Sign in to Spotify and give FriendList permission to build playlists in your account. A browser window will open." — 14pt `#6B6459`, max width 400pt, centered |
| Scope card | Inline-block, `#F7F5F0`, radius 12pt, padding 14×18, left-aligned, 8pt row gap. Rows are 6pt dots + 12.5pt text. Granted rows: dot `#1DB954`, text `#4A4459`. Excluded row: dot `#D8D2C6`, text `#9A9184`. |
| Scope rows | "Create and edit your playlists" · "Search the Spotify catalog" · "Nothing else — no listening history, no following" |
| Footer | "Back" link / "Authorize with Spotify" primary |

**Real implementation:** `ASWebAuthenticationSession` with PKCE. Scopes: `playlist-modify-private`, `playlist-modify-public`, `ugc-image-upload`. Callback `friendlist://callback` registered as a custom URL scheme in `Info.plist`. Refresh token → Keychain.

---

### 5. Scanning (`step 5`) — loading state

**Purpose:** cover the real work of parsing the chat and resolving tracks.

| Element | Spec |
|---|---|
| Spinner | 46×46pt ring, 4pt stroke `#EFEBE3` with top arc in accent `#9B85F2`, rotating 360° / 0.8s linear, infinite |
| Heading | "Reading {chat name}" — 22pt / 800, 20pt below spinner |
| Status line | 13.5pt `#6B6459`, min-height 20pt (prevents layout jump between messages) |
| Progress bar | 300 × 6pt, radius 3pt, track `#EFEBE3`, fill accent, width animates over 400ms ease |
| Counter | IBM Plex Mono 12pt `#A79E90` — "{n} songs found" |

**Status sequence** (prototype timings; drive from real progress in the app):
0ms "Opening the local Messages database…" (0%) → 500ms "Scanning 4,812 messages for links…" (22%) → 1500ms "Matching links to Spotify tracks…" (58%, count at 60%) → 2500ms "Removing duplicates…" (88%, full count) → 3200ms (100%) → 350ms later advance.

---

### 6. Customize (`step 6`)

**Purpose:** name it and set a cover before anything is written to Spotify. Nothing exists on Spotify yet at this point.

| Element | Spec |
|---|---|
| Result pill | Inline-flex, `#EFF7EF`, radius 99pt, padding 6×13, 12pt / 700 `#3E7A44`, 8pt gap, 7pt green dot `#5FC559`. Text: "{n} songs found in {chat name}" |
| Heading | "Make it yours" — 26pt / 800, 14pt below pill |
| Subhead | "Or leave it exactly as is — it already works." — 14pt `#6B6459` |
| Cover well | 104×104pt, radius 10pt, 45° stripe pattern `#EFEBE3`/`#E6E1D8` at 8pt intervals, shadow `0 6px 14px rgba(35,28,20,.14)`. Label IBM Plex Mono 10pt `#A79E90`, two lines: "default / cover". Below: "Use your own" plain underlined link, 12pt. |
| Name field | Label "PLAYLIST NAME" — 11.5pt / 700 / `.06em` / uppercase / `#9A9184`, 6pt above. Input: 1.5pt `#EAE5DB`, radius 10pt, padding 11×13, 14pt / 600. Defaults to the chat name. |
| Description field | Label "DESCRIPTION", same treatment. Input 13.5pt regular. Default: "Made from the group chat. Kept fresh by FriendList." |
| Layout | Cover on the left (fixed), fields column on the right (flex 1), 20pt gap, 14pt between fields |
| Footer | "Back" link (returns to **step 4**, skipping the scan) / "Create playlist" primary |

Cover upload should use `NSOpenPanel` restricted to JPEG; Spotify's `ugc-image-upload` requires base64 JPEG ≤ 256 KB.

---

### 7. Creating (`step 7`) — loading state

Identical layout to *Scanning*, in the **accent purple** (not Spotify green — the user explicitly chose purple for both loaders).

Heading "Building your playlist". Sequence: 0ms "Creating the playlist on Spotify…" (0%) → 500ms "Adding tracks…" (30%) → 1500ms "Uploading cover art…" (72%) → 2400ms "Done" (100%) → 400ms later advance.

On completion the playlist is appended to the home list.

---

### 8. All set (`step 8`)

| Element | Spec |
|---|---|
| Heading | "You're all set" — 30pt / 800, centered |
| Body | "FriendList is watching {chat name}. Every song anyone drops in lands in the playlist within a minute." — 14.5pt `#6B6459`, line-height 1.55, max width 380pt |
| Link card | Max width 400pt, `#F7F5F0`, 1pt border `#EAE5DB`, radius 12pt, padding 11×14, 12pt gap. 44×44pt cover thumb (same stripe pattern, radius 7pt). Title 13.5pt/700 `#2A2622` truncating. Below it the playlist URL as an underlined link, IBM Plex Mono 12pt `#6B6459`. |
| Primary | "Open in Spotify" |
| Secondary | "Back to FriendList" — plain underlined link, 12.5pt → goes to Home |

---

### 9. Home (`step 0`)

**Purpose:** the app's steady state after onboarding.

Entering Home **re-drops every object from the ceiling** — the welcome animation replays each time the window opens. (In the prototype: all bodies are restored to the world, repositioned above the top edge at staggered heights, velocities zeroed, with a small random angular velocity.)

| Element | Spec |
|---|---|
| Panel | 430pt wide (max 88%), 34pt from the top, centered. `rgba(255,255,255,.94)` with a 10pt backdrop blur, radius 16pt, shadow `0 18px 40px -12px rgba(40,33,25,.34)`, padding 20/22/18. |
| Panel header | "FriendList" 22pt / 800 left; "SYNCING" IBM Plex Mono 11pt uppercase `.06em` `#A79E90` right, baseline-aligned |
| Playlist row | 1pt border `#EFEAE1`, radius 12pt, padding 10×12, background `#FDFCFA`, 12pt gap, 9pt between rows. 42×42pt cover thumb (radius 8pt, stripe pattern). Name 14pt/700 `#2A2622` truncating; meta 12pt `#8A8275` — "{n} songs · from {chat}". Trailing 7pt `#5FC559` dot pulsing opacity .35↔1 over 2s. |
| CTA | "Create a new one" — full-width primary, 14pt/700, padding 12pt, radius 12pt, 14pt above |

"Create a new one" pops half the objects and returns to **step 2**, preserving Spotify auth and the developer keys.

---

## The physics scene

Present on every screen; UI floats above it. Objects fall from above the top edge on launch, collide, and pile up. The user can grab and fling any object with the cursor.

**Engine settings (Matter.js reference values)**

| Setting | Value |
|---|---|
| Gravity Y | 1.05 |
| Walls | Floor, left, right (all static, restitution 0.4, friction 0.6) + a high ceiling well above the frame so objects can spawn off-screen |
| Body restitution | 0.52 |
| Body friction | 0.35 |
| Air friction | 0.008 |
| Spawn | Random X within the frame (70pt inset), Y between −120 and −640, random initial angle ±0.6 rad |
| Stagger | First body enters at 260ms, then one every 130ms |
| Drag | Mouse constraint, stiffness 0.18. Scroll-wheel capture disabled. |
| Collision shape | Circle for round objects; rounded rect (corner radius `min(10, h/3)`) for the rest |

**Object inventory** (14 total)

| Object | Size | Shape |
|---|---|---|
| Vinyl record | 98×98 | circle — dark disc, `#9B85F2` label, white spindle hole |
| CD | 80×80 | circle — iridescent conic gradient, white center |
| Cassette | 118×74 | rect — `#EFB63F` shell, cream window, two `#3B352E` spools |
| Headphones | 92×80 | rect — `#4B4550` band (13pt stroke), two `#5B5466` earcups |
| Gold chain | 104×24 | rect — four interlocking 22pt rings alternating `#E9BE4A` / `#F0CB63` |
| Smiley bead | 62×62 | circle — `#F4A0C0` with `#5A2C42` face |
| Music note | 48×62 | rect — `#37333C` stem, flag, tilted oval head |
| Star | 58×58 | rect — `#F3C63F`, 5-point |
| Heart | 52×46 | rect — `#EF6079`, two rotated lobes |
| Guitar pick | 50×56 | rect — teal gradient `#7FC7B4`→`#4FA893` |
| Ticket stub | 118×56 | rect — `#F0E3C4` aged stock, **torn/perforated edges on all four sides**, dashed tear line, "ADMIT ONE" in IBM Plex Mono 7pt, tracking `.14em`, `#8A7C56`, rotated 90° |
| Link preview card | 136×60 | rect — white, `#CDC6F5`→`#A996EE` thumb, two grey text bars |
| iMessage bubble | 196×46 | rect — `#1B8DFF`, radius 23pt, white 15pt/600 text "you need to hear this", with a clipped tail hooking off the bottom-right corner |
| Jerry Garcia sticker | 96×96 | circle — image asset, white ring |

Balloons were prototyped and **cut** — nothing floats; everything settles.

In SpriteKit, render each object as an `SKSpriteNode` with a texture rendered once from a vector asset, and attach `SKPhysicsBody(circleOfRadius:)` or `(rectangleOf:)`.

---

## Interactions & Behavior

**Navigation:** linear 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8, then Home (0). Back from step 6 jumps to step 4 (never re-runs the scan). Home → step 2.

**Sheet transition:** a 600pt-wide white panel slides down from the top edge (`translateY(-105%)` → `0`) over 620ms with `cubic-bezier(.22, 1.1, .36, 1)` — a spring with slight overshoot. Radius 20pt on the bottom corners only, shadow `0 26px 50px -12px rgba(40,33,25,.4)`. It stays mounted for all of steps 2–8; only the content inside swaps.

**Progress bar:** 4pt strip pinned to the top of the sheet, track `#EDE9E1`, accent fill with a 3pt radius on its right edge, 500ms ease. Widths by step: 2→16%, 3→34%, 4→50%, 5→64%, 6→80%, 7→92%, 8→100%.

**Button states:** disabled CTA is `#DED8CC` with no shadow and `not-allowed` cursor. Enabled hover lifts 2pt; active presses 1pt.

**Loading states** auto-advance on timers in the prototype — in the app they must be driven by real progress, with error paths for: no Full Disk Access, invalid client credentials, OAuth denial/cancel, network failure, and zero songs found.

---

## State Management

```
step            Int      0 = home, 1 = welcome, 2…8 = onboarding
lists           [Playlist]  created playlists shown on home
access          Bool     Full Disk Access granted
pick            Int?     selected chat index
clientId        String
clientSecret    String   → Keychain
copied          Bool     transient, 1400ms
name / desc     String   playlist fields
scanPct/found/scanLabel      scanning progress
createPct/createLabel        creation progress
```

---

## Design Tokens

**Color**

| Token | Hex | Use |
|---|---|---|
| Accent | `#9B85F2` | CTAs, progress, both loaders, selection |
| Accent alternatives | `#B7A2FF` `#8A6FE8` `#7C6BD6` | offered as tweaks |
| Ink | `#1D1B18` | headings |
| Body | `#6B6459` | body copy |
| Muted | `#8A8275` | secondary |
| Faint | `#A79E90` | mono captions |
| Line | `#EAE5DB` | borders |
| Divider | `#F2EEE6` | list dividers |
| Surface | `#FFFFFF` | sheet |
| Field | `#FDFCFA` | inputs |
| Well | `#F7F5F0` | code/scope blocks |
| Tint | `#F4F1FB` | privacy card, selected row |
| Focus | `#B6A6F0` | input focus border |
| Success | `#5FC559` | sync dot |
| Success text | `#3E7A44` on `#EFF7EF` | result pill |
| Spotify | `#1DB954` | OAuth badge only |
| iMessage | `#1B8DFF` | bubble object |
| Desk | `#FDFBF7` → `#F4F0E8` | stage gradient |

**Type** — Plus Jakarta Sans (400/500/600/700/800) for UI; IBM Plex Mono (400/500) for captions, counts, and code. Substitute SF Pro + SF Mono if you'd rather stay system-native — note that headings lose some of their character at weight 800.

Scale: 60 / 30 / 26 / 22 / 17 / 15 / 14.5 / 14 / 13.5 / 12.5 / 12 / 11.5 / 11 / 10 / 7pt. Headings use tracking −0.03em (−0.035em at 60pt); uppercase mono labels use +0.06em.

**Radius** — 4 (progress) · 7 (small chips) · 9 (code field) · 10–13 (inputs, buttons, rows) · 14 (window) · 16 (home panel) · 20 (sheet bottom) · 23 (bubble) · 99 (pill).

**Shadow** — Window `0 32px 70px -20px rgba(40,33,25,.45)`; sheet `0 26px 50px -12px rgba(40,33,25,.4)`; home panel `0 18px 40px -12px rgba(40,33,25,.34)`; primary button `0 8px 18px rgba(90,68,190,.35)`; objects `0 6-10px 12-20px rgba(35,28,20,.2-.28)`.

Buttons carry an inner top highlight and inner bottom shade — in SwiftUI, a subtle vertical gradient overlay plus a light top stroke reproduces this.

---

## Assets

- `uploads/Cartoony SVG Request Jul 25 2026.png` — the Jerry Garcia sticker, user-supplied, included in this bundle.
- Every other object is drawn in CSS (gradients, clip-paths, box-shadows). Re-author each as a vector asset (SVG → PDF or an Asset Catalog vector) for the Swift app; the HTML is the visual spec.
- The Spotify glyph in the prototype is an approximation — ship the official mark from Spotify's brand assets.
- Fonts: Plus Jakarta Sans and IBM Plex Mono, both SIL Open Font License, from Google Fonts.

## Files

- `FriendList Onboarding.dc.html` — the complete prototype, all nine screens plus the physics scene. Open it in a browser and click through.
- `uploads/Cartoony SVG Request Jul 25 2026.png` — sticker asset.

## Known CSS→SwiftUI gaps

- `backdrop-filter: blur(10px)` on the home panel → `.background(.ultraThinMaterial)`
- `clip-path` shapes (torn ticket edges, bubble tail, star) → custom `Shape` / `Path`, or ship as vector assets
- `inset` box-shadows → overlay gradients + strokes
- `text-wrap: pretty` has no equivalent; SwiftUI's default wrapping is close enough
- Hover states apply to pointer input only — use `.onHover`, and make sure every action is reachable via keyboard
