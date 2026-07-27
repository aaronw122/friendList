# Friend List Plan Review — Spotify OAuth/API + Distribution Specialist (r1-agent2)

Persona lens: ASWebAuthenticationSession PKCE + `friendlist://` redirect, embedded public client_id, token storage/refresh, playlist bootstrap/add/dedup + scopes, ISRC, and macOS distribution (Developer ID / notarization / Gatekeeper / Spotify quota).

## Critical
- **Public-distribution model is non-viable under current Spotify quota policy** — one embedded shared `client_id` (§Components 5, §Distribution, §Risks "Spotify app quota") means *all installs count against one app*. As of Feb 2026 development mode is capped at **5 authenticated users** (plan says "~25"), and extended quota now requires a legally-registered business + **250k MAU** + launched service (6-wk review) — unobtainable for this app. → Re-architect to **bring-your-own client_id**: each user creates their own Spotify dev app and pastes their `client_id` in onboarding. Each user is then their own app *owner* (dev mode, self-use, no allowlist, no extended quota). Drop "one Spotify developer app backs all installs."

## Must-fix
- **Dev-mode allowlist requires each user's Spotify account email** in the dashboard — directly contradicts the privacy pillar "no email, we never ask for anything" (§Product shape pillar 1, §Privacy, §Onboarding 3). Under the shared-client_id design every user would have to send you their email to be allow-listed. → The BYO-client_id fix above removes this (owner needs no allowlist); state explicitly that no shared allowlist exists.
- **Refresh-token rotation not persisted** (§Components 5 "silent access-token refresh"). Spotify's PKCE refresh response returns a *new* `refresh_token`; if the daemon keeps reusing the original it will silently lose auth and the "forever" loop dies. → StateStore/Keychain must overwrite the stored refresh token with the rotated value on every refresh.

## Medium
- **Liked Songs dedup cannot be ISRC-aware as specified** — `GET /v1/me/tracks/contains?ids=` (§Dedup strategy, source 2) returns booleans keyed by *track ID only*, so a re-release with a different ID but same ISRC in Liked Songs won't be caught, contradicting the "keys on ISRC, not just track ID" claim (§Dedup "Matching key — ISRC-aware"). → Note Liked Songs dedup is ID-only, or make full-library ISRC scan the opt-in path.
- **Developer/user Premium requirement** (§Tech stack / §Risks) — since Feb 2026 dev-mode Web API access requires the app owner to hold Spotify Premium. Under BYO-client_id each user is an owner → each user needs Premium. Call this out as an adoption constraint before M2/M5.

## Low
- **Confirm `friendlist://auth-callback` registered as a Redirect URI** in the Spotify dashboard (§Components 5). Custom schemes remain supported after the 27 Nov 2025 OAuth migration (only HTTP/localhost were removed), so the custom-scheme choice is correct and needs no loopback server — just document the required dashboard registration.

## Impl-note
- `GET /v1/playlists/{id}/tracks` pages at 100 items — dedup cache build must paginate (§Dedup source 1).
- Per-track `GET /v1/tracks/{id}` (ISRC) + `contains` per incoming track can hit the 30s rolling rate limit on bursts; batch `?ids=` (up to 50) where possible (§Dedup).
- Include and verify the OAuth `state` param for CSRF on the ASWebAuthenticationSession round-trip (§Components 5).
- `ASWebAuthenticationSession(callbackURLScheme:)` takes the bare scheme `friendlist`, not the full URL (§Components 5).
- Notarization: the bundled agent binary must also be signed with Hardened Runtime + secure timestamp, and both binaries need matching `keychain-access-groups` entitlement (same Team ID) for the shared Keychain item (§Architecture, §Distribution, §Components 5).
