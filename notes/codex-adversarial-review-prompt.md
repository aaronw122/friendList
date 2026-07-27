# Task: Adversarial review of a design handoff

You are an adversarial technical reviewer. Be skeptical, specific, and harsh. Your job is to find every problem BEFORE a SwiftUI engineer starts building from this handoff. Do not praise. Do not summarize for its own sake. Hunt for defects.

## What to read (all paths relative to the current working directory, which is the project root)

1. `design_handoff/README.md` — the design handoff spec (the artifact under review).
2. `design_handoff/FriendList Onboarding.dc.html` — the HTML prototype the handoff describes. Cross-check the spec against what the prototype actually does.
3. `PLAN.md` — the authoritative product/engineering plan for this same app (Friend List). The handoff must be consistent with this.

## The product (context)
Friend List is a native SwiftUI macOS menubar app that reads a group chat in Messages locally (`chat.db`), extracts Spotify track links, and builds/maintains a Spotify playlist. The handoff covers the onboarding + home UI only. The target is native SwiftUI + SpriteKit (NOT a webview, NOT React).

## What I need from you — write findings, grouped and prioritized

Produce your review as Markdown written to `notes/2026-07-25-handoff-adversarial-review.md`. Structure it exactly like this:

### 1. CONTRADICTIONS between the handoff and PLAN.md
Hunt hard here. For each, quote both sources with line-ish references and state which is likely correct and why. Known suspects to verify (do not trust me — check yourself, and find more):
- Redirect URI: handoff uses one value, PLAN uses another. Exact string match matters — this is an OAuth callback; a mismatch breaks auth.
- Spotify scopes: handoff lists one set, PLAN lists a different set. Which is right given the app only makes PRIVATE playlists and needs dedup reads?
- Number/shape of onboarding screens (handoff = 9 steps incl. home; PLAN = 5 screens). Is anything the PLAN requires MISSING from the handoff?
- Premium requirement, BYO client_id, app-translocation / move-to-/Applications gate, Full Disk Access relaunch survival — are these in the handoff at all?

### 2. SPOTIFY DEVELOPER ACCOUNT ONBOARDING GAPS (single most important section)
The handoff's "Spotify developer keys" step (step 3) is suspected to be incomplete/oversimplified vs what a real user must actually do in Spotify's dashboard in 2025-2026. Enumerate every concrete step a real user must perform that the handoff omits or gets wrong. Consider at minimum: needing a Spotify account + logging in, accepting developer Terms of Service, the exact "Create app" form fields (App name, App description, Website, Redirect URI, which APIs/SDKs checkbox — Web API), where the Client ID and Client Secret actually live (Settings page), whether client secret is even needed for PKCE (PLAN uses PKCE — does PKCE need the secret? If not, why does the handoff collect "Client secret"?), Premium requirement, dev-mode user cap / adding users, and 2025-26 dashboard changes. Flag the Client Secret question specifically: the handoff collects a client secret and says store it in Keychain, but PLAN's auth is Authorization Code + PKCE which typically does NOT use a client secret for a native app. This is a possible fundamental contradiction — analyze it.

### 3. TECHNICAL FEASIBILITY / SwiftUI recreation risks
Where will a SwiftUI engineer get stuck or produce something that doesn't match? Be concrete: SpriteKit vs Matter.js physics-feel gaps, the sheet slide/spring transition, `clip-path` shapes (torn ticket, bubble tail, star, heart) as SwiftUI `Path`/`Shape`, `backdrop-filter` blur, inset box-shadows, fixed 760×560 non-resizable window, custom URL scheme registration, Keychain, fonts (Plus Jakarta Sans / IBM Plex Mono licensing + bundling). Note anything underspecified.

### 4. INTERNAL INCONSISTENCIES in the handoff itself
Numbers that don't add up, copy that contradicts itself, tokens referenced but not defined, screens that reference states never defined, navigation that loops incorrectly, progress-bar percentages, step indices, etc. Cross-check README claims against the actual HTML prototype behavior.

### 5. MISSING ERROR/EDGE STATES
The handoff mentions error paths exist but may not design them. List each error state that needs a real UI but isn't specified (no FDA, invalid credentials, OAuth denied/cancelled, network failure, zero songs found, playlist deleted, token revoked, etc.).

### 6. TOP 10 MUST-FIX, RANKED
A ranked, actionable punch list. Each item: one line, imperative, with the specific fix. These are what the engineer will act on first.

## Rules
- Cite specifics (quote the text). Vague findings are useless.
- When the handoff and PLAN disagree, PICK A WINNER and justify it — do not just note the difference.
- It is fine to inspect the HTML/JS to confirm actual behavior.
- Do NOT modify any files except creating `notes/2026-07-25-handoff-adversarial-review.md`.
- Do NOT write any Swift code. This is review only.
- End the file with a one-paragraph "Bottom line: is this handoff safe to build from as-is? What must change first?"
