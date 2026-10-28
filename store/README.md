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
appstore/<language>/name.txt          ≤ 30
appstore/<language>/subtitle.txt      ≤ 30
appstore/<language>/keywords.txt      ≤ 100, comma separated
appstore/<language>/promotional_text.txt ≤ 170
appstore/screenshots/<language>/      1320 × 2868 (6.9″), eight
```

Languages: `de-DE` (default) and `en-US`.

Regenerate:

```sh
uv run --no-project --with pillow python tool/store_graphics.py
SCREENSHOT_IMAGES=<dir with images.json + jpgs> SCREENSHOT_OUT=store \
  flutter test test/screenshots_test.dart
```

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
  - deletion: the user revokes a device under Profile; the account is deleted on request
    to info@bortle.eu.
  - the FCM device token, for app functionality (push).
- **Account deletion URL:** not required (the app does not create accounts), but
  https://bortle.eu/privacy names how.
- **Category:** Photography (Play); Photo & Video, second Utilities (App Store). Contact
  info@bortle.eu, website and support URL https://bortle.eu.
- **App Store age rating:** none of the content questions apply (no web browser, no chat,
  no other people's content).
- **App Store review:** the same test account as for Play, in the review contact.
