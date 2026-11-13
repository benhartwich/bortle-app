# Store listings

Everything the stores show, kept here so a listing is reviewed like code. The allskyhub
hub pushes it with the shared developer accounts (docs/CONCEPT.md, "Keys and a public
repository"); the layout is the same as allskyhub's `app/store`.

```
play/icon.png                         512 × 512, from assets/icon (tool/store_graphics.py)
play/<language>/title.txt             ≤ 30
play/<language>/short_description.txt ≤ 80
play/<language>/full_description.txt  ≤ 4000, also the App Store description
play/<language>/feature.png           1024 × 500 (tool/store_graphics.py)
play/<language>/screenshots/          1080 × 2400, eight (test/screenshots_test.dart)
play/<language>/tablet7/, tablet10/   tablets, see below
appstore/<language>/name.txt          ≤ 30
appstore/<language>/subtitle.txt      ≤ 30
appstore/<language>/keywords.txt      ≤ 100, comma separated
appstore/<language>/promotional_text.txt ≤ 170
appstore/screenshots/<language>/      1320 × 2868 (6.9″), eight; ipad/ below
appstore/review_notes.txt             ≤ 4000, English, the App Review notes (no credentials)
```

Languages: `de-DE` (default) and `en-US`.

### Tablets (since 0.7.0)

The app lays itself out for tablets (lib/layout.dart: a rail from 600 dp, list and detail
side by side from 840 dp) and is built for iPad as well as iPhone
(`TARGETED_DEVICE_FAMILY = "1,2"`). The tablet shots show what the width buys: the plan
beside the recommendations, the run beside the gallery, the rig's controls beside the
live frame.

```
play/<language>/tablet7/                1920 × 1080, eight (960 × 540 dp at 2×)
play/<language>/tablet10/               2560 × 1440, eight (1280 × 720 dp at 2×)
appstore/screenshots/<language>/ipad/   2064 × 2752 (13″ iPad, upright), eight
                                        (1032 × 1376 pt at 2×)
```

Why these sizes:

- **Play** takes JPEG or 24-bit PNG without alpha, each side 320–3840 px, the long side at
  most twice the short one. For tablets and large screens it asks for 16:9 (landscape) or
  9:16 (portrait) with each side at least 1080 px; Play shows an app as "designed for
  tablets" only with these. Both tablet sizes are 16:9 landscape, both above 1080 px and
  below 3840 px. Landscape because that is where the two-pane layout shows (an upright 7″
  tablet at 600 dp gets the rail but no second pane).
- **App Store** builds every iPad size from the 13″ one: 2064 × 2752 upright (2752 × 2064
  on its side, 2048 × 2732 also accepted). At 1032 pt the iPad is wide enough for two
  panes upright as well. Needed once the iPad build ships.

Every screenshot is written as an RGB PNG without alpha; both stores refuse one with an
alpha channel. (The phone shots from before 0.7.0 carried an alpha channel, opaque
everywhere; it was dropped without changing a pixel.)

Regenerate:

```sh
uv run --no-project --with pillow python tool/store_graphics.py
SCREENSHOT_IMAGES=<dir with images.json + jpgs> SCREENSHOT_OUT=store \
  flutter test test/screenshots_test.dart
# only some devices, the others stay as they are:
SCREENSHOT_DEVICES=tablet7,tablet10,ipad SCREENSHOT_IMAGES=… SCREENSHOT_OUT=store \
  flutter test test/screenshots_test.dart
```

Devices: `android`, `ios` (phones), `tablet7`, `tablet10`, `ipad`. `FLUTTER_ROOT` must
point at the SDK (the test loads Roboto and the Material icons from its cache).

`SCREENSHOT_IMAGES` holds the maintainer's own finished pictures, which stay out of the
repository: `images.json` is a list of `{title, title_en, recipe, file, hours}` (the
gallery's titles in German and English, the develop recipe, the JPG beside it, the
integration in hours, read from the stacked masters as the gallery does). The tablet
plan also shows the sky around each recommendation; put the DSS2 cutouts the planner
serves next to them as `dss_<ra>_<dec>.jpg` (RA and Dec with four decimals, 2.6773° ×
1.7893°, e.g. from `services/orchestrator/sky_preview.cutout`). Without them the
thumbnails stay black with the frame drawn.

The texts say what the app does today. Device control is named as missing until it
ships; change the descriptions in the same commit that ships them.

## What only the Play Console takes

The API cannot fill these; they are answered once by hand.

- **Privacy policy:** https://bortle.eu/privacy
- **App access:** every function needs a sign-in. Give review a test account on bortle.eu
  without admin rights (it sees Tonight, Plan, Gallery; the Telescope tab tells it that
  only the operator runs the telescope).
- **Ads:** none.
- **Content rating:** utility, no user-to-user content, no violence, no gambling.
- **Target audience:** 18 and over (not designed for children).
- **Data safety:**
  - collected: user name or e-mail address and password for signing in (account
    management, required), and the photos and files the user's own Bortle shows (app
    functionality). They go only to the server the user entered.
  - not shared with third parties; no tracking; no advertising ID.
  - encrypted in transit: yes for bortle.eu (HTTPS). An own install on the home network
    may use plain HTTP, which the app warns about outside the home network.
  - deletion: the user revokes a device under Profile; the account deletes itself, with
    all its data, in the app (More → Delete account) or on the web (Profile), or on
    request to info@bortle.eu.
  - the FCM device token, for app functionality (push).
  - **approximate location** (since the tools without an account): used on the
    phone for twilight, the moon and altitudes. Only when the weather tab is opened is
    it sent, rounded to 0.1° (about 10 km), to bortle.eu, which asks Open-Meteo and
    7Timer! as service providers and keeps nothing. Play: "Approximate location –
    collected, processed ephemerally, not shared, optional, app functionality". App
    Store privacy: "Coarse Location – App Functionality, not linked to the user, no
    tracking". The permission text is in ios/Runner/Info.plist
    (NSLocationWhenInUseUsageDescription); Android asks for ACCESS_COARSE_LOCATION only.
- **Account deletion URL:** https://bortle.eu/delete-account (in-app deletion since 0.4.0).
- **Category:** Photography (Play); Photo & Video, second Utilities (App Store). Contact
  info@bortle.eu, website and support URL https://bortle.eu.
- **App Store age rating:** none of the content questions apply (no web browser, no chat,
  no other people's content).
- **App Store review:** the same test account as for Play, entered in App Store Connect's
  Sign-In Information (never in the repo); the notes come from `appstore/review_notes.txt`.
