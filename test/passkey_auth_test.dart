import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/auth/account_binding_page.dart';
import 'package:nuist_aio/src/auth/session_store.dart';
import 'package:nuist_aio/src/services/site_registry.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'service_sessions_test.dart' show FakeSession;

final bundle = <String, dynamic>{
  'rpId': 'authserver.nuist.edu.cn',
  'credentialId': 'synthetic',
  'privateKeyPkcs8Pem': 'synthetic private key',
  'userId': 'synthetic',
  'anonbiometricsd': 'synthetic',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({
      'nuist.portal.session.v1': jsonEncode({'accountKey': 'a' * 64}),
    });
  });
  test(
    'failed main authentication skips every child without reporting ready',
    () async {
      final child = FakeSession(
        (_, _) async => throw StateError('must not run'),
      );
      final state = AppState(
        verifyPortal: () async => false,
        teachingSession: child,
        cardSession: child,
        librarySession: child,
        portalSession: child,
      );
      state.connectedAt = DateTime.now();
      await state.connectCampusServices();
      expect(child.calls, isEmpty);
      expect(
        state.sitePhase(SchoolSites.get(SchoolSiteId.chaoxing)),
        SitePhase.planned,
      );
      for (final site in SchoolSites.automatic.where(
        (site) => site.id != SchoolSiteId.chaoxing,
      )) {
        expect(state.sitePhase(site), SitePhase.failed);
        expect(state.siteMessages[site.id], contains('已跳过'));
      }
      expect(
        state.sitePhase(SchoolSites.get(SchoolSiteId.identity)),
        SitePhase.failed,
      );
      expect(state.servicesNotice, contains('通行密钥自动登录'));
      expect(state.connectingServices, false);
      state.dispose();
    },
  );
  test(
    'late portal result after account reset cannot start child requests',
    () async {
      final pending = Completer<bool>();
      final child = FakeSession(
        (_, _) async => throw StateError('must not run'),
      );
      final state = AppState(
        verifyPortal: () => pending.future,
        teachingSession: child,
        cardSession: child,
        librarySession: child,
      );
      state.connectedAt = DateTime.now();
      final work = state.connectCampusServices();
      await state.clearPrivateData();
      await state.resetServiceSessions();
      pending.complete(true);
      await work;
      expect(child.calls, isEmpty);
      expect(state.servicesNotice, isNull);
      state.dispose();
    },
  );
  test(
    'concurrent renewal requests share one bounded login operation',
    () async {
      final pending = Completer<bool>();
      int calls = 0;
      final state = AppState(
        verifyPortal: () {
          calls++;
          return pending.future;
        },
      );
      final a = state.ensurePortal(), b = state.ensurePortal();
      expect(calls, 1);
      pending.complete(true);
      expect(await a, true);
      expect(await b, true);
      state.dispose();
    },
  );
  test(
    'foreground maintenance is throttled and does not initialize child sites',
    () async {
      var calls = 0;
      final child = FakeSession(
        (_, _) async => throw StateError('must not run'),
      );
      final state = AppState(
        verifyPortal: () async {
          calls++;
          return false;
        },
        cardSession: child,
        teachingSession: child,
        librarySession: child,
      );
      state.connectedAt = DateTime.now();
      state.passkeyEnabled = true;
      await state.maintainPortal();
      await state.maintainPortal();
      expect(calls, 1);
      expect(child.calls, isEmpty);
      expect(state.servicesNotice, contains('重新创建通行密钥'));
      state.dispose();
    },
  );
  test('secure credential is owner scoped and disabling deletes it', () async {
    final store = SessionStore();
    await store.savePasskey(bundle, owner: 'a' * 64);
    expect(await store.readPasskey(), bundle);
    final state = AppState();
    await state.refreshPasskey();
    expect(state.passkeyEnabled, true);
    await state.disablePasskey();
    expect(await store.readPasskey(), isNull);
    expect(state.passkeyEnabled, false);
    await expectLater(
      store.savePasskey(bundle, owner: 'b' * 64),
      throwsFormatException,
    );
    state.dispose();
  });
  test('changing the primary account clears the local credential', () async {
    final state = AppState();
    await state.sessions.savePasskey(bundle, owner: 'a' * 64);
    await state.refreshPasskey();
    await state.clearPrivateData();
    expect(await state.sessions.readPasskey(), isNull);
    expect(state.passkeyEnabled, false);
    state.dispose();
  });
  testWidgets(
    'account binding collects primary, passkey, learning and VPN settings',
    (tester) async {
      final state = AppState();
      await tester.pumpWidget(
        MaterialApp(home: AccountBindingPage(state: state)),
      );
      await tester.pumpAndSettle();
      expect(find.text('账号绑定'), findsOneWidget);
      expect(find.text('统一认证账号'), findsOneWidget);
      expect(find.text('使用通行密钥自动登录'), findsOneWidget);
      expect(find.text('学习通账号'), findsOneWidget);
      expect(find.text('学校 WebVPN'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    },
  );
}
