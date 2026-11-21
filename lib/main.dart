import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_state.dart';
import 'src/network/network_lifecycle.dart';
import 'src/services/sso_diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SsoDiagnostics.reset();
  SsoDiagnostics.record('app', 'startup');
  registerCampusLicenses();
  final state = AppState();
  await state.load();
  runApp(
    CampusNetworkLifecycle(
      state: state,
      child: CampusApp(state: state),
    ),
  );
  // Public announcements are optional content: fetch after the first frame so
  // they never delay rendering, onboarding or campus-service initialization.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    state.announcements.refreshOnStartup();
  });
}
