import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_state.dart';
import 'src/services/sso_diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SsoDiagnostics.reset();
  SsoDiagnostics.record('app', 'startup');
  registerCampusLicenses();
  final state = AppState();
  await state.load();
  runApp(CampusApp(state: state));
}
