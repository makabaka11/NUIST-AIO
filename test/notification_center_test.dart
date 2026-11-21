import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:nuist_aio/src/notifications/notification_center.dart';
import 'package:nuist_aio/src/notifications/notification_poster.dart';
import 'package:nuist_aio/src/notifications/notification_settings.dart';
import 'package:nuist_aio/src/services/site_registry.dart';

class FakePoster implements NotificationPoster {
  final posted = <({NotifyKind kind, int id, String title, String body})>[];
  bool granted = true;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<bool> permissionGranted() async => granted;

  @override
  Future<void> show(NotifyKind kind, int id, String title, String body) async {
    posted.add((kind: kind, id: id, title: title, body: body));
  }
}

ChaoxingWorkSnapshot work(
  String key, {
  String title = '第一章作业',
  String course = '高等数学',
  String group = 'todo',
  DateTime? deadline,
}) => ChaoxingWorkSnapshot(
  key: key,
  title: title,
  course: course,
  group: group,
  deadline: deadline,
);

Map<String, dynamic> bulletin(String url, String title) => {
  'url': url,
  'title': title,
  'date': '2026-11-21',
};

Map<String, dynamic> exam(String course, String date) => {
  'KCM': course,
  'KSMC': '期末考试',
  'KSRQ': date,
  'KSSJMS': '09:00~11:00',
  'JASMC': '明德楼N101',
  'ZWH': '12',
};

Map<String, dynamic> grade(String course, String score) => {
  'XNXQDM': '2026-2027-1',
  'KCM': course,
  'KCH': 'MATH101',
  'SJKSRQ': '2026-11-20',
  'XSZCJMC': score,
  'ZCJ': score,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('截止档位', () {
    test('5/3/1 天档位判定', () {
      final now = DateTime(2026, 11, 21, 12);
      int? bucket(double days) =>
          CampusNotificationCenter.activeDeadlineBucket(
            now.add(Duration(milliseconds: (days * 86400000).round())),
            now,
          );
      expect(bucket(6), isNull, reason: '超过 5 天不提醒');
      expect(bucket(5.0), 5);
      expect(bucket(4.5), 5);
      expect(bucket(3.2), 5, reason: '尚未跨过 3 天线，仍处于 5 天档');
      expect(bucket(2.9), 3);
      expect(bucket(2.1), 3);
      expect(bucket(1.2), 3, reason: '尚未跨过 1 天线，仍处于 3 天档');
      expect(bucket(0.9), 1);
      expect(bucket(0.4), 1, reason: '最后数小时仍按 1 天档提醒');
      expect(
        CampusNotificationCenter.activeDeadlineBucket(
          now.subtract(const Duration(days: 1)),
          now,
        ),
        isNull,
        reason: '已截止不提醒',
      );
      expect(
        CampusNotificationCenter.activeDeadlineBucket(null, now),
        isNull,
        reason: '无截止时间不提醒',
      );
    });
  });

  group('学习通作业', () {
    test('首次建档静默，新作业只提醒一次', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.chaoxingWork, true);
      final poster = FakePoster();
      final items = [work('w1'), work('w2')];
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchChaoxingWork: () async => items,
      );
      addTearDown(center.dispose);

      await center.checkAll();
      expect(poster.posted, isEmpty, reason: '首轮为静默基线');

      items.add(work('w3', title: '第二章作业'));
      await center.checkAll();
      expect(poster.posted.single.kind, NotifyKind.chaoxingWork);
      expect(poster.posted.single.body, contains('第二章作业'));

      await center.checkAll();
      expect(poster.posted.length, 1, reason: '同一作业不重复提醒');
    });

    test('截止前 5/3/1 天各提醒一次', () async {
      var now = DateTime(2026, 11, 21, 12);
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.chaoxingWork, true);
      final poster = FakePoster();
      final deadline = now.add(const Duration(days: 4, hours: 6));
      final items = [work('w1', deadline: deadline)];
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        now: () => now,
        fetchChaoxingWork: () async => items,
      );
      addTearDown(center.dispose);

      await center.checkAll();
      expect(poster.posted, isEmpty, reason: '基线阶段不提醒当前档位');

      now = now.add(const Duration(days: 2)); // 剩约 2.3 天 → 3 天档
      await center.checkAll();
      expect(poster.posted.single.body, contains('约剩 3 天'));

      now = now.add(const Duration(days: 2)); // 剩约 0.3 天 → 1 天档
      await center.checkAll();
      expect(poster.posted.last.body, contains('约剩 1 天'));
      expect(poster.posted.length, 2, reason: '同档位不重复提醒');

      now = now.add(const Duration(days: 2)); // 已过期
      await center.checkAll();
      expect(poster.posted.length, 2, reason: '过期后不再提醒');
    });

    test('已完成的作业不参与提醒', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.chaoxingWork, true);
      final poster = FakePoster();
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchChaoxingWork: () async => [work('w1', group: 'done')],
      );
      addTearDown(center.dispose);
      await center.checkAll();
      await center.checkAll();
      expect(poster.posted, isEmpty);
    });
  });

  group('公告 / 考试 / 成绩', () {
    test('新公告合并提醒且不重复', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.bulletins, true);
      final poster = FakePoster();
      final rows = [bulletin('https://b.example/1', '关于调整校车的通知')];
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchBulletins: () async => rows,
      );
      addTearDown(center.dispose);

      await center.checkAll();
      expect(poster.posted, isEmpty);

      rows.add(bulletin('https://b.example/2', '关于放假安排的通知'));
      rows.add(bulletin('https://b.example/3', '关于选课的通知'));
      await center.checkAll();
      expect(poster.posted.single.kind, NotifyKind.bulletins);
      expect(poster.posted.single.body, contains('2 条新公告'));

      await center.checkAll();
      expect(poster.posted.length, 1);
    });

    test('新考试发布提醒', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.exams, true);
      final poster = FakePoster();
      final rows = [exam('高等数学', '2027-01-08')];
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchExams: () async => rows,
      );
      addTearDown(center.dispose);

      await center.checkAll();
      expect(poster.posted, isEmpty);

      rows.add(exam('大学物理', '2027-01-10'));
      await center.checkAll();
      expect(poster.posted.single.title, contains('新考试'));
      expect(poster.posted.single.body, contains('大学物理'));

      // 同字段重复出现（例如座位号变化外的固定信息）不提醒。
      await center.checkAll();
      expect(poster.posted.length, 1);
    });

    test('新成绩发布提醒包含成绩', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.grades, true);
      final poster = FakePoster();
      final rows = <Map<String, dynamic>>[];
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchGrades: () async => rows,
      );
      addTearDown(center.dispose);

      await center.checkAll();
      rows.add(grade('线性代数', '92'));
      await center.checkAll();
      expect(poster.posted.single.body, contains('线性代数'));
      expect(poster.posted.single.body, contains('92'));
    });
  });

  group('电费预警', () {
    test('低于阈值提醒一次，回升后重新警戒', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.electricity, true);
      final poster = FakePoster();
      var value = 20.0;
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchElectricity: () async =>
            ElectricityReading(value: value, unit: '度'),
      );
      addTearDown(center.dispose);

      await center.checkAll();
      expect(poster.posted, isEmpty, reason: '高于阈值不提醒');

      value = 8.0;
      await center.checkAll();
      expect(poster.posted.single.title, '电费预警');
      expect(poster.posted.single.body, contains('8.00 度'));

      await center.checkAll();
      expect(poster.posted.length, 1, reason: '持续低于阈值不重复提醒');

      value = 25.0; // 充电回升，重新警戒
      await center.checkAll();
      value = 5.0;
      await center.checkAll();
      expect(poster.posted.length, 2, reason: '回升后再次低于阈值应重新提醒');
    });

    test('金额型读数不做阈值判断', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.electricity, true);
      final poster = FakePoster();
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchElectricity: () async =>
            const ElectricityReading(value: 2, unit: '元'),
      );
      addTearDown(center.dispose);
      await center.checkAll();
      expect(poster.posted, isEmpty);
    });

    test('自定义阈值生效', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.electricity, true);
      await settings.setElectricityThreshold(20);
      final poster = FakePoster();
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchElectricity: () async =>
            const ElectricityReading(value: 15, unit: '度'),
      );
      addTearDown(center.dispose);
      await center.checkAll();
      expect(poster.posted.single.body, contains('20.0 度'));
    });
  });

  group('登录失效', () {
    test('ready 转 failed 提醒一次，恢复后重置', () async {
      final settings = NotificationSettings();
      await settings.load();
      final poster = FakePoster();
      var phase = SitePhase.ready;
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        identityPhase: () => phase,
      );
      addTearDown(center.dispose);

      await center.checkAll();
      expect(poster.posted, isEmpty, reason: '就绪状态不提醒');

      phase = SitePhase.failed;
      await center.checkAll();
      expect(poster.posted.single.kind, NotifyKind.authFailure);

      await center.checkAll();
      expect(poster.posted.length, 1, reason: '同一失效周期只提醒一次');

      phase = SitePhase.ready;
      await center.checkAll();
      phase = SitePhase.failed;
      await center.checkAll();
      expect(poster.posted.length, 2, reason: '恢复后再次失效应重新提醒');
    });

    test('关闭开关后不提醒', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.authFailure, false);
      final poster = FakePoster();
      var phase = SitePhase.ready;
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        identityPhase: () => phase,
      );
      addTearDown(center.dispose);
      await center.checkAll();
      phase = SitePhase.failed;
      await center.checkAll();
      expect(poster.posted, isEmpty);
    });

    test('启动即为失败（从未就绪）不提醒', () async {
      final settings = NotificationSettings();
      await settings.load();
      final poster = FakePoster();
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        identityPhase: () => SitePhase.failed,
      );
      addTearDown(center.dispose);
      await center.checkAll();
      expect(poster.posted, isEmpty, reason: '避免离线启动误报');
    });
  });

  group('账号与开关变化', () {
    test('账号切换清空去重状态，重新静默建档', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.bulletins, true);
      final poster = FakePoster();
      var generation = 1;
      final rows = [bulletin('https://b.example/1', '通知一')];
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        accountGeneration: () => generation,
        fetchBulletins: () async => rows,
      );
      addTearDown(center.dispose);

      await center.checkAll(); // 基线
      rows.add(bulletin('https://b.example/2', '通知二'));
      await center.checkAll();
      expect(poster.posted.length, 1);

      generation = 2; // 换号
      await center.checkAll();
      expect(poster.posted.length, 1, reason: '换号后重新建档，不补发');
    });

    test('关闭再开启后重新建档', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.bulletins, true);
      final poster = FakePoster();
      final rows = [bulletin('https://b.example/1', '通知一')];
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchBulletins: () async => rows,
      );
      addTearDown(center.dispose);
      center.start();

      await center.checkAll(); // 基线
      rows.add(bulletin('https://b.example/2', '通知二'));
      await center.checkAll();
      expect(poster.posted.length, 1);

      await settings.setEnabled(NotifyKind.bulletins, false);
      await settings.setEnabled(NotifyKind.bulletins, true);
      await center.checkAll();
      expect(poster.posted.length, 1, reason: '重新启用后静默重建基线');
    });
  });

  group('轮询调度', () {
    test('全部轮询项关闭时不启动定时器', () async {
      final settings = NotificationSettings();
      await settings.load();
      final poster = FakePoster();
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchBulletins: () async => [],
      );
      addTearDown(center.dispose);
      center.start();
      expect(center.pollingActive, isFalse);

      await settings.setEnabled(NotifyKind.bulletins, true);
      expect(center.pollingActive, isTrue, reason: '开启轮询项后自动调度');

      await settings.setEnabled(NotifyKind.bulletins, false);
      expect(center.pollingActive, isFalse, reason: '全部关闭后停止调度');
    });

    test('单项查询失败不影响其他项', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.bulletins, true);
      await settings.setEnabled(NotifyKind.grades, true);
      final poster = FakePoster();
      final rows = [bulletin('https://b.example/1', '通知一')];
      final center = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchBulletins: () async => rows,
        fetchGrades: () async => throw Exception('网络异常'),
      );
      addTearDown(center.dispose);

      await center.checkAll(); // 基线 + grades 抛错
      rows.add(bulletin('https://b.example/2', '通知二'));
      await center.checkAll();
      expect(poster.posted.single.kind, NotifyKind.bulletins);
    });
  });

  group('去重状态持久化', () {
    test('重启后恢复已见状态', () async {
      final settings = NotificationSettings();
      await settings.load();
      await settings.setEnabled(NotifyKind.bulletins, true);
      final poster = FakePoster();
      final rows = [bulletin('https://b.example/1', '通知一')];
      final first = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchBulletins: () async => rows,
      );
      await first.checkAll();
      first.dispose();

      final second = CampusNotificationCenter(
        settings: settings,
        poster: poster,
        fetchBulletins: () async => rows,
      );
      addTearDown(second.dispose);
      await second.restoreState();
      await second.checkAll();
      expect(poster.posted, isEmpty, reason: '已见公告不因重启重新提醒');
    });
  });
}
