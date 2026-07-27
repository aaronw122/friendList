# Friend List — R3 Challenge (Defense)

Role: skeptical senior engineer attempting to disprove each R3 Critical/Must-fix. Verdict per item is **REALITY**-based (CONCEDE = the defect is real; DISPROVEN = phantom/misread/theoretical/settled-re-raise). Severity is not the axis — "doesn't crash" ≠ "delivers the core promise."

Inputs: PLAN.md · r3-consolidated (prosecution) · r2-verdict (prior adjudication). Platform facts verified against the `launchd.plist(5)` man page, Apple Developer Forums, and Spotify's official Quota Modes docs (Feb-2026 dev-mode changes).

---

## C1 — `SMAppService.agent().register()` + `RunAtLoad` spawns a duplicate live instance, no single-instance handoff

**Verdict: CONCEDE (real, newly introduced).**

Disproof attempts, all failed:

1. *"register() doesn't run the program; it only registers for next login."* — False for `.agent` + `RunAtLoad`. `launchd.plist(5)`: `RunAtLoad` = "launched once at the time the job is loaded," and `register()` loads the job. So on a successful/enabled registration the launchd copy (instance B) starts **immediately**, while the LaunchServices-launched onboarding process (instance A) is still alive. This is a documented, reproduced behavior — Apple Developer Forums thread *"SMAppService.agent.register() will launch a second instance of an application"* (developer.apple.com/forums/thread/745712) describes exactly this.

2. *"First registration lands `.requiresApproval`, so nothing runs during onboarding."* — Doesn't save it. The plan's own M4 flow drives the user to approve ("Enable Friend List in Login Items"); the moment approval lands, `RunAtLoad` fires while instance A may still be up. And the plan explicitly admits the general case ("any later Finder-open of the .app starts yet another") — the second-instance window is not confined to onboarding.

3. *"The `flock` guard already handles it."* — No. Plan Component 2 (line 113) is explicit that `flock` exists "so two instances can't **double-write**" — it guards state writes, not process/UI multiplicity, and the plan **never names a winner or a loser-exits contract**. Result: two `MenuBarExtra` processes (two menubar icons), two scanning loops racing the lock, and the flock-loser's behavior is unspecified (silent no-op or error), not a clean exit.

This is a *genuinely new* mechanism, not the R2-downgraded C1 (whose false "FDA-grant kills the app" premise R2 stripped). It is a direct side-effect of the R2-endorsed switch to `SMAppService.agent`: R2 blessed the *mechanism* (agent + KeepAlive watchdog, same executable) but never specified `RunAtLoad`/handoff, and the plan wired it with no single-instance contract. The fix is cheap (post-register `NSApp.terminate` on the onboarding instance, or a bundle-id `NSRunningApplication` activate-existing-and-exit on every launch, lock-loser `exit(0)`), which confirms it's real and unaddressed rather than theoretical.

---

## MF1 — `KeepAlive=true` (boolean) turns a clean menubar Quit into a respawn

**Verdict: CONCEDE (real, newly introduced).**

The platform fact is authoritative, not arguable. `launchd.plist(5)` on the **boolean** form: *"The value may be set to true to **unconditionally** keep the job alive."* Unconditional = respawn on **any** exit, including a user-initiated clean `exit(0)`. So the menubar "Quit" is defeated: the process dies, launchd relaunches it (throttled to launchd's default ~10s `ThrottleInterval`). The correct crash-only semantics are the dictionary form `KeepAlive={SuccessfulExit=false}` — man page: *"If false, the job will be restarted in the inverse condition"* (i.e., only on non-zero/abnormal exit), which still gives RunAtLoad login-start + crash-restart while honoring a deliberate Quit.

The plan specifies bare `RunAtLoad + KeepAlive` (Architecture line 77, Component 1 line 106, Component 2 line 111, Tech stack line 212) — i.e., boolean `true`. The common counter-claim that "KeepAlive=true already respects exit 0" is a well-circulated community **misconception** (e.g. tjluoma/launchd-keepalive README) contradicted by the man page's "unconditionally." "Storm" is mild hyperbole (it's one throttled respawn per quit, not a tight loop), but the load-bearing claim — **a deliberate Quit does not stay quit** — is true. Not disprovable. Needs the `SuccessfulExit=false` fix + routing Quit through `unregister()`/bootout, exactly as filed. Genuinely new (R2 fact 2 named the watchdog but not the plist key).

---

## MF2 — Onboarding must add the owner's OWN Spotify account under "Users and Access"

**Verdict: DISPROVEN (false premise + R2-settled re-raise, no new reasoning).**

The core claim — *"owner's own account must be added or auth returns 'user not registered'"* — is false for this plan's model. Spotify's official Quota Modes docs: the 403 "User not registered in the Developer Dashboard" hits **non-owner** users who install a dev-mode app; **"each Spotify user who installs your app will need to be added to your app's allowlist"** is about testers, while the **app owner has direct access through their own (Premium) account** and needs no separate self-add. The plan is strictly **owner == user** (BYO client_id: each user creates and owns their own dev app), which is precisely the case that needs no allowlist entry.

This is verbatim the issue the **R2 judge DISMISSED** (fact 3 + M2 verdict): "a Spotify dev-app owner authenticating with the owning account needs no User Management self-add… a verification flag inflated to Must-fix." R3 re-raises it as Must-fix with **zero new reasoning** — the only delta is the dev-mode cap number (25 → 5), a real 2026 change but an impl-note detail that does not touch the self-add question. The legitimate residue (Spotify's dev-mode policy churn) is already captured by the plan/impl-note **"verify at M2 on a fresh dev app"**, not an onboarding self-add step. (Verified: Feb-2026 changes require the **owner** to have Premium — already in the plan — and cap testers at 5; neither implies owner self-add.)

---

## MF3 — Privacy "Local only" contradicts the retry queue storing source chat + sender

**Verdict: DISPROVEN (misread of the privacy claim + R1/R2-settled re-raise as Must-fix).**

No off-device leak exists. The retry queue (Component 8) lives in the app's Application Support container on the same Mac; its chat/sender fields **never leave the device**. The privacy *pillar* — "No user data ever leaves the Mac" / "No off-device data" — is intact; persisting chat/sender **locally** does not contradict "Local only," it *is* local. The only real residue is a one-line wording seam between §Privacy line 241 ("only Spotify track IDs are persisted … never … contact identifiers **beyond what filtering needs locally**") and the retry queue's local sender field.

This is **verbatim R1-M7, re-adjudicated as R2-M6**, both times **downgraded to Low** as exactly that "one-line wording mismatch (drop the two fields, or amend the §Privacy sentence)." The consolidated itself tags it "carried-over." R3 restates identical content and re-inflates it to Must-fix with **no new argument**. Severity bar untouched (nothing silent, nothing off-device); the cheap wording/field-trim fix stands at Low, as already ruled twice.

---

## Holistic

The prosecution splits cleanly down the middle. The two **new** findings (C1, MF1) are **both real** and both are the same story: R2 endorsed the `SMAppService.agent` + KeepAlive *mechanism* but left the plist unspecified, and the plan implemented the details wrong — `RunAtLoad` with no single-instance handoff, and boolean `KeepAlive` instead of `{SuccessfulExit=false}`. They are cheap, verifiable, and cluster on R2's own "launch survivability" seam, so they should be folded into M4 as filed. The two **carried-over** findings (MF2, MF3) are settled-item re-raises — MF2 on a false premise the R2 judge already dismissed (owner==user needs no self-add), MF3 a twice-downgraded Low wording seam inflated to Must-fix — and both fall. Net: concede the systems defects, reject the recycled ones.
