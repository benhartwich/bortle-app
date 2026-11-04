// Keeps the screenshots of integration_test/store_screenshots_test.dart as
// build/screenshots/<name>.png (codemagic.yaml, store-screenshots).
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    File('build/screenshots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return true;
  },
);
