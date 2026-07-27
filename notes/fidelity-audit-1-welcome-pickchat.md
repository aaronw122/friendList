# Fidelity Audit — Welcome (step 1) & Pick a group chat (step 2)

READ-ONLY audit. Spec: `design_handoff/README.md` (authoritative) cross-checked against `design_handoff/FriendList Onboarding.dc.html`. Implementation: `Sources/DesignSystem/*` + `Sources/Onboarding/Screens/{WelcomeView,PickChatView}.swift`.

Legend: ✅ match · ⚠️ minor · ❌ deviation

---

## Screen 1 — Welcome (`WelcomeView.swift`)

| Element | Spec | Implemented | Verdict | Note |
|---|---|---|---|---|
| Wordmark copy | "FriendList" | "FriendList" (`:35`) | ✅ | README authoritative says "FriendList"; the HTML prototype renders lowercase "friendList" — README wins. |
| Wordmark font | 60pt / 800 | `ui(60, 800)` → heavy | ✅ | SF substitution intentional. |
| Wordmark tracking | −0.035em | `tracking(-0.035*60)` = −2.1 | ✅ | |
| Wordmark color | `#1D1B18` | `Palette.ink` #1D1B18 | ✅ | |
| Wordmark shadow | `0 2px 0 rgba(255,255,255,.9)` | radius 0, y 2, white 0.9 | ✅ | |
| Subhead copy | "Turn a group chat's songs into a Spotify playlist — and keep it growing." | exact (`:42`) | ✅ | HTML prototype lowercases "turn"; README authoritative. |
| Subhead font | 17pt / 500 | `ui(17, 500)` | ✅ | |
| **Subhead color** | **`#5D574E`** | **`Palette.body` #6B6459** (`:44`) | ❌ | Wrong token — implemented color is lighter/warmer. #5D574E is not defined in Palette. |
| Subhead max width | 400pt | `frame(maxWidth: 400)` | ✅ | |
| Subhead line-height | 1.45 | `lineSpacing(7)` ≈ 24pt | ✅ | Close approximation (1.45×17≈24.7). |
| Subhead gap | 20pt below wordmark | `.padding(.top, 20)` | ✅ | |
| Kicker copy | "ALWAYS LISTENING · NEVER UPLOADING" | exact (`:49`) | ✅ | Not present in HTML prototype; README authoritative. |
| Kicker font | IBM Plex Mono 12pt, uppercase | `mono(12)` + `.uppercase` | ✅ | |
| Kicker tracking | .06em | `tracking(0.06*12)` | ✅ | |
| **Kicker color** | **`#9A9184`** | **`Palette.faint` #A79E90** (`:53`) | ❌ | Wrong token — #9A9184 not in Palette. |
| Kicker gap | 10pt below subhead | `.padding(.top, 10)` | ✅ | |
| CTA copy | "Continue" | "Continue" (`:62`) | ✅ | |
| CTA font | 15pt / 700 white | `ui(15,700)` white | ✅ | |
| CTA fill | `#9B85F2` | `Palette.accent` | ✅ | |
| CTA padding | 14×44 | 14 vert / 44 horiz | ✅ | |
| CTA radius | 13pt | `Radii.button` 13 | ✅ | |
| CTA shadow | `0 8px 18px rgba(90,68,190,.35)` | `5A44BE`@.35, r9, y8 | ✅ | Blur/2 convention. |
| CTA inner highlight/shade | inset top white .35 / bottom black .12 | gradient overlay .35/.12 | ✅ | |
| CTA hover/active | lift −2 / press +1 | −2 / +1 offsets | ✅ | |
| CTA letter-spacing | (HTML button uses −.01em; README unspecified) | none | ⚠️ | HTML renders Continue at tracking −0.01em; README does not list it, so cosmetic only. |
| CTA caption copy | "or toss the stuff around a bit first" | exact (`:64`) | ✅ | Not in HTML prototype; README authoritative. |
| CTA caption font/color | 11.5pt, `#A79E90` | `ui(11.5)` + `Palette.faint` #A79E90 | ✅ | |
| CTA caption gap | 10pt below button | `.padding(.top, 10)` | ✅ | |
| Layout anchors | text 87pt from top; CTA 212pt from bottom (absolute) | top `Spacer 87`, bottom `Spacer 96` + flexible middle | ⚠️ | CTA is not truly bottom-anchored at 212pt; approximated with a fixed 96pt bottom spacer (comment admits the estimate). May drift from 212pt depending on CTA-group height. |

---

## Screen 2 — Pick a group chat (`PickChatView.swift`)

| Element | Spec | Implemented | Verdict | Note |
|---|---|---|---|---|
| Privacy card bg | `#F4F1FB` | `Palette.tint` #F4F1FB | ✅ | |
| Privacy card radius | 12pt | 12 | ✅ | |
| Privacy card padding | 12×14 | 12 vert / 14 horiz | ✅ | |
| Privacy card bottom margin | 20pt | `.padding(.bottom, 20)` | ✅ | |
| Privacy icon | 18×18, radius 5, `#9B85F2`, inset bottom shade | 18×18, r5, accent, black .14 gradient | ✅ | |
| Privacy icon gap | 10pt | HStack spacing 10 | ✅ | |
| Privacy lead copy | "Everything stays on your Mac." | exact, bold (`:66`) | ✅ | |
| Privacy body copy | "FriendList reads Messages locally to spot song links. Your texts are never uploaded, stored, or seen by anyone — including us." | exact (`:69`) | ✅ | |
| Privacy text | 12.5pt, line-height 1.5, `#4A4459` | `ui(12.5)`, lineSpacing 6, `privacyText` #4A4459 | ✅ | |
| Privacy lead color | `#2E2840` bold | `privacyLead` #2E2840, 700 | ✅ | |
| Heading copy | "Pick a group chat" | exact (`:16`) | ✅ | |
| Heading font/color | 26pt / 800 / −0.03em / `#1D1B18` | `ui(26,800)`, tracking −0.03×26, `Palette.ink` | ✅ | |
| Subhead copy | "Just one to start. You can add more chats whenever you like." | exact (`:21`) | ✅ | |
| Subhead font/color | 14pt, `#6B6459`, 7pt below | `ui(14)`, `Palette.body` #6B6459, `.top 7` | ✅ | |
| Permission border | dashed 1.5pt `#DED8CC`, radius 14 | dashed 1.5pt **`Palette.line` #EAE5DB** (`:106`) | ❌ | Wrong border color — spec is #DED8CC (confirmed in HTML). Radius 14 & dash ok. |
| Permission padding | 26pt | `.padding(26)` | ✅ | |
| **Permission title color** | 14pt / 600, **`#3A352E`** | `ui(14,600)`, **`Palette.ink` #1D1B18** (`:90`) | ❌ | Too dark; spec #3A352E. |
| Permission title copy | "FriendList needs Full Disk Access to read Messages" | exact | ✅ | |
| Permission sub | 12.5pt `#8A8275`, "macOS will ask you to confirm in System Settings." | `ui(12.5)`, `Palette.muted` #8A8275, exact copy | ✅ | |
| **Grant access button** | 14pt / 700, padding **11×24**, radius **11**, shadow `0 6px 14px rgba(90,68,190,.3)` | `PrimaryButton` → **15pt**, padding **14×44**, radius **13**, shadow .35 (`:99`) | ❌ | Reuses PrimaryButton, so font size, padding, radius and shadow all differ from the smaller permission-button spec. |
| Grant access copy | "Grant access" | exact | ✅ | |
| Chat list border | 1pt `#EAE5DB` | `Palette.line`, 1pt | ✅ | |
| Chat list radius | 13pt | 13 | ✅ | |
| Chat list max height | 184pt, scrolls | `frame(maxHeight:184)` + ScrollView | ✅ | |
| Row padding | 11×14 | 11 vert / 14 horiz | ✅ | |
| Row divider | 1pt `#F2EEE6` | `Palette.divider` #F2EEE6, 1pt | ✅ | |
| Row gap | 11pt | HStack spacing 11 | ✅ | |
| Selected row bg | `#F4F1FB` | `Palette.tint` | ✅ | |
| Radio unselected | 15×15, 2pt border `#D8D2C6` | 15×15, 2pt #D8D2C6 | ✅ | |
| Radio selected | 5pt border accent | 5pt accent | ✅ | |
| Row name | 14pt / 700 / `#2A2622` | `ui(14,700)`, `rowName` #2A2622 | ✅ | |
| Row count | IBM Plex Mono 11pt `#A79E90`, right-aligned | `mono(11)`, `Palette.faint`, right via Spacer | ✅ | "{n} links" format matches sample data. |
| CTA | "Continue", bottom-right, disabled until selection | `SheetFooter` primary, `enabled: pick != nil` | ✅ | |

---

## Intentional (not bugs)
- Fonts use SF Pro / SF Mono instead of Plus Jakarta Sans / IBM Plex Mono — README permits substitution (`Fonts.swift`).
- Persistent "On device · nothing leaves your Mac" privacy footer (`PrivacyFooter` in `Components.swift`) — added from the plan, not the handoff.
- Welcome prerequisite heads-up line already removed.
- Wordmark/subhead casing: HTML prototype renders lowercase ("friendList" / "turn…"); README (authoritative) uses title case, which the implementation follows.
