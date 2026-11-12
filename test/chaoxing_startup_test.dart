import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/chaoxing/chaoxing.dart';
import 'package:nuist_aio/src/dashboard/dashboard_config.dart';
import 'package:nuist_aio/src/services/site_registry.dart';
import 'package:nuist_aio/src/shell.dart';

import 'service_sessions_test.dart'
    show FakeSession, teaching, card, fakeCalendar, fakeLibrary;

const course = {'courseId': '1', 'classId': '2', 'cpi': '3', 'title': '课程'};
AppState stateWith(
  ChaoxingRepository repository, {
  Future<bool> Function()? portal,
}) =>
    AppState(
        chaoxingRepository: repository,
        verifyPortal: portal ?? () async => true,
        teachingSession: teaching(),
        cardSession: FakeSession(
          (task, args) async => task == 'probe'
              ? {'ok': true, 'ready': true}
              : await card().query(task, args),
        ),
        librarySession: fakeLibrary(),
        portalSession: fakeCalendar(),
      )
      ..connectedAt = DateTime(2026)
      ..dashboardLayout = const DashboardLayout(
        disabled: {DashboardWidgetId.holiday},
      );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  Future<void> remember() =>
      SharedPreferencesAsync().setBool('chaoxing.connection.v1', true);

  testWidgets(
    'home startup restores saved Chaoxing while portal authentication is pending',
    (tester) async {
      await remember();
      final portal = Completer<bool>();
      var probes = 0;
      final repository = ChaoxingRepository(
        documentReader: (_, task) async {
          expect(task, 'courses');
          probes++;
          return {
            'ok': true,
            'courses': [course],
          };
        },
      );
      final state = stateWith(repository, portal: () => portal.future);
      await tester.pumpWidget(MaterialApp(home: CampusShell(state: state)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(probes, 1);
      expect(repository.verified, true);
      expect(state.connectingServices, true);
      expect(
        state.sitePhase(SchoolSites.get(SchoolSiteId.chaoxing)),
        SitePhase.ready,
      );
      portal.complete(false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.connectingServices, false);
      expect(repository.verified, true);
      expect(
        state.sitePhase(SchoolSites.get(SchoolSiteId.chaoxing)),
        SitePhase.ready,
      );
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  test(
    'never connected users make no Chaoxing requests during initialization',
    () async {
      var probes = 0;
      final repository = ChaoxingRepository(
        documentReader: (_, _) async {
          probes++;
          return {
            'ok': true,
            'courses': [course],
          };
        },
      );
      final state = stateWith(repository);
      await state.connectCampusServices(synchronizeData: false);
      expect(probes, 0);
      expect(
        state.sitePhase(SchoolSites.get(SchoolSiteId.chaoxing)),
        SitePhase.planned,
      );
      expect(
        state.sitePhase(SchoolSites.get(SchoolSiteId.teaching)),
        SitePhase.ready,
      );
      state.dispose();
    },
  );
  test('expired independent session cannot block other services and retry can recover', () async {
    await remember();
    var expired = true, probes = 0;
    final repository = ChaoxingRepository(
      documentReader: (_, _) async {
        probes++;
        return expired
            ? {'ok': false, 'code': 'auth'}
            : {
                'ok': true,
                'courses': [course],
              };
      },
    );
    final state = stateWith(repository);
    await state.connectCampusServices(synchronizeData: false);
    expect(probes, 1);
    expect(repository.verified, false);
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.chaoxing)),
      SitePhase.failed,
    );
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.teaching)),
      SitePhase.ready,
    );
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.campusCard)),
      SitePhase.ready,
    );
    expired = false;
    await state.connectCampusServices(synchronizeData: false);
    expect(probes, 2);
    expect(repository.verified, true);
    await repository.close(clearCookies: true);
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.chaoxing)),
      SitePhase.planned,
    );
    await state.connectCampusServices(synchronizeData: false);
    expect(probes, 2);
    state.dispose();
  });
  test('initialization never waits for course confirmation or a personal-data scan', () async {
    await remember();
    final tasks = <String>[];
    final repository = ChaoxingRepository(
      documentReader: (_, task) async {
        tasks.add(task);
        return {
          'ok': true,
          'courses': [course],
        };
      },
    );
    final state = stateWith(repository);
    await state.connectCampusServices();
    // Let the independent background stage reach its manual confirmation.
    await Future<void>.delayed(Duration.zero);
    expect(state.connectingServices, false);
    expect(repository.pendingSelection, isNotNull);
    expect(tasks, everyElement('courses'));
    expect(
      state.sitePhase(SchoolSites.get(SchoolSiteId.campusCard)),
      SitePhase.ready,
    );
    repository.confirmCourseSelection(null);
    await Future<void>.delayed(Duration.zero);
    state.dispose();
  });
  test(
    'onboarding session-only initialization never starts a data scan',
    () async {
      await remember();
      final tasks = <String>[];
      final repository = ChaoxingRepository(
        documentReader: (_, task) async {
          tasks.add(task);
          return {
            'ok': true,
            'courses': [course],
          };
        },
      );
      final state = stateWith(repository);
      await state.connectCampusServices(synchronizeData: false);
      expect(tasks, ['courses']);
      expect(repository.pendingSelection, isNull);
      state.dispose();
    },
  );
  test('account change rejects late startup probe and cancels data synchronization', () async {
    await remember();
    final response = Completer<Map<String, dynamic>>();
    final started = Completer<void>();
    final repository = ChaoxingRepository(
      documentReader: (_, _) {
        started.complete();
        return response.future;
      },
    );
    final state = stateWith(repository);
    final initialization = state.connectCampusServices();
    await started.future;
    await state.clearPrivateData();
    await state.resetServiceSessions();
    response.complete({
      'ok': true,
      'courses': [course],
    });
    await initialization;
    expect(repository.verified, false);
    expect(repository.courses, isEmpty);
    expect(repository.pendingSelection, isNull);
    expect(state.connectingServices, false);
    state.dispose();
  });
}
