# Fidelity Audit 3 — Customize (6), Creating (7), All set (8), Home (0)

READ-ONLY audit. Spec = `design_handoff/README.md` (authoritative) cross-checked against
`design_handoff/FriendList Onboarding.dc.html`. Implementation as of this audit.

Legend: ✅ match · ⚠️ minor/approximate deviation · ❌ clear deviation

---

## 6. Customize (step 6) — `Sources/Onboarding/Screens/CustomizeView.swift`

| Element | Spec | Implemented | Verdict | Note |
|---|---|---|---|---|
| Result pill bg | `#EFF7EF`, radius 99 | `Palette.successBg` #EFF7EF, `Radii.pill` 99 | ✅ | |
| Result pill padding | 6×13 | v6 h13 | ✅ | |
| Result pill text | 12/700 `#3E7A44` | ui(12,700) successText | ✅ | |
| Result pill dot | 7pt `#5FC559`, gap 8 | 7pt success, HStack spacing 8 | ✅ | |
| Pill copy | "{n} songs found in {chat name}" | `\(found) songs found in \(selectedChatName)` | ✅ | char-exact |
| Heading text | "Make it yours" | same | ✅ | |
| Heading type | 26/800, tracking −0.03em, `#1D1B18` | ui(26,800) ink, **no tracking** | ⚠️ | tracking −0.03em omitted (line 33) — AllSet/Home apply it, Customize doesn't |
| Heading top margin | 14 | .top 14 | ✅ | |
| Subhead text | "Or leave it exactly as is — it already works." | same | ✅ | em dash present |
| Subhead type | 14 `#6B6459` | ui(14) body | ✅ | |
| Subhead top margin | 7 (HTML) | .top 6 | ⚠️ | 6 vs 7 |
| Cover/fields row gap | 20 | HStack spacing 20 | ✅ | |
| Cover/fields row top | 20 (HTML) | .top 22 | ⚠️ | 22 vs 20 |
| Cover well size/radius | 104×104, radius 10 | StripeCover(104), corner 10 | ✅ | |
| Cover well shadow | `0 6px 14px rgba(35,28,20,.14)` | **none** | ❌ | StripeCover has no shadow; `Shadows.coverThumb` (exact spec) defined but unused |
| Cover stripe pattern | 8pt stripes / 16pt period, 135° | 4pt bars / 8pt period, 45° | ❌ | see StripeCover note below — half-scale & mirrored diagonal |
| Cover label | mono 10 `#A79E90`, "default\ncover" | mono(10) faint, "default\ncover" | ✅ | |
| "Use your own" link | plain underlined, 12 | LinkButton size 12 (underline on hover only) | ⚠️ | underline only appears on hover (app-wide LinkButton trait) |
| Field label type | 11.5/700, +.06em, uppercase, `#9A9184` | ui(11.5,700) tracking .06 uppercase, `Palette.faint` #A79E90 | ⚠️ | color #A79E90 substituted for spec #9A9184 (Components.swift:127) |
| Field label→input gap | 6 above input | VStack spacing 6 | ✅ | |
| Name input border/radius | 1.5 `#EAE5DB`, radius 10 | 1.5 line, Radii.input 10 | ✅ | |
| Name input padding | 11×13 | v10 h13 | ⚠️ | vertical 10 vs 11 (Components.swift:134) |
| Name input type | 14/600 `#2A2622` | ui(14,600) fieldInk | ✅ | |
| Name default | chat name | seedNameIfNeeded() → selectedChatName | ✅ | |
| Description input type | 13.5 **regular** | ui(13.5,**600**) | ❌ | LabeledField hardcodes weight 600 (Components.swift:132); desc should be 400 |
| Description default | "Made from the group chat. Kept fresh by FriendList." | state.desc same | ✅ | char-exact |
| Footer | "Back" link / "Create playlist" | SheetFooter same | ✅ | |
| Back target | step 6 → step 4 (skip scan) | back(): step==6 ? 4 | ✅ | |
| Footer placement | 24pt below fields (HTML) | Spacer pins footer to sheet bottom | ⚠️ | full-height sheet pushes footer far below content |
| Sheet content inset | HTML sheet padding 26 top / 34 horiz | topInset 40 / hInset 44 | ⚠️ | shared across sheet screens; wider/lower than HTML |

## 7. Creating (step 7) — `Sources/Onboarding/Screens/CreatingView.swift` (+ LoaderScaffold in ScanningView.swift)

| Element | Spec | Implemented | Verdict | Note |
|---|---|---|---|---|
| Spinner | 46×46, 4pt track `#EFEBE3`, top arc accent, 360°/0.8s | LoaderSpinner 46, 4pt spinnerTrack, 0.25 trim accent, 0.8s linear | ✅ | |
| Heading text | "Building your playlist" | same | ✅ | |
| Heading type | 22/800, tracking −0.03em | ui(22,800) ink, **no tracking** | ⚠️ | tracking −0.03em omitted (ScanningView.swift:55, shared) |
| Heading top margin | 20 | .top 20 | ✅ | |
| Status line | 13.5 `#6B6459`, min-height 20 | ui(13.5) body, minHeight 20 | ✅ | |
| Progress bar | 300×6, radius 3, track `#EFEBE3`, fill accent, 400ms ease | 300×6, r3, spinnerTrack, accent, easeInOut .4s | ✅ | |
| Counter line | none (accent purple loader, no counter) | counter: nil | ✅ | |
| Color | accent purple (not Spotify green) | Palette.accent | ✅ | |
| Sequence | 0 "Creating…"(0%) → 500 "Adding tracks…"(30%) → 1500 "Uploading cover art…"(72%) → 2400 "Done"(100%) → +400 advance | 0/500/1500(→900 sleep)/2400 Done/+400 completeCreation | ✅ | timings & % exact, labels char-exact |
| On completion | append playlist to Home, advance to 8 | completeCreation() appends + go(8) | ✅ | |

## 8. All set (step 8) — `Sources/Onboarding/Screens/AllSetView.swift`

| Element | Spec | Implemented | Verdict | Note |
|---|---|---|---|---|
| Heading text | "You're all set" | same | ✅ | |
| Heading type | 30/800, −0.03em, centered | ui(30,800) ink, tracking −0.03·30, centered | ✅ | |
| Body copy | "FriendList is watching {chat}. Every song anyone drops in lands in the playlist within a minute." | same | ✅ | char-exact |
| Body type | 14.5 `#6B6459`, line-height 1.55, max-w 380 | ui(14.5) body, lineSpacing 14.5·0.55, maxW 380 | ✅ | correct 1.55→lineSpacing conversion |
| Body top margin | 10 (HTML) | .top 14 | ⚠️ | 14 vs 10 |
| Link card | max-w 400, `#F7F5F0`, 1pt `#EAE5DB`, radius 12, padding 11×14, gap 12 | maxW 400, well, line stroke 1, Radii.row 12, v11 h14, spacing 12 | ✅ | |
| Card thumb | 44×44, radius 7, stripe (no shadow) | StripeCover(44, corner 7) | ✅ | correct: no shadow here; but stripe scale off (see StripeCover) |
| Card title | 13.5/700 `#2A2622`, truncate | ui(13.5,700) fieldInk, lineLimit 1 | ✅ | |
| Card URL | mono 12 `#6B6459` underlined "open.spotify.com/playlist/…" | mono(12) body underline, same text | ✅ | |
| Card top margin | 20 (HTML) | .top 22 | ⚠️ | 22 vs 20 |
| Primary | "Open in Spotify" | PrimaryButton | ✅ | |
| Secondary | "Back to FriendList" plain link 12.5 → Home | LinkButton size 12.5 → goHome() | ✅ | |
| Secondary gap | 12 (HTML column gap) | .top 14 | ⚠️ | 14 vs 12 |
| Content top inset | ~40 (26 sheet + 14) | none (heading pinned near progress bar) | ⚠️ | AllSetView adds no top padding |

## 0. Home (step 0) — `Sources/Onboarding/Screens/HomeView.swift`

| Element | Spec | Implemented | Verdict | Note |
|---|---|---|---|---|
| Panel width | 430 (max 88%) | min(430, w·0.88) | ✅ | |
| Panel top offset | 34 | .top 34 | ✅ | |
| Panel bg | `rgba(255,255,255,.94)` + 10pt blur | ultraThinMaterial + surface·0.6 | ✅* | intentional CSS→SwiftUI blur gap |
| Panel radius | 16 | Radii.homePanel 16 | ✅ | |
| Panel shadow | `0 18px 40px -12px rgba(40,33,25,.34)` | Shadows.homePanel | ✅ | approximated per token |
| Panel padding | 20 / 22 / 18 | top20 h22 bottom18 | ✅ | |
| Header title | "FriendList" 22/800 −0.03em | ui(22,800) ink, tracking −0.03·22 | ✅ | |
| Header status | "SYNCING" mono 11, +.06em, uppercase `#A79E90`, baseline-aligned | mono(11) faint, tracking .06·11, uppercase, firstTextBaseline | ✅ | |
| Rows container | margin-top 14, gap 9 | .top 14, VStack spacing 9 | ✅ | |
| Row border/radius | 1pt `#EFEAE1`, radius 12 | stroke #EFEAE1 1, Radii.row 12 | ✅ | |
| Row padding/bg | 10×12, `#FDFCFA` | v10 h12, field #FDFCFA | ✅ | |
| Row thumb | 42×42, radius 8, stripe | StripeCover(42, corner 8) | ✅ | stripe scale off (see StripeCover) |
| Row name | 14/700 `#2A2622`, truncate | ui(14,700) rowName, lineLimit 1 | ✅ | |
| Row meta | 12 `#8A8275`, "{n} songs · from {chat}" | ui(12) muted, same | ✅ | char-exact, gap 2 |
| Pulsing dot | 7pt `#5FC559`, opacity .35↔1 over 2s | 7pt success, .35↔1, easeInOut 2s repeatForever | ✅ | |
| CTA text | "Create a new one" | same | ✅ | |
| CTA type/size | 14/700, padding 12, radius 12, shadow `0 7px 16px rgba(90,68,190,.3)` | PrimaryButton default: **15/700, padding v14, radius 13, shadow .35/8/18** | ❌ | Home CTA uses full PrimaryButton metrics, not the smaller home-specific button (HomeView.swift:36) |
| CTA top margin | 14 | .top 14 | ✅ | |
| CTA action | → step 2, preserve auth/keys | createAnother(): pick=nil, go(2) | ✅ | (object-pop is physics-layer, out of scope) |
| Re-drop on enter | replay drop from ceiling | physics.dropAll() onAppear | ✅ | |

---

## StripeCover (shared) — `Sources/DesignSystem/Components.swift:202`

`StripeCover` uses a fixed `step = 8` with bar width `step/2 = 4` at every use, drawn at 45°:
- Cover well (104) spec: **8pt** stripes, **16pt** period, **135°** → impl draws 4pt/8pt/45° (half scale, mirrored diagonal). ❌
- Home (42) & AllSet (44) thumbs spec: **6pt** stripes, **12pt** period, **135°** → impl still 4pt/8pt/45°. ⚠️
StripeCover ignores the object's size when scaling stripes and uses the wrong period and diagonal direction for all three call sites.

---

## Intentional (not bugs)

- Fonts substituted SF Pro / SF Mono for Plus Jakarta Sans / IBM Plex Mono (README permits; Fonts.swift documents).
- Persistent "On device · nothing leaves your Mac" `PrivacyFooter` added on every screen — not in HTML spec, deliberate.
- Native macOS titled window instead of the HTML's fake title bar + traffic lights.
- Home backdrop blur uses `.ultraThinMaterial` (+ white 0.6 overlay) instead of `rgba(255,255,255,.94)` + `backdrop-filter: blur(10px)` — documented CSS→SwiftUI gap.
