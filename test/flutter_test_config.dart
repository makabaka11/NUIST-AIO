import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

// Widget tests do not have a native application bundle. Supply its metadata;
// release HTTP remains mocked by Flutter and dedicated updater tests inject it.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  PackageInfo.setMockInitialValues(
    appName: '信大 AIO',
    packageName: 'com.retrsoft.nuistaio',
    version: '0.3.5',
    buildNumber: '14',
    buildSignature: '',
  );
  await testMain();
}
