import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:nuist_aio/src/chaoxing/chaoxing.dart';
import 'package:nuist_aio/src/chaoxing/current_term.dart';
import 'package:nuist_aio/src/chaoxing/course_selection.dart';
import 'package:nuist_aio/src/chaoxing/course_selection_dialog.dart';

final matched = {
  'courseId': '1',
  'classId': '2',
  'cpi': '3',
  'title': '高等数学',
  'teacher': '教师甲',
};
final missed = {
  ...matched,
  'courseId': '4',
  'title': '数学补充课程',
  'teacher': '教师乙',
};
final guidance = {...matched, 'courseId': '5', 'title': '选课指导'};
ChaoxingTermScope scope([String name = '高等数学']) => ChaoxingTermScope.fromData({
  'term': '2026-2027-1',
  'rows': [
    {'KCM': name, 'SKJS': '教师甲'},
    {'KCM': name, 'SKJS': '教师甲'},
  ],
});
ChaoxingRepository repository({
  List<Map<String, dynamic>>? raw,
  List<String>? reads,
}) {
  return ChaoxingRepository(
    courseGap: Duration.zero,
    currentTerm: () async => scope(),
    documentReader: (uri, task) async {
      reads?.add('$task:${uri.queryParameters['courseid'] ?? ''}');
      if (task == 'courses') {
        return {
          'ok': true,
          'courses': raw ?? [matched, missed, guidance],
        };
      }
      if (task == 'meta') {
        return {'ok': true, 'stuenc': 'a' * 32, 'workEnc': 'b' * 32};
      }
      if (task == 'progress') {
        return {
          'ok': true,
          'progress': {'completed': 1, 'total': 2},
        };
      }
      return {'ok': true, 'items': []};
    },
  )..selectionOwner = () async => 'owner-a';
}

Future<void> waitForSelection(ChaoxingRepository r) async {
  if (r.pendingSelection != null) return;
  final ready = Completer<void>();
  void listen() {
    if (r.pendingSelection != null && !ready.isCompleted) ready.complete();
  }

  r.addListener(listen);
  await ready.future.timeout(const Duration(seconds: 3));
  r.removeListener(listen);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });
  test('selection deduplicates teaching rows and excludes guidance while retaining unmatched courses', () {
    final p = ChaoxingCourseSelection(scope(), [matched, missed, guidance]);
    expect(p.teaching.length, 1);
    expect(p.options.length, 2);
    expect(p.automatic, {'1:2'});
    expect(p.options.first.teacher, '教师甲');
    expect(
      p.fingerprint,
      ChaoxingCourseSelection(scope(), [guidance, missed, matched]).fingerprint,
    );
  });
  test('scan waits for confirmation, manual overrides persist, force editing can cancel, roster changes need review', () async {
    final reads = <String>[];
    final r = repository(reads: reads);
    await r.verify();
    final scanning = r.refresh();
    await waitForSelection(r);
    expect(reads.where((s) => s.startsWith('meta')), isEmpty);
    expect(r.selectedCourseKeys, {'1:2'});
    r.confirmCourseSelection({'4:2', '5:2', 'unknown'});
    await scanning;
    expect(r.courses.single.key, '4:2');
    expect(reads.where((s) => s.startsWith('meta')), ['meta:4']);
    await r.close();
    final cold = repository();
    await cold.verify();
    await cold
        .refresh(); // Saved confirmation is scoped to the same owner/roster.
    expect(cold.pendingSelection, isNull);
    expect(cold.courses.single.key, '4:2');
    final editing = cold.refresh(confirmCourses: true);
    await waitForSelection(cold);
    expect(cold.selectedCourseKeys, {'4:2'});
    cold.confirmCourseSelection(null);
    await editing;
    expect(cold.courses.single.key, '4:2');
    cold.currentTerm = () async => scope('高等数学（基础）');
    final changed = cold.refresh();
    await waitForSelection(cold);
    cold.confirmCourseSelection({});
    await changed;
    expect(cold.courses, isEmpty);
    expect(cold.selectedCourseCount, 0);
    r.dispose();
    cold.dispose();
  });
  test('account removal cancels pending confirmation and cannot restore prior selections', () async {
    final r = repository();
    await r.verify();
    final scan = r.refresh();
    await waitForSelection(r);
    await r.close(clearCookies: true);
    r.confirmCourseSelection({'1:2'});
    await scan;
    expect(r.courses, isEmpty);
    expect(r.verified, false);
    final next = repository();
    await next.verify();
    final newScan = next.refresh();
    await waitForSelection(next);
    next.confirmCourseSelection(null);
    await newScan;
    r.dispose();
    next.dispose();
  });
  test('saved choices cannot leak to a different account', () async {
    final r = repository();
    await r.verify();
    final first = r.refresh();
    await waitForSelection(r);
    r.confirmCourseSelection({'4:2'});
    await first;
    r.selectionOwner = () async => 'owner-b';
    final second = r.refresh();
    await waitForSelection(r);
    expect(r.selectedCourseKeys, {'1:2'});
    r.confirmCourseSelection(null);
    await second;
    r.dispose();
  });
  testWidgets(
    'dialog shows teacher sources, live counts and manual checkbox selection',
    (tester) async {
      final proposal = ChaoxingCourseSelection(scope(), [
        matched,
        missed,
        guidance,
      ]);
      Set<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<Set<String>>(
                    context: context,
                    builder: (_) => ChaoxingSelectionDialog(
                      selection: proposal,
                      selected: proposal.automatic,
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('教务 1 门 · 学习通可选 2 门'), findsOneWidget);
      expect(find.text('学习通教师：教师甲'), findsOneWidget);
      expect(find.text('学习通教师：教师乙'), findsOneWidget);
      expect(find.text('选课指导'), findsNothing);
      await tester.tap(find.text('数学补充课程'));
      await tester.pumpAndSettle();
      expect(find.text('确认并扫描 2 门'), findsOneWidget);
      await tester.tap(find.text('确认并扫描 2 门'));
      await tester.pumpAndSettle();
      expect(result, {'1:2', '4:2'});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('selection remains usable on narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final proposal = ChaoxingCourseSelection(scope(), [matched, missed]);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ChaoxingSelectionDialog(
                  selection: proposal,
                  selected: proposal.automatic,
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('确认学习通课程'), findsNothing);
  });

  testWidgets(
    'host defers confirmation until official login route closes and removes only its own dialog',
    (tester) async {
      final r = repository();
      late BuildContext home;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [chaoxingSelectionRoutes],
          home: Builder(
            builder: (context) {
              home = context;
              return ChaoxingSelectionHost(
                repository: r,
                child: const Scaffold(body: Text('主页')),
              );
            },
          ),
        ),
      );
      final navigator = Navigator.of(home);
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('官方登录')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await r.verify();
      final scan = r.refresh();
      await tester.pumpAndSettle();
      expect(r.pendingSelection, isNotNull);
      expect(find.text('确认学习通课程'), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('确认学习通课程'), findsOneWidget);
      await r.close(clearCookies: true);
      await tester.pumpAndSettle();
      await scan;
      expect(find.text('确认学习通课程'), findsNothing);
      expect(find.text('主页'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      r.dispose();
    },
  );
}
