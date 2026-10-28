# Bortle for Android and iOS

The native app for [Bortle](https://bortle.eu), the astrophotography cockpit
that covers planning, capture, quality control, stacking and the finished
image. The app does everything the web cockpit does, against the hosted
instance at bortle.eu or against your own install: you enter its address when
you sign in.

**Status: stage 2 of 4, not yet in the stores.** Built: sign-in against bortle.eu
or an own install, *Tonight*, answering holds, *Gallery* with the runs and their
progress, *Plan* (altitude, moon, clouds, the sequence to N.I.N.A. with the develop
level), the *Telescope* tab with overview, every frame of the night and its curves,
stopping the sequence and ending the night through N.I.N.A., signed-in devices and
the red light mode. Device control (stage 3) and push are next;
[docs/CONCEPT.md](docs/CONCEPT.md) has the order.

```sh
flutter pub get
flutter analyze && flutter test
flutter run            # against https://bortle.eu, or enter your own address
```

## What it does

- **Tonight:** the night's state, running developments with their progress,
  the latest events, and holds that are waiting for your answer.
- **Plan:** an object, its altitude over your horizon, the moon, the clouds,
  and a ready N.I.N.A. sequence.
- **Telescope:** the night as it happens, from N.I.N.A.:
  - the latest frames with previews;
  - HFR, star count and guiding over the session;
  - the sequence, with start, stop and skip;
  - the equipment: mount, camera, focuser, guider, filter wheel, rotator,
    flat panel and dew heater.
- **Gallery:** finished images, the full log of every run, sharing, and
  developing again with different settings.
- **Red light mode** for working at the telescope.

## Safety

The app operates N.I.N.A. through Bortle. It never takes over N.I.N.A.'s safety
layer: parking on unsafe conditions, the meridian flip and the safety monitor
stay in N.I.N.A., and they keep working when the phone, the network or Bortle
is gone. Every command that moves or changes equipment asks for confirmation
first.

## Architecture in one paragraph

Flutter, Android and iOS. The app talks only to the Bortle cockpit, never to
the orchestrator behind it, because the cockpit is where Bortle checks who may
do what. You sign in with your account's email and password. The app then
receives a token for this device; you can see it and revoke it in your Bortle
profile. The code is deliberately plain:
- `StatefulWidget` with `FutureBuilder`;
- `Navigator`;
- one hand-written HTTP client;
- no code generation.

This matches the [allskyhub](https://allskyhub.org) app, which comes from the
same maintainer.

## AI-assisted development

This app is written with substantial help from an AI model (Anthropic's
Claude), working under the direction of the maintainer. Commits it co-wrote
carry a `Co-Authored-By: Claude` trailer. The maintainer, Benjamin Hartwich,
reviews, tests and maintains the code, and is accountable for it.

## License

[Apache License 2.0](LICENSE).

Bortle itself, the server, is licensed under AGPL-3.0. The app is a separate
work and uses a store-compatible license on purpose.
