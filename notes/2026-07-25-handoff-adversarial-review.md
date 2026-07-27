# Adversarial design-handoff review

### 1. CONTRADICTIONS between the handoff and PLAN.md

1. **The OAuth redirect URI is inconsistent, and the handoff's value is wrong even under the plan's architecture.** The handoff tells the user to register and the app to use `friendlist://callback` (README lines 97–99, 119; HTML lines 218–221). PLAN specifies `friendlist://auth-callback` in the setup table and auth architecture (PLAN lines 63, 68, 174). Exact matching is mandatory at app registration, authorization, and token exchange. **Winner: PLAN**, because it is explicitly authoritative and repeats one value across UX and implementation. However, neither value is safe in July 2026: Spotify's current redirect rules require HTTPS except for an explicit loopback IP literal, and its examples no longer include custom schemes ([Spotify Redirect URIs](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri)). The team must validate a supported macOS callback strategy—probably a loopback listener such as `http://127.0.0.1:<port>/callback`—before freezing either string. Shipping either document literally risks an OAuth hard failure.

2. **The handoff asks for the wrong scopes.** It mandates `playlist-modify-private playlist-modify-public ugc-image-upload` (README line 119). PLAN mandates `playlist-modify-private user-library-read playlist-read-private` and explicitly says to drop public modification because all playlists are private (PLAN line 181). **Winner: PLAN.** `playlist-modify-public` is needless privilege. `playlist-read-private` is required for private-playlist enumeration/inspection, and `user-library-read` is required by PLAN's Liked Songs dedup (PLAN lines 210–220). `ugc-image-upload` is only justified if custom covers remain in scope; it is absent from PLAN's five-screen MVP and should be conditional, requested only when that feature actually ships. Spotify's scope reference confirms the privilege boundaries ([Spotify Scopes](https://developer.spotify.com/documentation/web-api/concepts/scopes)).

3. **The handoff's permission explanation is materially false.** Its OAuth card says the app can “Create and edit your playlists,” “Search the Spotify catalog,” and “Nothing else — no listening history, no following” (README lines 114–117; HTML lines 253–258). PLAN requires reading private playlists and Liked Songs (PLAN lines 181, 210–220). **Winner: PLAN.** The consent copy must disclose private-playlist and saved-library reads. “Search the Spotify catalog” is not a scope and obscures the permissions that actually matter.

4. **The handoff invents a nine-view product flow where PLAN specifies five screens.** Handoff navigation is Welcome → Pick chat → developer keys → OAuth explainer → scanning → customize → creating → all set → Home (README lines 41–181, 241–247). PLAN says exactly five screens: Welcome → Pick chat/FDA/translocation → Spotify setup/connect → Import → Done (PLAN lines 37–80, 244–245). **Winner: PLAN.** Extra visual states can exist inside those five product screens, but the handoff turns loader phases and an unplanned customization feature into numbered onboarding stages, creating extra back-navigation, persistence, analytics, accessibility, and recovery obligations.

5. **The handoff omits PLAN's persistent privacy affordance.** PLAN requires an “On device · nothing leaves your Mac” footer with a lock glyph on every screen (PLAN line 39). Neither README's per-screen specs nor the HTML contains it. The handoff only has a privacy card on chat selection and a welcome kicker claimed in README but missing from HTML. **Winner: PLAN**, because repeated reassurance is an explicit onboarding requirement.

6. **The handoff hides prerequisite costs until after Full Disk Access.** PLAN requires the Welcome screen to warn that setup needs a Spotify account, developer-app creation, and Premium before anything invasive (PLAN line 46). The handoff Welcome contains none of those facts (README lines 43–59; HTML lines 148–157); Premium is absent everywhere. **Winner: PLAN.** Asking for FDA and only later revealing a paid-account requirement is a trust-breaking funnel defect.

7. **The move-to-`/Applications` / app-translocation gate is completely missing.** PLAN calls it the “very first gate (before FDA)” and explains move-and-relaunch (PLAN lines 49–50, 128, 263–267). Handoff step 2 begins directly with FDA and chat selection (README lines 63–85). **Winner: PLAN.** An FDA grant or LaunchAgent registration attached to a quarantined/translocated path can break after relaunch or login.

8. **FDA relaunch survival is missing.** PLAN requires a persisted onboarding marker and reactivation at the picker after macOS “Quit & Reopen” (PLAN lines 51, 126–129). Handoff state is ephemeral (`step`, `access`, `pick`) and specifies no persistence or resume semantics (README lines 255–268; HTML line 363). **Winner: PLAN.** Without this, the most likely permission flow dumps the user back at Welcome and may repeat setup.

9. **The chat picker contradicts PLAN's required information architecture.** Handoff says “chat name only — no avatars, no member lists,” displays only a link count, and presents sample group chats (README lines 76–84). PLAN requires groups first, DMs below, plus display name, participant/message counts, and “N Spotify links found” preview (PLAN line 52). **Winner: PLAN**, unless product explicitly de-scopes DMs and participant/message counts. The handoff has no sectioning, no empty names, no indistinguishable-chat treatment, and no evidence that its single count means the required Spotify pre-scan.

10. **The handoff performs playlist creation later and differently.** It states “Nothing exists on Spotify yet” at Customize and creates only at step 7 (README lines 140–165). PLAN says auth success creates the private playlist and then Import scans/adds into it (PLAN lines 69–74). **Winner: PLAN**, because the backfill architecture and milestone definition assume a target playlist during import. If product wants pre-creation customization, PLAN must be changed deliberately, including resumability and orphan cleanup.

11. **The handoff introduces playlist cover upload without plan authority.** README adds a custom cover picker, JPEG constraints, upload scope, and an uploading phase (lines 140–155, 159–164). PLAN only says the playlist cover uses the brand mark (line 80) and does not scope a user cover picker or `ugc-image-upload`. **Winner: PLAN.** Remove user-uploaded covers from MVP or formally add the feature, validation, permissions, image processing, failures, and accessibility to PLAN.

12. **The import UI omits PLAN's actual progress and output.** Handoff scanning reports only generic status, a percent, and “N songs found” (README lines 123–136). PLAN requires messages scanned, Spotify links found, tracks added, duplicates skipped, and YouTube links counted; it must be batched, rate-limit-aware, and resumable (PLAN lines 71–74, 137–141, 241–242). **Winner: PLAN.** The handoff does not design the most informative or operationally important import states.

13. **The completion state overpromises latency and omits launcher registration.** Handoff promises each new song lands “within a minute” (README line 174; HTML line 539). PLAN's intended live poll is about 10 seconds and Done must register/verify the LaunchAgent and handle approval (PLAN lines 78, 104, 130–134). **Winner: PLAN.** The completion screen cannot claim ongoing monitoring until registration and status verification succeed.

14. **The handoff's Home window conflicts with the menubar product shape.** It specifies a persistent fixed 760×560 titled window and a Home panel whenever the window opens (README lines 16, 25–37, 181–195). PLAN specifies a menubar-only `LSUIElement` app with no Dock icon after setup and `MenuBarExtra` as the steady-state control surface (PLAN lines 7–10, 88–103, 125–135). **Winner: PLAN.** A separate settings/status window may exist, but calling this full window “Home” invents an unplanned application shell.

15. **The handoff does not design the required post-onboarding controls.** Home exposes only playlists and “Create a new one” (README lines 187–195). PLAN requires status, pause/resume, open playlist, add chat, Quit with unregister behavior, and attention/recovery actions (PLAN lines 101–103, 132–135, 193–195). **Winner: PLAN.** The proposed Home is decorative, not an operable menubar utility.

16. **The default naming diverges.** Handoff defaults playlist name to the raw chat name (README line 150). PLAN's example default is `🎵 <Chat Name>` (PLAN line 69). **Winner: PLAN** as authoritative, though this is a copy decision that should be frozen once in shared product requirements.

17. **The privacy claim is broader than PLAN can support.** Handoff says texts are “never uploaded, stored, or seen by anyone” (README line 72). PLAN more precisely says message content is read, matched, and discarded, while track IDs/ISRCs, chat-to-playlist mappings, and retry records are persisted (PLAN lines 255–259). **Winner: PLAN.** “Texts are never stored” is defensible only if attributed-body decoding, logs, crashes, retry state, and diagnostics never persist message content; the handoff gives engineering no constraints to ensure that.

18. **The current Spotify API has moved underneath both documents.** PLAN still specifies removed/renamed Development Mode endpoints such as `POST /v1/users/{me}/playlists`, `/playlists/{id}/tracks`, batch `GET /v1/tracks?ids=`, and `/me/tracks/contains` (PLAN lines 139, 179–180, 212–217, 238). Spotify's February 2026 migration requires `/me/playlists`, `/playlists/{id}/items`, individual track fetches, and `/me/library/contains` ([Spotify February 2026 migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)). **Winner: neither.** This is not merely a handoff discrepancy; PLAN must be updated before the UI can truthfully describe progress, dedup, batching, or feasibility.

### 2. SPOTIFY DEVELOPER ACCOUNT ONBOARDING GAPS (single most important section)

The three-step handoff is not a usable set of instructions for a real first-time user. It drops the user into a changing developer dashboard, omits required choices, requests a secret the native app should never need, and supplies a redirect URI Spotify's current rules appear to reject.

1. **No Spotify account prerequisite or login instruction.** “Open the Spotify developer dashboard and hit Create app” (README line 97) assumes an authenticated account. The flow must say: have or create a Spotify account, sign in to the dashboard using the same account intended to own and authorize the app, and resolve any account verification challenge.

2. **No Premium gate.** The handoff never says the app owner needs active Premium. Spotify states that Development Mode apps require the owner to maintain Premium; if it lapses, the app stops working ([Spotify February 2026 migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide)). This must appear on Welcome and again beside dashboard setup. A Free user should not grant FDA before learning they cannot complete setup.

3. **No developer Terms step.** The handoff does not tell the user to accept Spotify's Developer Terms or tick the required terms checkbox. Spotify's app guide explicitly requires the Developer Terms checkbox before creation ([Spotify Apps](https://developer.spotify.com/documentation/web-api/concepts/apps)).

4. **The create-app form is grossly underspecified.** “Name it anything” is insufficient. The UX must list, in the order actually presented by the dashboard:
   - App name: exact recommended value, e.g. `friendList`.
   - App description: exact safe value, e.g. `personal use`.
   - Website: say whether it is required in the current form and provide an acceptable exact value or explicit “leave blank.” Spotify's app guide describes adding a website/domain in Settings.
   - Redirect URI: one exact supported value and where to add it.
   - APIs/SDKs: select **Web API**, if that checkbox is present in the current dashboard.
   - Developer Terms checkbox.
   - Create/Save action.

5. **No post-create Settings path.** The handoff says “Copy your two keys over” but never says where they are. PLAN correctly says to open the new app's **Settings** and copy the Client ID (PLAN line 67). Spotify's app guide distinguishes app overview, Settings/Edit Settings, Client ID, Client Secret, Website, Redirect URIs, and Save. The handoff must name the actual navigation and acknowledge dashboard labels may be “Settings” or “Edit Settings.”

6. **It does not tell the user to save the redirect URI.** Copying a string into a field is not registration. The flow needs an explicit add/confirm action if the dashboard uses a list control, acceptance of terms, then **Save**, followed by an “I've saved it” checkpoint. PLAN already requires this (lines 57–67).

7. **The redirect URI is both inconsistent and likely obsolete.** The handoff supplies `friendlist://callback`; PLAN supplies `friendlist://auth-callback`. Current Spotify documentation requires HTTPS except explicit loopback IP literals and exact equality across registration, authorization, and token exchange ([Spotify Redirect URIs](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri); [Spotify PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow)). Before writing user instructions, engineering must prove which macOS callback Spotify accepts today. If loopback is required, the dashboard instruction and `ASWebAuthenticationSession` architecture must both change.

8. **Collecting Client Secret is a fundamental security and architecture error.** Handoff step 3 requests “Client ID” and “Client secret,” stores the secret in Keychain, and models it as app state (README lines 99, 102, 262–264; HTML lines 228–231, 363). PLAN uses Authorization Code + PKCE and BYO **client_id** only (PLAN lines 67–68, 174–178). Spotify explicitly recommends PKCE for desktop/mobile contexts where a secret cannot be safely stored; its authorization comparison says PKCE requires no secret, and its token request uses `client_id` plus `code_verifier`, not a secret ([Spotify Authorization](https://developer.spotify.com/documentation/web-api/concepts/authorization); [Spotify PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow)). **Delete the Client Secret field, state, copy, storage requirement, and validation.** Keychain does not turn a secret distributed to an end-user native client into a confidential server credential. Asking users to reveal it expands attack surface for no benefit and contradicts the chosen flow.

9. **No Client ID validation or completion rule.** The prototype enables “Connect Spotify” even with both credential fields empty because only chat selection affects `canNext` (HTML lines 515–516, 549). The production UX needs whitespace trimming, expected-format validation, required-state feedback, paste handling, and a disabled CTA until a plausible Client ID exists.

10. **No instruction that app owner and authorizing user must match.** PLAN identifies this as a risk: the developer-app owner must be the same Premium account used to authenticate (PLAN line 287). The handoff should say this directly before opening authorization.

11. **No Development Mode explanation.** A newly created app defaults to Development Mode, with user and quota restrictions ([Spotify Apps](https://developer.spotify.com/documentation/web-api/concepts/apps)). The user needs to know this is expected and that Friend List is for their personal, non-commercial use—not to request Extended Quota Mode.

12. **The user-cap story is missing and the product rationale is stale.** PLAN says BYO client IDs avoid a shared cap/allowlist (lines 54, 175), while the handoff vaguely says Spotify makes small apps use user-created keys. Spotify's 2026 rules include a per-app authorized-user cap, while the July 23, 2026 update raised the per-developer Client ID limit to 25 and made quotas shared per developer account ([Spotify February 2026 migration guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide); [Spotify July 2026 quota update](https://developer.spotify.com/blog/2026-07-23-web-api-quota-updates)). For the intended self-owned app, the user generally should not need to add anyone else. If Spotify requires the owner to appear in an allowlist in the current dashboard, the handoff must show the exact Users/User Management steps; if not, it must not invent them. This requires a live dashboard walkthrough before copy is frozen.

13. **No handling for users who already have an app or hit account limits.** The flow assumes “Create app” is always available. It needs branches for reusing an existing compatible Web API app, an existing redirect URI, account/app quota errors, and an unavailable Create button. Spotify currently says up to 25 apps per developer account, but quota is shared across them ([Spotify Apps](https://developer.spotify.com/documentation/web-api/concepts/apps); [Spotify July 2026 quota update](https://developer.spotify.com/blog/2026-07-23-web-api-quota-updates)).

14. **No confirmation that required endpoints work in fresh Development Mode.** PLAN itself marks playlist writes as an existential, unverified 2025–26 risk and gates M2 on a live write (PLAN lines 238–239, 282–284). The handoff confidently promises playlist creation before this has been proven. The UX should not be finalized until a fresh app can create a private playlist, add items, read owned private playlist contents, read/check the library as designed, refresh a PKCE token, and upload a cover if that feature survives.

15. **The described API behavior is stale.** The handoff says “Search the Spotify catalog,” while the plan relies heavily on batch track and playlist operations. Development Mode changed in February 2026: playlist `/tracks` endpoints became `/items`, batch track fetch was removed, and library contains moved to `/me/library/contains`. These changes affect rate, timing, progress labels, error frequency, and possibly requested scopes. The setup and consent explanation cannot be trusted until PLAN's API inventory is migrated.

16. **No support escape hatch.** The hardest onboarding step has no “I already have an app,” “Where is my Client ID?”, “Spotify rejected the redirect URI,” “I don't see Web API,” “I have a Free account,” or “Start over” state. A three-minute claim without recovery UI is irresponsible.

### 3. TECHNICAL FEASIBILITY / SwiftUI recreation risks

1. **Matter.js values are not a SpriteKit specification.** Gravity `1.05`, air friction `0.008`, restitution `0.52`, mouse stiffness `0.18`, and Matter's chamfered rectangle bodies (README lines 202–215) have no one-to-one SpriteKit units. The handoff supplies no reference video, sampled trajectories, frame rate, solver iteration settings, density/mass, linear/angular damping conversion, collision bitmasks, z-order, sleep behavior, or acceptance tolerances. “Reference for feel” is not testable.

2. **Visual geometry and collision geometry visibly disagree.** Star, heart, headphones, chain, note, guitar pick, torn ticket, and bubble tail are all simulated as rectangles (README lines 214–232; HTML lines 401–410). That means empty transparent corners collide. Users dragging a star or chain will see collisions before artwork touches. The handoff must explicitly accept this artifact or provide compound/alpha-hull physics bodies.

3. **The pop choreography is underspecified for SpriteKit/SwiftUI ownership.** Objects are SpriteKit nodes, but README describes DOM-like removal, scale, opacity, stagger, and later restoration (lines 59, 185, 194). It does not define whether the animation runs in SpriteKit actions, SwiftUI overlays, or pre-rendered textures; how a dragged object behaves when selected for popping; or how input is cancelled safely.

4. **The sheet transition is not reproducible from `.spring` alone.** README gives CSS cubic-bezier `(.22,1.1,.36,1)` over 620 ms but recommends SwiftUI `.transition(.move(edge:.top))` “with a spring” (lines 15, 245). A cubic Bézier with a control point over 1 is not equivalent to SwiftUI's spring parameters. Specify `response`, `dampingFraction`, `blendDuration`, initial velocity, clipping, final overshoot, reduced-motion behavior, and whether content swaps animate.

5. **The sheet's actual origin is unexplained and suspect.** HTML positions it at `top:-29px` inside the 524-point stage (HTML line 159), while README says it slides from the top edge and is 600 points wide (lines 245–247). That offset effectively tucks the sheet under the title bar/progress area and changes visible height. Native window/title-bar safe-area behavior is not specified.

6. **Custom shapes need actual assets or mathematical paths.** The star and torn ticket are CSS polygons; the bubble tail is CSS `clip-path:path`; the heart is composed from rotated divs (HTML lines 86–103, 120–123). “Use SwiftUI Path/Shape” is not enough. Provide normalized path data, fill rules, stroke alignment, antialiasing expectations, asset scale, and visual snapshots. The README calls out a “guitar pick” but does not mention it among known shape gaps.

7. **The Jerry Garcia asset is not production-ready by specification.** HTML references `uploads/Cartoony SVG Request Jul 25 2026.png` with a crop larger than its 96-point circle (lines 116–118). README merely calls it an image asset (line 233). There is no provenance, rights/license, required pixel dimensions, color profile, @2x/@3x strategy, accessibility label, or fallback if missing.

8. **Blur fidelity is unbounded.** Home uses CSS `backdrop-filter: blur(10px)` over a dynamic SpriteKit scene (README line 189; HTML line 127). SwiftUI materials and `NSVisualEffectView` do not map to a numeric CSS blur and may not sample `SpriteView` as expected. Specify material/blending mode, vibrancy, active/inactive window behavior, performance target, and fallback.

9. **Inset shadows do not have a native SwiftUI equivalent.** Buttons, badge, cassette, vinyl, and other objects rely heavily on multiple outer and inset shadows. The known-gaps section admits custom overlays may be needed, but does not supply layer recipes or pixel references. Simple `.shadow` recreation will look wrong.

10. **The fixed window is underdesigned for macOS.** “760×560 content area,” 36-point title bar, 14-point corner radius, and standard traffic lights (README lines 25–37) do not specify whether content size excludes the title bar, full-size content view behavior, toolbar/title visibility, backing scale, window restoration, centering, multi-display placement, zoom/minimize behavior, or what becomes resizable after onboarding. AppKit owns traffic-light positions and window corners; the HTML's geometry cannot be copied literally.

11. **The window model conflicts with a menubar-only lifecycle.** PLAN uses `LSUIElement`, `MenuBarExtra`, headless launch, and an onboarding `WindowGroup`. The handoff never defines window activation from the menubar, closing without quitting, reopening, hiding on background launch, or ensuring a LaunchAgent-started process does not flash a 760×560 window.

12. **Custom URL scheme registration instructions are incomplete and probably obsolete.** README says add `friendlist://callback` as a custom scheme in `Info.plist` (line 119). `CFBundleURLSchemes` contains only `friendlist`, not a full URI; `ASWebAuthenticationSession(callbackURLScheme:)` receives the bare scheme. More importantly, current Spotify redirect policy appears to require HTTPS/loopback. No engineer should implement the scheme until auth feasibility is re-proven.

13. **Keychain requirements are dangerously shallow.** “Refresh token → Keychain” and “client secret → Keychain” do not define service/account keys, accessibility class, update semantics, migration, deletion on Client ID change, handling duplicate items, locked Keychain, token rotation, or corruption. PLAN requires serialized refresh and atomic replacement of rotating refresh tokens (lines 176–178); the handoff does not.

14. **Font delivery is unresolved.** README demands Plus Jakarta Sans and IBM Plex Mono for pixel accuracy but says SF Pro/SF Mono substitution is acceptable (line 297). Those are visibly different decisions. The HTML loads Google Fonts over the network (lines 12–15), which violates PLAN's “network egress is only Spotify” privacy rule (PLAN line 256) if copied. The engineer needs bundled font files, exact versions, OFL license texts/attribution, registered PostScript names, supported weights, fallback metrics, and a firm decision about system versus bundled fonts.

15. **No accessibility specification exists.** Tiny 7–12 point text, color-only radio states and sync dots, draggable decorative physics, custom buttons, fake logo art, automatic transitions, and indefinite animations have no VoiceOver ordering, labels, keyboard traversal, focus restoration, reduced motion, increase contrast, differentiate-without-color, or hit-target requirements. A native recreation could be pixel-faithful and unusable.

16. **Performance and compositing budgets are absent.** Fourteen textured physics bodies, continuous SpriteKit simulation, draggable input, SwiftUI sheet updates, material blur, shadows, and pulsing/spinning animations run simultaneously. There are no CPU/GPU/energy targets, inactive-window pausing rules, refresh-rate assumptions, or behavior when the menubar app is headless.

17. **Image upload feasibility is incomplete.** Restricting `NSOpenPanel` to JPEG and enforcing ≤256 KB (README line 155) does not solve EXIF orientation, color space, square crop, resize/compression, progressive JPEG, MIME/UTType validation, security-scoped URLs, cancellation, or upload retry. The feature should not ship from this handoff.

18. **No deterministic fidelity baseline exists.** “Pixel-accurate” (README line 21) is impossible to approve without screenshots per screen/state, reference macOS version, display scale, font files, animation recordings, and tolerance criteria. The HTML itself is stateful and random, so it cannot serve as a stable golden master.

### 4. INTERNAL INCONSISTENCIES in the handoff itself

1. **README claims UI that the HTML does not render.** Welcome specifies kicker “ALWAYS LISTENING · NEVER UPLOADING” and CTA caption “or toss the stuff around a bit first” (README lines 55, 57). HTML Welcome renders neither; it has only wordmark, subhead, and Continue (HTML lines 148–157).

2. **Brand casing is inconsistent.** README wordmark is “FriendList” (line 53), overview uses FriendList, HTML hero renders `friendList` (line 150), and PLAN uses “friend list.” This is visible brand copy, not an implementation detail.

3. **The “complete first-run experience” claim is false.** README line 6 calls it complete, while line 251 merely names five error paths without designing them. Translocation, relaunch recovery, Premium, launcher approval, token recovery, and resumability are absent.

4. **Credential gating is broken.** README implies two keys are required, but the prototype's `canNext` checks only chat selection (HTML lines 515–516). “Connect Spotify” advances with blank Client ID and Client Secret (lines 239, 549).

5. **The fake FDA interaction contradicts its own copy.** The screen says “macOS will ask you to confirm in System Settings” (README line 75; HTML line 182), but `onGrant` simply flips `access: true` without opening settings, polling, relaunching, or failing (HTML line 548). This prototype does not demonstrate the intended behavior.

6. **“Everything stays on your Mac” conflicts with obvious Spotify network use.** The privacy card says “Everything stays on your Mac” (README line 72), while the product necessarily sends track identifiers, playlist metadata, cover art, and OAuth requests to Spotify. PLAN's narrower formulation—conversation content stays local and network calls go only to Spotify—is accurate. Current copy is an overclaim.

7. **“Your texts are never … seen by anyone” is nonsensical in context.** Other chat participants already see texts, and Spotify receives extracted track identifiers. The intended claim is that Friend List's operator has no server and does not receive message content. Copy should say that precisely.

8. **The OAuth permissions card does not match the declared scopes.** README declares public/private playlist modification and image upload (line 119), but the card mentions neither public playlists nor cover-image upload and invents “Search the Spotify catalog” (lines 115–117). Users cannot understand what they will consent to.

9. **The custom-cover affordance is a no-op.** README presents “Use your own” as a real `NSOpenPanel` feature (line 155), but HTML wires it to `onNoop` (HTML lines 304, 556). The prototype therefore cannot demonstrate selected, invalid, processing, uploading, cancelled, or failed-cover states.

10. **“Open in Spotify” is also a no-op.** README specifies a primary action (line 176), but HTML prevents default and performs nothing (lines 337, 556). The adjacent fake playlist URL always points to Spotify's generic root, not a playlist (line 333).

11. **The restart state is dead code and destructive.** HTML defines `onRestart` but exposes no control using it (line 559). If invoked, it resets FDA to false despite FDA being an OS permission, proving the state model conflates detected external state with transient UI state.

12. **Progress percentages imply a false unit.** Seven sheet states use 16, 34, 50, 64, 80, 92, 100% (README line 247). These are neither equal increments nor mapped to five product steps. The bar advances during two passive loaders and customization, so “progress” represents arbitrary prototype pages rather than user completion or work completion.

13. **There are two progress bars with incompatible meanings.** The sheet-top bar reports navigation step while scanning/creating screens contain separate task percentages (README lines 132, 247). On scanning, the outer bar is fixed at 64% while the inner reaches 100%, then navigation jumps to 80%. The handoff never explains this dual model.

14. **Back navigation is logically corrupt.** Customize Back jumps to OAuth, “skipping the scan” (README line 153). Authorizing again and then continuing enters Scan because step 4's Next always goes to step 5 (HTML lines 549–550). It does not skip the scan. The README claim and actual prototype behavior directly disagree.

15. **Back can trigger unnecessary reauthorization.** After a successful scan, returning to OAuth discards the fact that authorization already succeeded. There is no “connected” state, token state, or alternate CTA. The user can be sent through consent repeatedly.

16. **Home → new playlist preserves credentials only in prose.** README says it preserves Spotify auth and keys (line 194), but the prototype has no auth/token state at all; it merely leaves `cid` and `sec` strings in memory (HTML lines 363, 558). Closing or relaunching loses everything.

17. **Home's “SYNCING” state is unconditional and dishonest.** It always renders “syncing” (HTML line 130), even though the prototype has no launcher registration, scanner, token, network, paused state, error state, or last-success timestamp. README designs only a green pulsing dot (lines 190–191), never unhealthy or idle states.

18. **README calls row names weight 700; HTML uses 600.** Compare README line 78 with HTML line 192. This violates the claimed final, pixel-accurate typography.

19. **README says 14 objects and the HTML has 14, but pop indexing is unstable relative to the prose.** “Every other solid object (index % 2 == 0)” (README line 59) does not define whether index refers to full inventory, filtered visible inventory, or non-floating objects. HTML filters by `float`, though no current object uses `data-float`, and the optional bubble changes the item set before the “solid” list is formed (HTML lines 395–412, 464–479). The exact popped objects can change with a design toggle.

20. **The physics prose and code retain abandoned balloon machinery.** README says balloons were cut and “nothing floats” (line 235), but HTML retains `data-float`, special restitution/damping/density, and lift forces (lines 404–429). Dead behavioral paths undermine the prototype as a canonical reference.

21. **The sheet width description does not match placement.** README says a centered 600-point panel (line 245). HTML wraps the sheet in an absolutely positioned container with `left:0` and width determined by its child, without `left:50%`/translation or a full-width centering wrapper (lines 159–160). It appears left-aligned, not centered.

22. **The stated stage coordinate model is ambiguous.** README says the window content is 760×560 and the stage below the title bar is 760×524 (lines 29, 37). It also calls 760×560 “content area” (line 16), which in AppKit usually excludes title-bar chrome. An engineer cannot know whether the requested overall window is 760×560 or 760×596.

23. **The default cover contradicts branding.** README's Customize and Home use a generic stripe placeholder (lines 149, 191), while PLAN says the playlist cover uses the Messages/Spotify fusion mark. Even internally, “default cover” is not defined as a final asset.

24. **The done claim is not tied to successful creation.** Step 7 always auto-advances on timers and appends a list entry (HTML lines 495–508). No success response, playlist ID, URL, actual count, partial-add count, or cover failure is required. “You're all set” is reached by elapsed time alone.

25. **The navigation model cannot survive relaunch.** README defines `step` as an integer but no persistent state, checkpoints, or idempotency keys (lines 255–268). Reloading during creation can create duplicates; reloading during scanning loses progress; reloading after FDA returns to Welcome.

26. **Accessibility and keyboard states are absent from “final” design tokens.** There are hover/active styles but no focus-visible button state, keyboard selection behavior, default/cancel buttons, VoiceOver copy, reduced motion, or error colors. The only input focus token is a border color.

### 5. MISSING ERROR/EDGE STATES

1. App launched from a DMG, translocated path, read-only volume, non-`/Applications` folder, move denied, move fails, name collision in `/Applications`, administrator credentials required, or relaunch fails.
2. `chat.db` absent because Messages has never been used, Messages/iCloud is still syncing, user is signed out, history is incomplete on this Mac, database locked/busy, schema differs by macOS version, WAL read fails, database corrupt, or `attributedBody` decoding fails.
3. FDA not granted, user opens the wrong System Settings pane, user grants it but does not relaunch, “Quit & Reopen” kills the process, grant polling times out, access is later revoked, or FDA does not cover the launchd-started process.
4. No chats, no group chats, unnamed chats, duplicate display names, chats with no participants/count, DMs only, huge chat list, search/filter need, stale/deleted chat, or pre-scan/link count unavailable.
5. User tries Continue before selecting a chat, selection disappears after refresh, or the selected chat is renamed/deleted during import.
6. No Spotify account, login failure, unverified account, Free account, Premium lapses, dashboard unavailable, account not eligible for Development Mode, Create App unavailable, account/app limit reached, terms declined, or dashboard UI differs from instructions.
7. Create-app form rejects app name, description, Website, redirect URI, or API selection; redirect URI already used/conflicts; Save is not completed; user copies the wrong app's Client ID.
8. Blank, malformed, whitespace-padded, stale, revoked, or wrong-account Client ID; user pastes Client Secret into Client ID; clipboard permission/paste fails; Client ID changes after auth.
9. Redirect URI rejected by Spotify, redirect registered with different case/path/slash, callback port unavailable, callback captured by another app, callback never arrives, or `ASWebAuthenticationSession` cannot present from a headless menubar process.
10. Browser launch fails, user cancels, Spotify denies access, OAuth returns `access_denied`, state mismatches, callback lacks code, authorization code expires, token exchange fails, PKCE verifier is lost across app interruption, or the wrong Spotify account authorizes.
11. Requested scopes are denied/missing, Spotify changes consent, refresh token absent, access token expires mid-operation, refresh token expires/revokes/rotates, concurrent refresh races, Keychain is locked/denies access/corrupt, or stored credentials belong to a different Client ID.
12. Offline, DNS/TLS failure, timeout, captive portal, 401, 403, 404, 409, 429 rate limit, 429 quota exhaustion, 5xx, malformed JSON, schema change, partial response, or Spotify outage.
13. Development Mode endpoint not available, playlist writes blocked, current endpoint names differ, quota is exhausted across the developer's apps, or the app owner/user relationship violates current rules.
14. Zero messages, zero Spotify links, only YouTube links, malformed/unsupported Spotify URLs, albums/artists/playlists instead of tracks, local/removed/unavailable tracks, region restrictions, duplicate links, duplicate ISRCs, relinked tracks, or missing ISRC.
15. Extremely large history, progress total unknown/changes during scan, import takes minutes, app sleeps, app closes, crashes, restarts, is force-quit, loses network, receives a new link during backfill, or resumes with a stale cursor.
16. Partial import: playlist created but no items added; some batches succeed and some fail; duplicates skipped; items disappear between reads; retry queue persists; user cancels; user chooses retry, resume, or delete partial playlist.
17. Playlist name empty, only whitespace, too long, invalid description, emoji/Unicode normalization, duplicate name, API rejects metadata, or chat renamed later.
18. Cover chooser cancelled; non-JPEG selected despite filter; file extension lies; file unreadable; EXIF rotation; non-square crop; file over 256 KB; compression cannot reach limit; image upload permission missing; upload fails after playlist succeeds; default cover asset missing.
19. Playlist deleted, made public, unfollowed, ownership changes, ID mapping is corrupt, playlist contents cannot be read, duplicate cache is stale, or recreate action itself fails.
20. LaunchAgent registration denied, `.requiresApproval`, disabled in Login Items, status does not become enabled, registration launches a duplicate process, single-instance handoff fails, `flock` fails, crash loop occurs, or clean Quit immediately respawns.
21. Home with no playlists, dozens of playlists, long/non-Latin names, stale counts, paused status, syncing status, offline status, attention status, FDA revoked, auth revoked, playlist deleted, retry backlog, last sync unknown, or app update requires re-registration.
22. User closes the onboarding window, reopens it, quits midway, logs out, reboots, switches macOS account, changes Spotify account, changes Client ID, removes a chat, adds the same chat twice, or runs the app on a second Mac.
23. Reduced Motion enabled, VoiceOver active, Full Keyboard Access, Increase Contrast, Differentiate Without Color, large text/accessibility display settings, low-power mode, 1× versus 2× display, multiple monitors, inactive window, or unsupported macOS version.

### 6. TOP 10 MUST-FIX, RANKED

1. **Prove the July 2026 Spotify auth path on a fresh Development Mode app and replace both custom-scheme redirect strings with one currently accepted, end-to-end-tested callback.**
2. **Delete Client Secret collection and storage; implement PKCE with Client ID, verifier/challenge, state validation, and refresh-token Keychain handling only.**
3. **Update PLAN and the handoff to Spotify's current Development Mode endpoints, limits, Premium rule, quotas, and redirect policy before UI implementation begins.**
4. **Rewrite the Spotify setup screen as a literal dashboard walkthrough: account/login, Premium, terms, every form field, Web API selection, Save, Settings, and Client ID retrieval.**
5. **Replace the handoff scopes with the least-privilege set justified by the final feature set, and make the consent explanation accurately disclose private-playlist and library reads.**
6. **Restore PLAN's pre-FDA gates: Welcome prerequisite disclosure, move-to-`/Applications`/translocation handling, and persisted FDA relaunch resume.**
7. **Collapse the handoff into PLAN's five product screens or formally amend PLAN; remove unapproved customization/cover-upload/Home-window scope until that decision is explicit.**
8. **Design real import and recovery states for resumable backfill, current API batching/rate/quota behavior, partial success, duplicates, YouTube counts, zero results, and interruption.**
9. **Replace the decorative Home with the actual menubar steady state and required controls: health, pause/resume, add chat, open playlist, recovery actions, and Quit/unregister semantics.**
10. **Deliver implementable native visual specs: bundled/licensed assets and fonts, normalized paths, SpriteKit tuning targets, animation recordings/parameters, accessibility states, and deterministic golden screenshots.**

Bottom line: **No, this handoff is not safe to build from as-is.** It contains an auth-breaking redirect mismatch, appears incompatible with Spotify's current redirect policy, asks users for an unnecessary Client Secret, requests the wrong permissions, omits Premium and most real dashboard steps, contradicts the authoritative five-screen product flow, and provides no viable recovery design for the riskiest operations. First prove the current Spotify Development Mode path—including redirect, PKCE, playlist writes/reads, library dedup, refresh, and current endpoints—then update PLAN, and only then rewrite the onboarding handoff around that verified contract. Starting SwiftUI work before those changes would convert unresolved product and platform failures into expensive UI rework.
