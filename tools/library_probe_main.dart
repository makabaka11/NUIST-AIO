// Manual, read-only development probe. Never the shipped application entrypoint.
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/library/library.dart';
import 'package:nuist_aio/src/library/library_page.dart';
import 'package:nuist_aio/src/dashboard/holiday.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('正在验证图书馆只读会话…'))),
    ),
  );
  if (const bool.fromEnvironment('LIBRARY_PROBE_SESSION_ONLY')) {
    final session = NativeLibrarySession();
    var ready = false;
    try {
      final probe = await session.query('probe', {});
      final loans = await session.query('loans', {});
      ready = probe['ready'] == true && loans['ok'] == true;
      debugPrint(
        'NUIST_LIBRARY_SESSION ${jsonEncode({'ready': ready, 'count': loans['total']})}',
      );
    } catch (_) {
      debugPrint('NUIST_LIBRARY_SESSION {"ready":false}');
    }
    if (const bool.fromEnvironment('LIBRARY_PROBE_OFFICIAL_PAGE')) {
      runApp(
        MaterialApp(
          home: LibraryLoginPage(
            state: AppState(librarySession: session)..libraryVerified = ready,
          ),
        ),
      );
      return;
    }
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text(ready ? '图书馆只读会话验证通过。' : '图书馆需要在官方页面完成认证。')),
        ),
      ),
    );
    return;
  }
  final state = AppState();
  await state.load();
  await state.connectLibrary();
  await state.syncCalendar();
  final now = DateTime.now().toUtc().add(const Duration(hours: 8));
  SchoolHoliday? holiday;
  if (state.schoolCalendar != null) {
    holiday = SchoolHoliday.next(state.schoolCalendar!, now);
  }
  final summary = {
    'libraryReady': state.libraryVerified,
    'loansRead': state.libraryLoans != null,
    'count': state.libraryLoans?.books.length,
    'calendarRead': state.schoolCalendar != null,
    'nextHoliday': holiday?.name,
    'holidayDate': holiday?.start.toIso8601String().substring(0, 10),
  };
  debugPrint('NUIST_LIBRARY_PROBE ${jsonEncode(summary)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            state.libraryVerified ? '图书馆只读会话验证通过。' : '图书馆需要在官方页面完成认证。',
          ),
        ),
      ),
    ),
  );
}
