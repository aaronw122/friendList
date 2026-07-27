# Plan Review — Product / Integration / UX Reviewer (r1, agent3)

Note: the plan is an iMessage→Spotify daemon, not a social friend-list app, so the persona's
literal flows (add/accept/decline/block friend) do not exist here. Reviewed through the general
Product/Integration/UX lens: end-to-end flows, front↔back API-contract consistency, real error
paths, and cross-section consistency.

## Critical
- none

## Must-fix
- **Missing `playlist-read-private` scope.** §4 Spotify client lists scopes `playlist-modify-private playlist-modify-public user-library-read`, but Dedup strategy reads the target playlist (`GET /v1/playlists/{id}/tracks`) and, when `dedup_all_my_playlists` is on, every owned playlist (`GET /v1/me/playlists`). Reading a private playlist you own requires `playlist-read-private`; without it these calls 403 and dedup silently fails → duplicate adds. Fix: add `playlist-read-private` to the scope list in §4.
- **OAuth redirect/callback receiver is undefined.** §4 says "one-time browser login" and Setup step 2/3 assume a redirect to `http://127.0.0.1:PORT/callback`, but no component receives the redirect. PKCE requires a loopback HTTP listener to capture the auth `code`. Fix: add a local callback-server responsibility to `spotify.py` (or a small auth module) in Components.
- **Config missing `client_id`, `redirect_uri`/`port`.** Setup steps 2–3 depend on a client ID and redirect URI, but §1 Config (`config.toml`) never defines them. Front-of-flow references a contract the config doesn't provide. Fix: add `client_id`, `redirect_uri` (or `callback_port`) to §1.

## Medium
- **`only_from_others=true` default conflicts with the stated test flow.** §1 default skips `is_from_me=1`, but M1's done-criterion is "a Spotify link **you text yourself** shows up parsed" and M3 is tested by texting a link. With the default on, self-texted links are filtered out and the acceptance test fails. Fix: state that verification uses a second handle, or default `only_from_others=false` for M1/M3.
- **`dedup_liked_songs=true` default may drop wanted songs.** Dedup strategy skips any incoming track already in Liked Songs. A friend-sent song you happen to have Liked (but isn't in the friend playlist) never enters the playlist — likely surprising product behavior for a "friend playlist." Fix: reconsider the default, or scope friend-sent adds to playlist-only dedup and document the trade-off.
- **No defined behavior when auth fails unattended.** §5 daemon loop has no path for a revoked/expired refresh token (password change, revoked app access). Adds would silently stop with the daemon still "running" and no user signal. Fix: define a re-auth/notify path in the daemon loop.

## Low
- **No user-facing success/failure feedback.** For a "zero taps, ambient" product the only signal is a log file (§5). The user cannot tell it's working or that it stopped. Fix: add a minimal macOS notification on add/failure, or explicitly accept log-only for MVP and note menubar status is deferred to v2.

## Impl-note
- Handle normalization for `allowed_handles`: chat.db handles appear as phone numbers or emails and the same friend may match multiple; matching rules are an implementation detail.
- Playlist dedup cache goes stale between periodic refreshes if the user edits playlists elsewhere; refresh cadence is an implementation tuning detail.
- Regex/`?si=` share-token stripping and `spotify:track:` URI edge cases (§3) surface naturally during coding.
