# Fidelity Audit 4 — Physics Scene, Sheet Transition & Window

READ-ONLY audit. Spec = `design_handoff/README.md` (+ `FriendList Onboarding.dc.html` for constants).
Legend: ✅ match · ⚠️ deviation / tuning · ❌ wrong or missing · 🟦 known-intentional (not a bug).

---

## Engine settings

| Setting | Spec (Matter ref) | Implementation | File:line | Status |
|---|---|---|---|---|
| Gravity Y | 1.05 | `gravity = (0, -8)` (SpriteKit units, hand-tuned) | StageScene.swift:32 | ⚠️ tuning — can't be 1:1; verify feel |
| Walls restitution | 0.4 | 0.4 | StageScene.swift:59 | ✅ |
| Walls friction | 0.6 | 0.6 | StageScene.swift:60 | ✅ |
| Ceiling well above frame | yes | `h + 1600` + floor/left/right | StageScene.swift:52,64-67 | ✅ |
| Body restitution | 0.52 | 0.52 | PhysicsObjects.swift:36 | ✅ |
| Body friction | 0.35 | 0.35 | PhysicsObjects.swift:37 | ✅ |
| Air friction | 0.008 | `linearDamping = 0.1` (SpriteKit default reused) | PhysicsObjects.swift:38 | ⚠️ ~12× the reference feel; consider lowering |
| Spawn X inset | 70pt | `spawnInset = 70` | StageScene.swift:23,88 | ✅ |
| Spawn Y | −120…−640 above top | `height + random(120…640)` | StageScene.swift:89 | ✅ |
| Spawn angle | ±0.6 rad | `zRotation random(-0.6…0.6)` | StageScene.swift:91 | ✅ |
| Stagger | 260ms then 130ms | `0.26 + i*0.13` | StageScene.swift:77 | ✅ |
| Drag | mouse constraint, stiffness 0.18 | rigid position-follow (no spring lag) | StageScene.swift:149-159 | ⚠️ feel differs (infinite stiffness); fling OK |
| Scroll-wheel capture disabled | yes | `scrollWheel {}` empty | StageScene.swift:171 | ✅ |
| Collision shape | circle / rounded-rect chamfer min(10,h/3) | circle / plain `rectangleOf` (SKPhysicsBody has no chamfer) | PhysicsObjects.swift:69-73 | ⚠️ no rect chamfer (API limit); acceptable |

### Pop choreography (Continue)
| Aspect | Spec | Impl | Status |
|---|---|---|---|
| Selection | index % 2 == 0 (solids) | `offset % 2 == 0` (all are solids) | ✅ |
| Duration / scale | 340ms, 1 → 1.45 → 1.7 | grow 1.45 (0.17s) + 1.7 (0.17s) = 0.34s | ✅ (even split vs 55%/45% keyframe; trivial) |
| Fade | opacity → 0 | `fadeOut 0.34` | ✅ |
| Stagger | 55ms | `i * 0.055` | ✅ |
| Body removed | yes | `physicsBody = nil` | ✅ |
| Post-pop advance | 420ms then sheet drops | WelcomeView: `popEveryOther()` + `sleep(420ms)` + `advance()` | ✅ (WelcomeView.swift:74-77) |

### dropAll / re-drop
`onDropAll` → `spawnObjects()` clears & re-drops all 14 staggered from the ceiling. HomeView `.onAppear { physics.dropAll() }`. ✅ (StageScene.swift:110; HomeView.swift:16). Recreates fresh nodes rather than restoring existing bodies — net effect matches spec.

---

## Object inventory checklist (14)

| # | Object | Size ✓ | Shape ✓ | Dominant color ✓ | Notes |
|---|---|---|---|---|---|
| 1 | Vinyl | 98×98 ✅ | circle ✅ | dark disc `#211E28`, `#9B85F2` label, white spindle ✅ | |
| 2 | CD | 80×80 ✅ | circle ✅ | iridescent → tinted arcs on `#DFE4EE`, white center ✅ | conic→approx 🟦 |
| 3 | Cassette | 118×74 ✅ | rect ✅ | `#EFB63F` shell, cream window, `#3B352E` spools ✅ | |
| 4 | Headphones | 92×80 ✅ | rect ✅ | `#4B4550` band, `#5B5466` cups ✅ | |
| 5 | Gold chain | 104×24 ✅ | rect ✅ | 4 rings `#E9BE4A`/`#F0CB63` ✅ | |
| 6 | Smiley bead | 62×62 ✅ | circle ✅ | `#F4A0C0`, `#5A2C42` face ✅ | |
| 7 | Music note | 48×62 ✅ | rect ✅ | `#37333C` ✅ | |
| 8 | Star | 58×58 ✅ | rect ✅ | `#F3C63F` 5-point ✅ | |
| 9 | Heart | 52×46 ✅ | rect ✅ | `#EF6079` ✅ | |
| 10 | Guitar pick | 50×56 ✅ | rect ✅ | teal, solid `#64B7A3` mid-tone ✅ | gradient→solid 🟦 |
| 11 | Ticket stub | 118×56 ✅ | rect ✅ | `#F0E3C4` ✅ | ⚠️ **no torn/perforated edges**; "ADMIT ONE" **not rotated 90°**, 9pt Menlo vs 7pt IBM Plex Mono |
| 12 | Link preview card | 136×60 ✅ | rect ✅ | white, `#A996EE` thumb, grey bars ✅ | gradient→solid 🟦 |
| 13 | iMessage bubble | 196×46 ✅ | rect ✅ | `#1B8DFF` r23, white text + tail ✅ | |
| 14 | Jerry Garcia | 96×96 ✅ | circle ✅ | transparent head cutout, **no white ring** 🟦 | intentional per design decision — not flagged |

All 14 present. Sizes: 14/14 ✅. Shape categories: 14/14 ✅. Dominant colors: 14/14 ✅.
Only detailing deviation is Ticket (#11); Jerry (#14) is the sanctioned cutout.

---

## Sheet transition

| Aspect | Spec | Impl | File:line | Status |
|---|---|---|---|---|
| Motion | translateY(−105%) → 0 | offset `-(contentHeight+40)` → 0 (≈ −600, fully off-screen) | OnboardingContainer.swift:32 | ✅ |
| Curve / duration | cubic-bezier(.22,1.1,.36,1), 620ms | `.timingCurve(0.22,1.1,0.36,1, duration: 0.62)` | OnboardingContainer.swift:33 | ✅ |
| Width | 600pt | `Geometry.sheetWidth = 600` | Tokens.swift:88 | ✅ |
| Bottom radius | 20pt (bottom corners only) | `BottomRoundedRectangle(radius: 20)` | OnboardingContainer.swift:63; Tokens.swift:76 | ✅ |
| Shadow | 0 26px 50px −12px rgba(40,33,25,.4) | `Shadows.sheet` approx | Tokens.swift:109 | ✅ |
| Mounted for 2–8, content swaps | yes | `Group { switch step }` | OnboardingContainer.swift:48-59 | ✅ |

## Progress bar

| Aspect | Spec | Impl | File:line | Status |
|---|---|---|---|---|
| Height | 4pt strip | `.frame(height: 4)` | Components.swift:106 | ✅ |
| Track | `#EDE9E1` | `progressTrack = #EDE9E1` | Tokens.swift:56 | ✅ |
| Fill | accent, 3pt right radius | accent, `RoundedRectangle(3)` | Components.swift:100-102 | ✅ (both edges rounded; left hidden at x=0) |
| Animation | 500ms ease | `.easeInOut(0.5)` | Components.swift:103 | ✅ |
| Widths 2→8 | 16/34/50/64/80/92/100 | `[0,0,.16,.34,.50,.64,.80,.92,1.0]` | OnboardingState.swift:71 | ✅ |

## Navigation

| Aspect | Spec | Impl | Status |
|---|---|---|---|
| Linear 1→…→8 | yes | `advance()` → `min(step+1,8)` | ✅ |
| 8 → Home | yes | `goHome()` → 0 (AllSet "Back to FriendList") | ✅ |
| Back from 6 → 4 | yes | `back()` `step==6 ? 4` | ✅ (OnboardingState.swift:92) |
| Home → 2 | yes | `createAnother()` → go(2) | ✅ |
| "Create a new one" pops half | popHalf() then go(2) @420ms | **only clears pick + go(2)** — no pop | ❌ missing (OnboardingState.swift:113-116) |

---

## Window

| Aspect | Spec | Impl | File:line | Status |
|---|---|---|---|---|
| Content size | 760×560 fixed | 760×560, `.windowResizability(.contentSize)` | FriendListApp.swift:8,12-13 | ✅ |
| Title bar | `.titled`, centered "FriendList" 12/600 `#8B8377` on `#F3F0EA` | `.windowStyle(.hiddenTitleBar)` — **no title bar / no centered title**; `titleBar`/`titleText` tokens unused | FriendListApp.swift:11; Tokens.swift:42-43 | ⚠️ hiddenTitleBar removes the bar entirely (spec wanted native titled bar, not hidden) |
| Stage height | 760×524 (below 36pt bar) | stage `524` but window content is full `560` (no bar) → ~36pt gap at bottom | Tokens.swift:87; PhysicsStageView.swift:23 | ⚠️ 36pt stage/content mismatch consequence of hiddenTitleBar |
| Corner radius | 14pt | `Radii.window=14` defined but native window uses system rounding | Tokens.swift:74 | ⚠️ token unapplied (native window) |
| Non-resizable | yes | contentSize + fixed frame | FriendListApp.swift:12 | ✅ |
| Body gradient | `#FDFBF7`→`#F4F0E8` | `deskGradient` | Tokens.swift:59-62 | ✅ |

🟦 Native macOS title bar substituted for the HTML's fake 36pt bar is sanctioned — but see the hiddenTitleBar note: the bar is *removed*, not natively rendered.
