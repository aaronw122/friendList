# Friend List — R2 Challenge (Defense)

Role: skeptical senior engineer disproving R2's Critical + Must-fix findings.
Severity bar (from R1 judge): "the app still delivers its core promise correctly" — friend-sent
songs auto-added, privately, set-and-forget. Silent non-function is severe. I challenge
**reality, not severity**: is the finding a true, load-bearing defect against the *actual* plan?

Platform facts established (web-verified 2026-07):
- **SMAppService.mainApp login item = login-only.** It registers the app to auto-launch *at login*.
  It carries **no** `KeepAlive`/crash-restart semantics — that is LaunchAgent/`launchd` territory.
  (M1's factual premise is TRUE.)
- **Spotify dev-mode owner self-add = NOT required.** Spotify's own docs + community mods:
  *"You should not put your own information inside the dashboard of your own app. That's not
  required."* The owner authenticates directly with their own credentials; the "user not
  registered" 403 hits **non-owner** un-allowlisted users. (M2's premise is FALSE for the
  owner==user BYO case.)
- **FDA grant does NOT restart/kill a running app.** macOS shows a passive *"…will not have full
  disk access until it is quit"* notice and an *optional* "Quit & Reopen"; it never force-kills.
  The grant simply isn't seen by the already-running process until relaunch. (C1's "kills the app
  mid-onboarding" is FALSE.)
- **App translocation is real** (Gatekeeper Path Randomization): a quarantined app launched
  *directly from the DMG/Downloads* runs from a randomized read-only path, changing the executable
  path used by TCC. **A Finder move to /Applications clears it.** (M3's fact is real but scoped.)

---

## Critical

### [C1] "FDA grant kills the app mid-onboarding; menubar-only relaunch has no step-resume" — **DISPROVEN**
Two-part claim, both parts fail against reality:
1. **"FDA grant kills the app"** — factually wrong. Verified: granting Full Disk Access does not
   terminate or relaunch a running app. macOS posts a passive "quit to take effect" notice and an
   *optional* Quit & Reopen button; the process keeps running. There is no involuntary "kill
   mid-onboarding." The finding's dramatic premise is a misread of TCC UX.
2. **The real residue — "grant not seen until relaunch; persist an onboarding-step marker and
   re-present the window"** — is **verbatim R1's M8**, which the R1 judge already **DOWNGRADED to
   Medium** ("persist the onboarding step so relaunch resumes at Scope… worst-case recovery is
   benign; the relaunch replays two pre-auth screens; no state or auth exists yet"). R2 re-labels
   the identical concern **Critical** by bolting on a false "kills the app" premise. That is
   severity inflation on a misread, not a new Critical.
- **Genuinely new content?** Only the minor LSUIElement wrinkle: on relaunch a menubar-only app
  must `NSApp.activate` + explicitly present the onboarding window. That is a one-line
  implementation note (the plan already persists `didOnboard`, Component 1), *not* a Critical
  defect. Fold it into the already-adjudicated M8 Medium.
- **Core promise:** untouched. Worst case is the benign replay R1 already described.

---

## Must-fix

### [M1] "No crash/exit recovery — SMAppService.mainApp is login-only; lost LaunchAgent KeepAlive" — **CONCEDE (narrow; doc-line, not a watchdog)**
The platform fact is **true**: `SMAppService.mainApp` launches at login and does not auto-restart on
crash. I will not pretend otherwise. But the finding overstates the impact and the fix:
- **Impact is bounded, not catastrophic.** The watermark (`last_seen` ROWID) is persisted and the
  loop is explicitly restart-safe (§Scanning loop, "resumes from persisted `last_seen`… drains the
  retry queue"). A crash therefore **delays**, it does not **drop**: on next login the scanner
  catches up from the last watermark. No friend song is permanently lost — the plan's own
  wake/relaunch catch-up design already covers this.
- **The proposed fix is over-engineering.** An `SMAppService.agent` watchdog re-introduces a second
  code identity/binary — the exact multi-binary complexity C1's single-executable collapse was
  adopted to kill. The prosecution's *own* OR-branch ("explicitly document login-only recovery")
  is the right resolution: one sentence in the plan.
- **Verdict:** real fact → concede a **one-line documentation** of login-only recovery + a crash-
  restart note in M4 acceptance. Reject the watchdog. Not a core-promise breaker.

### [M2] "BYO onboarding omits the Spotify User Management self-add step → dev-mode auth fails" — **DISPROVEN**
The finding's central premise is contradicted by Spotify's own documentation and dashboard mods:
**the app owner does not need to add themselves under User Management.** Owners authenticate
directly with their own credentials; the "user not registered in the Developer Dashboard" 403 is a
**non-owner** problem (an un-allowlisted *other* user). The plan's model is strictly owner==user:
each user creates *their own* dev app and signs in with the *same* account that owns it (Component 5,
§Onboarding 3, Med11 confirms same account). That is precisely the case Spotify says needs **no**
self-add.
- **Already-adjudicated context:** R1's M4 (the allowlist/email concern) was **DISMISSED** as
  subsumed by C2 — no allowlist obligation exists on the BYO path. R2 re-raises a cousin of it.
- **R2's own confidence is weak:** agent2 filed it **Low**, agent3 an **impl-note "verify"**, and
  R2's impl-note #51 literally says *"Confirm whether a dev-app owner must self-add."* Elevating a
  "please verify" flag to **Must-fix** on a premise Spotify's docs refute is unjustified.
- **Verdict:** phantom for the owner-only BYO flow. At most, add a "verify at M2" line — which the
  plan already implies. No self-add step is required.

### [M3] "App translocation invalidates the path-keyed FDA grant and login-item path" — **CONCEDE (narrow; overstated, mitigated by the plan's own install flow)**
The macOS fact is **real**: translocation runs a quarantined app from a randomized path, and TCC/
login-item records are path-sensitive. I concede the fact. But the finding is **context-blind to
the plan's stated distribution**:
- The plan ships a **.dmg with "drag to /Applications"** (§Distribution, M5). A Finder move to
  /Applications **clears translocation** — the app then runs from a stable path, and FDA is
  requested *during onboarding, after install*, i.e. against the /Applications path. The finding's
  failure scenario only materializes if the user runs straight from the DMG in violation of the
  documented step.
- So the claim that translocation "invalidates the FDA grant AND the login-item path" is **false
  for the documented flow** and true only for a mis-install.
- **Verdict:** worth a **cheap defensive guard** (detect not-in-/Applications / translocated →
  prompt to move before requesting FDA) — this is routine notarized-app packaging hygiene, not a
  novel architectural flaw or a Must-fix. Concede the guard; reject the "invalidates everything"
  framing.

### [M4] "Login-item registration may be declined / require approval; ambient promise breaks silently" — **CONCEDE (real, cheap; rides existing M6 machinery)**
This is a genuine platform reality: an `SMAppService` registration can land in `.requiresApproval`,
and the user can toggle the login item off in Settings at any time. If it is not `.enabled`, the
"never open again" auto-launch silently fails — which *does* hit the set-and-forget promise, and the
plan (Component 1) checks no such status. I concede this as real.
- **But it is a small, localized addition, not a redesign:** the plan already defines the M6
  attention-state surface ("Attention needed", swap icon, reopen relevant step). Adding
  `status != .enabled` → "Enable Friend List in Login Items" is one more case on machinery that
  already exists. Elevated-from-Low per R2 is fair; the fix is trivial.
- **Verdict:** concede — add a login-item-status check to the existing attention surface + an M4
  acceptance line.

### [M5] "Denied / never-granted FDA still has no failure state" — **DISPROVEN (already DOWNGRADED to Low in R1; no new reasoning)**
This is **R1's M5**, which the R1 judge explicitly **DOWNGRADED to Low (merge with L4)**: *"the user
is present at the screen… this is not silent background failure, so the severity bar is not met.
What's missing is stuck-state copy."* R2 re-raises the identical item back to **Must-fix** and adds
**no new reasoning** — it just re-asks for "try again / can't continue" copy plus an "installed-but-
paused" state, which is exactly the stuck-state copy R1 already scoped as Low.
- **Reality check:** the grant path is fully specified (probe read, explainer, deep link, poll,
  Component 1 + §Onboarding 2). The app genuinely cannot function without FDA and the user is
  *looking at the screen* — a copy gap, not silent non-function.
- **Verdict:** re-litigation of an adjudicated Low. Add the stuck-state copy (already tracked by
  L5). Not Must-fix.

### [M6] "Privacy claim contradicts the retry queue storing source chat + sender" — **DISPROVEN (already DOWNGRADED to Low in R1; no new reasoning)**
This is **R1's M7**, **DOWNGRADED to Low**: *"local-only, so the privacy pillar (nothing leaves the
Mac) is intact. Fix in one line."* R2 re-raises it as **Must-fix** with the same content and no new
argument.
- **Reality check:** the retry queue's chat/sender fields **never leave the Mac** — the entire
  privacy *pillar* ("no user data ever leaves the Mac") is untouched. The plan's §Privacy even
  hedges "beyond what filtering needs locally." The residue is a literal wording mismatch against
  one sentence, fixable by dropping the two fields or amending the sentence — a one-liner.
- **Verdict:** local-only wording nit, already adjudicated Low. Core promise (privacy) intact. Not
  Must-fix.

### [M7] "Premium + own-dev-app disclosed on screen 3, AFTER the FDA grant on screen 2 → non-Premium dead end" — **CONCEDE (real UX ordering; copy re-order, not architecture)**
This is a legitimate **disclosure-ordering** finding and it is genuinely NEW (a C2-BYO side-effect).
Premium *is* in fact required (Spotify's Feb 2026 dev-mode change confirms owner-Premium), so a
non-Premium user who grants invasive FDA on screen 2 only to discover the Premium/own-app gate on
screen 3 hits a real dead-end moment. I concede the UX point.
- **But it is not a functional/core-promise defect and not architectural:** the FDA grant is
  user-reversible, nothing has left the device, and the user is *informed* (no silent failure). The
  fix is pure onboarding copy: surface "Premium + you'll create your own Spotify app" on **Welcome
  (screen 1)**, before the FDA ask.
- **Verdict:** concede as a cheap Welcome-screen disclosure re-order. Real, but a UX polish item,
  not a break in the seeing/adding legs.

---

## Holistic Assessment

**Scorecard:** C1 DISPROVEN · M1 concede(doc) · M2 DISPROVEN · M3 concede(guard) · M4 concede(status
check) · M5 DISPROVEN · M6 DISPROVEN · M7 concede(copy).

The two findings that, if true, would actually break the core promise — **C1** ("FDA grant kills the
app") and **M2** ("dev-mode auth fails for your own account") — are both **factually wrong** against
verified platform behavior. Neither macOS nor Spotify behaves as the prosecution asserts. C1 is a
misread of TCC UX wrapped around R1's already-Medium M8; M2 is a "please verify" flag inflated to
Must-fix and refuted by Spotify's own docs.

Of the remaining "Must-fix" items, **two (M5, M6) are R1 findings already DOWNGRADED to Low that R2
re-raises with zero new reasoning** — pure re-litigation. The four I concede (M1, M3, M4, M7) are all
**real but small, localized, non-architectural** additions: one doc line (M1), one packaging guard
(M3), one attention-state case on machinery the plan already has (M4), and one Welcome-screen copy
re-order (M7). **None** breaks the seeing leg, the adding leg, the privacy pillar, or the process
architecture. The R1 judge's verdict stands unchanged: sound concept, correct feasibility, four
prerequisite fixes (C1/C2/M2/M6 from R1) already identified — R2 adds no new *architecture-changing*
defect.

**One caveat the prosecution missed entirely** (and the more important real risk than anything in
its C1/M-list): Spotify's **Feb 2026 dev-mode tightening** and a community report (spotify-web-api-ts-sdk
Issue #159) that **playlist *write* access may be restricted for Development-Mode apps**. If true,
that would kill the core promise regardless of any R2 finding — it is the single thing genuinely
worth blocking M2 (the milestone) on, far more than dev-app self-add or crash watchdogs. Verify a
live `POST /playlists/{id}/tracks` from a fresh dev-mode app at milestone M2 before anything else.
