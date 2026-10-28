# Concept

Agreed with the maintainer on 2026-10-28. Layouts are on the design canvas
"Bortle App – Konzept & Layouts"; this file is the written source of truth.

## Decisions

| Topic | Decision |
|---|---|
| Platforms | Android and iOS, Flutter stable |
| License | Apache-2.0 (store-compatible); the Bortle server stays AGPL-3.0 |
| Repository | this one, public, separate from the server |
| Store identity | `eu.bortle.app`, on the same developer accounts as allskyhub |
| Control | yes: the app operates the rig, as the cockpit's `/rig` pages do |
| Push | the way allskyhub does it (Firebase Cloud Messaging) |
| Shared code with allskyhub | copied first; a shared Dart package only once both apps exist and the maintainer agrees |

## Talking to a server

The app is one more client of the **cockpit**, at `https://bortle.eu` or at the
address the user enters ("own instance"). It never talks to the orchestrator
directly: the orchestrator has no auth of its own, and the cockpit's proxy is
where per-user scoping and the operator-only instance settings are enforced.

The server gets these additions, which live in the Bortle repository:

- `GET /api/app/info` (public): `{name: "bortle", version, api, auth: "password" | "none"}`.
  The app calls it before login. It tells a Bortle apart from anything else
  and an old instance apart from a current one, and it says whether the
  instance runs in local mode without accounts.
- `POST /api/app/login` `{email, password, device}` returns an opaque token
  `bat_…`. The server stores only its hash, as it does for plugin keys.
- `DELETE /api/app/session` signs out.
- `GET/DELETE /api/app/devices` lists and revokes the signed-in devices; these
  also appear on the profile page.
- The proxy accepts `Authorization: Bearer bat_…` and resolves it to the same
  session a cookie would. Scoping is unchanged.
- A contract test in the Bortle repository checks that every endpoint the
  app's client calls exists in the cockpit, like the one for the N.I.N.A.
  plugin.

The token is kept in `flutter_secure_storage` as `StoredSession(serverUrl, token)`.
Local mode over `http://` outside a private network gets a visible warning.

## Navigation

The bottom bar has five tabs; everything else is pushed on top.

1. **Heute** (Tonight)
   - night state
   - holds waiting for an answer
   - developments in progress, with step and progress
   - latest finished images
   - events
2. **Planen** (Plan)
   - object search
   - altitude over the user's horizon, moon, clouds, dark hours
   - the proposed exposure plan and the develop level ("Danach entwickeln")
   - sending the sequence to N.I.N.A.
3. **Teleskop** (Telescope): the running night, from N.I.N.A. A segmented
   header has four views:
   - *Übersicht* (Overview):
     - latest frame
     - HFR, stars, guiding RMS
     - sequence progress
     - plugin upload queue
     - next autofocus and meridian flip
     - "Nacht beenden" (end the night)
   - *Bilder* (Frames):
     - every frame of the session as a grid of previews, with a full-screen
       view that has a stretch toggle
     - QC verdict per frame
   - *Verlauf* (History): HFR, star count, guiding RMS, temperature and focuser
     position over the session, plus the events.
   - *Steuern* (Control): tiles for each device, every one a detail screen:
     - Mount: jog pad with rates, slew to target, tracking, park and unpark,
       meridian flip settings (shown, not set).
     - Camera: single exposure, cooling and warming, gain, binning, dew heater.
     - Focus: step in and out, run autofocus, the live curve and its verdict.
     - Guiding: start and stop, the RMS graph, clear calibration.
     - Filter wheel, rotator, flat panel (light, cover, brightness).
     - Sequence: load, start, stop, skip, the instruction tree.
     - Framing and TPPA polar alignment.
     - Devices: connect and disconnect, with the driver N.I.N.A. actually
       loaded.
4. **Galerie** (Gallery)
   - Images, runs and sessions.
   - A run shows live progress while it computes:
     - steps done and still to come
     - current step with a progress bar
     - estimated time
     - the worker it runs on
   - When it is finished, it shows the full log, sharing, and developing again.
5. **Mehr** (More)
   - sessions
   - upload from Nextcloud
   - profile
   - N.I.N.A. plugin keys
   - signed-in devices
   - red light mode
   - the operator-only pages: settings, system, users

## Control and safety

The app may operate everything the cockpit can. It adds no operation of its
own, and the rules that bind Bortle bind the app:

- Parking on unsafe conditions, the meridian flip and the safety monitor stay
  in N.I.N.A. The night ends safely without the app, the network or Bortle.
- Anything that moves or switches hardware asks for confirmation. That covers
  slew, park, sequence stop, warming, disconnect and flat light. Disconnecting
  a device repeats the cockpit's warning that some drivers will not reconnect
  without a power cycle.
- A command that N.I.N.A. refuses (409/502 from the cockpit) is shown verbatim,
  never retried silently.
- The control paths have not yet run against connected hardware, even in the
  cockpit. They are proven there first, then enabled in the app.

## Red light mode

The whole UI turns to dark red on black: `#FF5A4E` text on `#000000`. It is
switched by hand, and it can come on by itself while a session is running.
allskyhub will adopt it, so it is built as a self-contained theme.

## Push

The app uses Firebase Cloud Messaging, as allskyhub does. Bortle sends a
notification when:
- a hold waits for an answer,
- a development has finished or failed,
- the night was ended or aborted,
- the plugin queue has stopped draining,
- the clouds came in (see allskyhub below).

Until push exists, the app refreshes when it is opened and polls the Telescope
tab while it is visible.

## allskyhub

The two apps share a design language:
- the bottom bar,
- the dark sky theme (`#04060F` background, `#7AA2F7` accent),
- Space Grotesk for display text.

Bortle uses allskyhub's public API (`/api/v1/public`, no auth):
- the cameras near the user's site, picked in the profile;
- their measured cloud cover and SQM, kept as a measured condition of each
  session and shown live in the Telescope tab;
- later, the astro weather and the event calendar, compared against Bortle's
  own planner weather before anything is switched.

## Phases

1. **Companion**:
   - login and server picker
   - Tonight
   - holds
   - Gallery with run progress
   - sessions and profile
   - red light mode

   Acceptance: a Flutter integration test against an isolated Bortle instance
   signs in, answers a hold and opens a run.
2. **The night**:
   - Plan through to the sequence in N.I.N.A.
   - Telescope Overview, Frames and History
   - push
3. **At the rig**:
   - Telescope Control, every device screen
   - enabled once the cockpit's control paths have been proven on connected
     hardware
4. **The rest**:
   - A/B compare and the composite designer (tablet-first)
   - the operator pages

## Build and release

- Codemagic builds both platforms, as it does for allskyhub. It gets an app
  of its own that points at this repository, with its own `codemagic.yaml`.
- Signing secrets stay out of this repository.
- A test channel ships through a dart-define. There are no flavors.

The store accounts are shared with allskyhub. The maintainer decided on
2026-10-28 to share the keys as well:
- One App Store Connect API key and one Codemagic API key serve both apps.
- The team's iOS distribution certificate is shared too. Apple limits how many
  distribution certificates a team may have.

No key is copied anywhere. The allskyhub hub keeps them in its vault and, under
admin → "bortle", does three things:
- registers the bundle id `eu.bortle.app` with Apple and reports whether the
  App Store record exists;
- adds a Codemagic app for this repository in the same team, and fills its
  variable group `bortle_store` with these keys:
  - `APP_STORE_CONNECT_PRIVATE_KEY`
  - `APP_STORE_CONNECT_KEY_IDENTIFIER`
  - `APP_STORE_CONNECT_ISSUER_ID`
  - `CERTIFICATE_PRIVATE_KEY`
- starts the workflow `ios-release` on `main`.

`codemagic.yaml` at the repository root reads that group.

Done by the maintainer, by hand:
- create the App Store record for `eu.bortle.app`;
- for Android, a separate upload keystore, and the first AAB uploaded by hand
  in the Play Console. The API works only after that.

Still open:
- pushing the store listing,
- TestFlight groups,
- Android builds.

**Firebase:** one project per app.

### Keys and a public repository

This repository is public. The `bortle_store` group holds two keys that cover
the whole team: the App Store Connect key and the key of the distribution
certificate. A build that could be started from someone else's code would hand
both keys to them. So:

- `codemagic.yaml` stays manual only. It has no `triggering` section and
  never a pull request trigger: a build of a pull request from a fork would
  expose both keys.
- GitHub Actions workflows never receive store keys or signing keys. A
  workflow that runs on `pull_request` gets no secret at all, and
  `pull_request_target` is not used.
- A change to either rule needs the maintainer's explicit approval.
