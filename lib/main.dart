import 'package:flutter/material.dart';

import 'src/accounts/accounts.dart' show Electricity;
import 'src/app.dart';
import 'src/app_state.dart';
import 'src/network/network_lifecycle.dart';
import 'src/notifications/notification_center.dart';
import 'src/services/site_registry.dart';
import 'src/services/sso_diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SsoDiagnostics.reset();
  SsoDiagnostics.record('app', 'startup');
  registerCampusLicenses();
  final state = AppState();
  await state.load();
  // 系统通知中心：复用已注册站点的只读查询，不新增任何认证流程。
  state.notificationCenter = _campusNotificationCenter(state);
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
    state.notificationCenter?.start();
  });
}

CampusNotificationCenter _campusNotificationCenter(AppState state) {
  // 学习通轮询不得触发交互式课程确认：仅在已完成一次扫描后进行。
  Future<List<ChaoxingWorkSnapshot>?> fetchChaoxingWork() async {
    final repo = state.chaoxing;
    if (!repo.verified ||
        repo.busy ||
        repo.scanTerm == null ||
        repo.selection == null ||
        repo.busyUntil?.isAfter(DateTime.now()) == true) {
      return null;
    }
    try {
      await state.refreshChaoxing();
    } catch (_) {
      return null;
    }
    if (repo.pendingSelection != null) {
      // 学期课程名单变化引发的确认弹窗自动取消，交由用户手动处理。
      repo.confirmCourseSelection(null);
      return null;
    }
    if (!repo.verified) return null;
    return [
      for (final item in repo.items.where((item) => item.kind == 'work'))
        ChaoxingWorkSnapshot(
          key: item.url?.toString() ?? '${item.courseKey}:work:${item.title}',
          title: item.title,
          course: item.course,
          group: item.group,
          deadline: item.deadline,
        ),
    ];
  }

  Future<List<Map<String, dynamic>>?> fetchBulletins() async {
    try {
      final result = await state.bulletins.query(state.networkMode, 'list');
      return (result.data['rows'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> fetchExams() async {
    final session = state.teachingSession;
    if (state.connectedAt == null || !session.available) return null;
    try {
      final semesters = await session.query('semesters', {});
      final term = semesters['current'];
      if (term is! String) return null;
      final data = await session.query('exams', {
        'params': {'term': term, 'plan': null},
      });
      if (data['ok'] != true) return null;
      return (data['rows'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> fetchGrades() async {
    final session = state.teachingSession;
    if (state.connectedAt == null || !session.available) return null;
    try {
      final data = await session.query('grades', {
        'params': {'term': null, 'plan': null},
      });
      if (data['ok'] != true) return null;
      return (data['rows'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<ElectricityReading?> fetchElectricity() async {
    if (state.dorm == null || !state.cardSession.available) return null;
    try {
      final data = await state.cardSession.query(
        'electricity',
        state.accountArguments(),
      );
      final raw = data['electricity'];
      if (raw is! Map) return null;
      final reading = Electricity.fromJson(Map<String, dynamic>.from(raw));
      // 顺带更新应用内账户缓存，保持展示一致。
      await state.saveAccounts({
        'electricity': raw,
      }, generation: state.sessionGeneration);
      return ElectricityReading(value: reading.primaryValue, unit: reading.unit);
    } catch (_) {
      return null;
    }
  }

  return CampusNotificationCenter(
    settings: state.notifications,
    accountWatch: state,
    accountGeneration: () => state.sessionGeneration,
    identityPhase: () =>
        state.sitePhase(SchoolSites.get(SchoolSiteId.identity)),
    fetchChaoxingWork: fetchChaoxingWork,
    fetchBulletins: fetchBulletins,
    fetchExams: fetchExams,
    fetchGrades: fetchGrades,
    fetchElectricity: fetchElectricity,
  );
}
