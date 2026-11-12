import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/app_state.dart';
import 'package:nuist_aio/src/profile/avatar_store.dart';
import 'package:nuist_aio/src/profile/profile_header.dart';
import 'package:nuist_aio/src/profile/student_profile.dart';
import 'package:nuist_aio/src/services/site_registry.dart';

import 'service_sessions_test.dart' show FakeSession;

const profile = {
  'name': '测试姓名',
  'studentNumber': '00001234',
  'college': '测试学院',
  'major': '测试专业',
  'grade': '2024级',
  'className': '测试班',
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('nuist-profile-test-');
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({
      'nuist.portal.session.v1': jsonEncode({
        'version': 2,
        'accountKey': 'a' * 64,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'displayName': '门户姓名',
      }),
    });
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  AppState state({FakeSession? teaching}) => AppState(
    verifyPortal: () async => true,
    avatarStore: AvatarStore(directory: () async => temp),
    teachingSession:
        teaching ??
        FakeSession((_, _) async => {'ok': true, 'profile': profile}),
    cardSession: FakeSession((_, _) async => {'ok': true, 'ready': true}),
  );
  Future<XFile> photo() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const Color(0xff345678), BlendMode.src);
    final picture = recorder.endRecording(),
        image = await picture.toImage(80, 40);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return XFile.fromData(data!.buffer.asUint8List(), name: 'source.png');
  }

  test(
    'after credential probes profile is saved separately and restored securely',
    () async {
      final teaching = FakeSession(
        (task, _) async => task == 'semesters'
            ? {'ok': true}
            : {'ok': true, 'profile': profile},
      );
      final s = state(teaching: teaching);
      await s.load();
      await s.connectCampusServices(synchronizeData: false);
      expect(teaching.calls, ['semesters', 'studentProfile']);
      expect(s.studentProfile!.studentNumber, '00001234');
      expect(s.schedule, isNull);
      final restored = state();
      await restored.load();
      expect(restored.studentProfile!.major, '测试专业');
      expect(restored.avatarColor, s.avatarColor);
      s.dispose();
      restored.dispose();
    },
  );
  test('profile failure does not invalidate teaching credentials or another service', () async {
    final s = state(
      teaching: FakeSession((task, _) async {
        if (task == 'studentProfile') throw const FormatException('failed');
        return {'ok': true};
      }),
    );
    await s.load();
    await s.connectCampusServices(synchronizeData: false);
    expect(
      s.sitePhase(SchoolSites.get(SchoolSiteId.teaching)),
      SitePhase.ready,
    );
    expect(
      s.sitePhase(SchoolSites.get(SchoolSiteId.campusCard)),
      SitePhase.ready,
    );
    expect(s.studentProfile, isNull);
    expect(s.profileNotice, isNotNull);
    s.dispose();
  });
  test(
    'account reset refuses late student data and clears cached identity',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      final s = state(teaching: FakeSession((_, _) => pending.future));
      await s.load();
      final work = s.syncStudentProfile();
      await s.clearPrivateData();
      pending.complete({'ok': true, 'profile': profile});
      await work;
      expect(s.studentProfile, isNull);
      expect(s.syncingProfile, false);
      expect(await s.sessions.readProfile(), isNull);
      s.dispose();
    },
  );
  test(
    'photo is normalized, copied privately and owner-bound across restart',
    () async {
      final s = state();
      await s.load();
      final source = await photo();
      await s.saveAvatar(source, generation: s.sessionGeneration);
      final codec = await ui.instantiateImageCodec(s.avatarBytes!),
          frame = await codec.getNextFrame();
      expect(frame.image.width, 512);
      expect(frame.image.height, 512);
      frame.image.dispose();
      codec.dispose();
      final restored = state();
      await restored.load();
      expect(restored.avatarBytes, s.avatarBytes);
      await s.clearPrivateData();
      expect(await s.avatars.read(), isNull);
      expect(await s.sessions.avatarOwner(), isNull);
      expect(s.avatarBytes, isNull);
      s.dispose();
      restored.dispose();
    },
  );
  test(
    'cached identity and photo are not restored for another account',
    () async {
      final s = state();
      await s.load();
      await s.syncStudentProfile();
      await s.saveAvatar(await photo(), generation: s.sessionGeneration);
      const secure = FlutterSecureStorage();
      await secure.write(
        key: 'nuist.portal.session.v1',
        value: jsonEncode({
          'accountKey': 'b' * 64,
          'capturedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      final changed = state();
      await changed.load();
      expect(changed.studentProfile, isNull);
      expect(changed.avatarBytes, isNull);
      s.dispose();
      changed.dispose();
    },
  );
  test('invalid photo preserves the existing avatar and late selections are ignored', () async {
    final s = state();
    await s.load();
    await s.saveAvatar(await photo(), generation: s.sessionGeneration);
    final original = s.avatarBytes;
    await expectLater(
      s.saveAvatar(
        XFile.fromData(Uint8List.fromList([1, 2, 3])),
        generation: s.sessionGeneration,
      ),
      throwsA(anything),
    );
    expect(s.avatarBytes, original);
    final old = s.sessionGeneration;
    await s.clearPrivateData();
    await s.saveAvatar(await photo(), generation: old);
    expect(s.avatarBytes, isNull);
    s.dispose();
  });
  testWidgets(
    'compact profile presents real fields and supports large text on narrow screens',
    (tester) async {
      final semantics = tester.ensureSemantics();

      final s = state();
      await s.load();
      s.studentProfile = StudentProfile.fromJson(profile);
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: ProfileHeader(state: s, onLogin: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测试姓名'), findsOneWidget);
      expect(find.text('学号：00001234'), findsOneWidget);
      expect(find.text('学院  测试学院'), findsOneWidget);
      expect(find.text('课表已导入'), findsNothing);
      final avatarNode = tester.getSemantics(
        find.bySemanticsLabel(RegExp('更换本地头像')),
      );
      expect(avatarNode.label, isNot(contains('00001234')));
      expect(avatarNode.rect.width, lessThanOrEqualTo(70));
      expect(tester.takeException(), isNull);
      expect(avatarLetters('王小明'), '小明');
      expect(avatarLetters('A👩‍💻'), 'A👩‍💻');
      await tester.pumpWidget(const SizedBox());
      s.dispose();
      semantics.dispose();
    },
  );
}
