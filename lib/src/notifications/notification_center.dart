import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/site_registry.dart';
import '../academic/academic.dart';
import 'notification_poster.dart';
import 'notification_settings.dart';

/// 学习通作业快照。轮询层把 [ChaoxingItem] 归一化后交给通知中心，
/// 测试可注入构造，避免依赖 WebView 仓库。
class ChaoxingWorkSnapshot {
  const ChaoxingWorkSnapshot({
    required this.key,
    required this.title,
    required this.course,
    required this.group,
    this.deadline,
  });
  final String key, title, course, group;
  final DateTime? deadline;

  /// `group == 'todo'` 才视为未完成。
  bool get pending => group == 'todo';
}

/// 电量读数（来自一卡通电费接口）。
class ElectricityReading {
  const ElectricityReading({required this.value, required this.unit});
  final double value;

  /// '度' / '元' / ''，与 [Electricity.unit] 一致。
  final String unit;
}

/// 通知中心：
/// - 轮询类（作业 / 公告 / 电费 / 考试 / 成绩）在应用进程存活期间每约 1 小时
///   检查一次启用项；应用被系统回收后检查自然暂停，回到前台时择机补查。
/// - 登录失效为事件驱动：监听统一认证站点阶段，从就绪转为失败时提醒一次。
/// - 所有检查均为只读查询，复用已注册站点会话，不新增任何认证流程。
/// - 去重状态按账号隔离：账号变化（sessionGeneration 变化）即全部重置。
class CampusNotificationCenter with WidgetsBindingObserver {
  CampusNotificationCenter({
    required this.settings,
    NotificationPoster? poster,
    SharedPreferencesAsync? preferences,
    DateTime Function()? now,
    this.interval = const Duration(hours: 1),
    this.accountWatch,
    this.accountGeneration,
    this.identityPhase,
    this.fetchChaoxingWork,
    this.fetchBulletins,
    this.fetchExams,
    this.fetchGrades,
    this.fetchElectricity,
  }) : poster = poster ?? settings.poster,
       _prefs = preferences ?? SharedPreferencesAsync(),
       _now = now ?? DateTime.now;

  final NotificationSettings settings;
  final NotificationPoster poster;
  final SharedPreferencesAsync _prefs;
  final DateTime Function() _now;

  /// 轮询间隔。生产环境为 1 小时；测试可缩短。
  final Duration interval;

  /// 账号/状态监听（生产环境为 [AppState]）。
  final Listenable? accountWatch;
  final int Function()? accountGeneration;

  /// 统一认证站点阶段读取（生产环境读取 AppState.sitePhases）。
  final SitePhase Function()? identityPhase;

  // ---- 数据源注入（生产环境为各站点只读查询；null 表示该项不可用）----
  final Future<List<ChaoxingWorkSnapshot>?> Function()? fetchChaoxingWork;
  final Future<List<Map<String, dynamic>>?> Function()? fetchBulletins;
  final Future<List<Map<String, dynamic>>?> Function()? fetchExams;
  final Future<List<Map<String, dynamic>>?> Function()? fetchGrades;
  final Future<ElectricityReading?> Function()? fetchElectricity;

  static const _stateKey = 'notify.state.v1';

  /// 作业截止提醒的剩余天数档位。
  static const List<int> deadlineBuckets = [5, 3, 1];

  Timer? _timer;
  bool _started = false, _checking = false, _disposed = false;
  DateTime? _lastCheck;
  int? _lastGeneration;
  SitePhase? _lastIdentityPhase;
  bool _authNotified = false;
  final Map<NotifyKind, bool> _lastEnabled = {};
  Future<void> _restore = Future<void>.value();

  // ---- 去重状态（持久化，账号变化时重置）----
  final Set<NotifyKind> _baselined = {};
  final Set<String> _seenWork = {};
  final Map<String, Set<int>> _workBuckets = {};
  final Set<String> _seenBulletins = {};
  final Set<String> _seenExams = {};
  final Set<String> _seenGrades = {};
  bool _electricityArmed = true;
  Future<void> _stateWrite = Future<void>.value();

  bool get pollingActive => _timer != null;
  DateTime? get lastCheck => _lastCheck;

  /// 启动通知中心。重复调用安全；全部轮询项关闭时只保留事件监听。
  void start() {
    if (_disposed) return;
    if (!_started) {
      _started = true;
      accountWatch?.addListener(_accountNotified);
      settings.addListener(_settingsChanged);
      WidgetsBinding.instance.addObserver(this);
      for (final kind in NotifyKind.values) {
        _lastEnabled[kind] = settings.isEnabled(kind);
      }
      _accountNotified();
      // 恢复上次运行的去重状态；checkAll 会等待其完成。
      _restore = restoreState();
    }
    _applySchedule();
  }

  /// 停止轮询并移除监听（测试与释放时使用）。
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_started) {
      accountWatch?.removeListener(_accountNotified);
      settings.removeListener(_settingsChanged);
      WidgetsBinding.instance.removeObserver(this);
      _started = false;
    }
  }

  void _applySchedule() {
    final needTimer = settings.anyPollingEnabled;
    if (needTimer && _timer == null) {
      // 启动后的首次检查稍作延迟，避开校园服务初始化的高峰期。
      _timer = Timer(const Duration(seconds: 20), _timerTick);
    } else if (!needTimer && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  void _timerTick() {
    if (_disposed) return;
    unawaited(checkAll());
    // Timer.periodic 在进程存活期间（含后台）持续触发；被系统挂起或回收即停止。
    _timer = Timer(interval, _timerTick);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!settings.anyPollingEnabled) return;
    final last = _lastCheck;
    if (last == null || _now().difference(last) >= const Duration(minutes: 30)) {
      unawaited(checkAll());
    }
  }

  void _settingsChanged() {
    if (_disposed) return;
    for (final kind in NotifyKind.values) {
      final value = settings.isEnabled(kind);
      final was = _lastEnabled[kind] ?? value;
      _lastEnabled[kind] = value;
      if (kind.polling && !was && value) {
        // 重新启用：当前数据先静默建档，避免一次性补发历史变更。
        _resetCategory(kind);
      }
    }
    _persistState();
    _applySchedule();
  }

  void _accountNotified() {
    if (_disposed) return;
    final generation = accountGeneration?.call();
    if (generation != null && generation != _lastGeneration) {
      _lastGeneration = generation;
      _resetAllState();
    }
    final phase = identityPhase?.call();
    if (phase != null && phase != _lastIdentityPhase) {
      final previous = _lastIdentityPhase;
      _lastIdentityPhase = phase;
      if (phase == SitePhase.failed && previous == SitePhase.ready) {
        _notifyAuthFailure();
      } else if (phase == SitePhase.ready || phase == SitePhase.connecting) {
        _authNotified = false;
      }
    }
  }

  Future<void> _notifyAuthFailure() async {
    if (_authNotified || !settings.isEnabled(NotifyKind.authFailure)) return;
    _authNotified = true;
    await _post(
      NotifyKind.authFailure,
      '登录已失效',
      '统一认证已失效或暂时无法验证，请打开信大AIO重新登录或使用通行密钥自动登录。',
    );
  }

  /// 立即执行一轮检查。并发调用只保留一次；逐项静默失败。
  Future<void> checkAll() async {
    if (_checking || _disposed) return;
    _checking = true;
    try {
      await _restore;
      _accountNotified();
      if (settings.isEnabled(NotifyKind.bulletins)) {
        await _guard(_checkBulletins);
      }
      if (settings.isEnabled(NotifyKind.electricity)) {
        await _guard(_checkElectricity);
      }
      if (settings.isEnabled(NotifyKind.exams)) {
        await _guard(_checkExams);
      }
      if (settings.isEnabled(NotifyKind.grades)) {
        await _guard(_checkGrades);
      }
      if (settings.isEnabled(NotifyKind.chaoxingWork)) {
        await _guard(_checkChaoxingWork);
      }
    } finally {
      _lastCheck = _now();
      _checking = false;
      _persistState();
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // 轮询失败不影响其他项，也不向用户报错；下一周期重试。
    }
  }

  // ---------------- 学习通作业 ----------------

  Future<void> _checkChaoxingWork() async {
    final fetch = fetchChaoxingWork;
    if (fetch == null) return;
    final items = await fetch();
    if (items == null) return;
    final now = _now();

    if (!_baselined.contains(NotifyKind.chaoxingWork)) {
      // 首次启用：当前未完成作业全部静默建档，之后只对新增/档位变化提醒。
      for (final item in items) {
        if (!item.pending) continue;
        _seenWork.add(item.key);
        final bucket = _activeBucket(item.deadline, now);
        if (bucket != null) (_workBuckets[item.key] ??= {}).add(bucket);
      }
      _baselined.add(NotifyKind.chaoxingWork);
      return;
    }

    final fresh = <ChaoxingWorkSnapshot>[];
    for (final item in items) {
      if (!item.pending) continue;
      if (_seenWork.add(item.key)) fresh.add(item);
    }
    if (fresh.isNotEmpty) {
      await _postList(
        NotifyKind.chaoxingWork,
        fresh.map((item) => '《${item.course}》${item.title}').toList(),
        '份新作业',
      );
      for (final item in fresh) {
        final bucket = _activeBucket(item.deadline, now);
        if (bucket != null) (_workBuckets[item.key] ??= {}).add(bucket);
      }
    }

    // 截止提醒：进入 5 / 3 / 1 天档位时各提醒一次。
    for (final item in items) {
      if (!item.pending) continue;
      final bucket = _activeBucket(item.deadline, now);
      if (bucket == null) continue;
      final notified = _workBuckets[item.key] ??= {};
      if (notified.add(bucket)) {
        await _post(
          NotifyKind.chaoxingWork,
          '作业即将截止',
          '《${item.course}》${item.title} 距截止约剩 $bucket 天。',
        );
      }
    }
    _boundWorkState();
  }

  /// 距截止 [deadline] 剩余时间所处的提醒档位；已过期或超过 5 天返回 null。
  @visibleForTesting
  static int? activeDeadlineBucket(DateTime? deadline, DateTime now) =>
      _activeBucket(deadline, now);

  static int? _activeBucket(DateTime? deadline, DateTime now) {
    if (deadline == null) return null;
    final remaining = deadline.difference(now);
    if (remaining.isNegative || remaining == Duration.zero) return null;
    final days = remaining.inMinutes / 1440;
    if (days > deadlineBuckets.first) return null;
    // 取满足 剩余天数 ≤ 档位 的最小档位：剩余 2.25 天处于 3 天档，
    // 直到跨过 1 天线才进入 1 天档。
    for (final bucket in deadlineBuckets.reversed) {
      if (days <= bucket) return bucket;
    }
    return null;
  }

  void _boundWorkState() {
    _boundSet(_seenWork, 500);
    _workBuckets.removeWhere((key, _) => !_seenWork.contains(key));
  }

  // ---------------- 学校公告 ----------------

  Future<void> _checkBulletins() async {
    final fetch = fetchBulletins;
    if (fetch == null) return;
    final rows = await fetch();
    if (rows == null) return;

    if (!_baselined.contains(NotifyKind.bulletins)) {
      _seenBulletins.addAll(rows.map(_bulletinKey));
      _boundSet(_seenBulletins, 300);
      _baselined.add(NotifyKind.bulletins);
      return;
    }
    final fresh = rows.where((row) => _seenBulletins.add(_bulletinKey(row))).toList();
    if (fresh.isEmpty) return;
    await _postList(
      NotifyKind.bulletins,
      fresh.map((row) => '${row['title'] ?? '新公告'}').toList(),
      '条新公告',
    );
    _boundSet(_seenBulletins, 300);
  }

  String _bulletinKey(Map<String, dynamic> row) =>
      '${row['url'] ?? ''}|${row['title'] ?? ''}';

  // ---------------- 考试 / 成绩 ----------------

  Future<void> _checkExams() async {
    final fetch = fetchExams;
    if (fetch == null) return;
    final rows = await fetch();
    if (rows == null) return;

    if (!_baselined.contains(NotifyKind.exams)) {
      _seenExams.addAll(rows.map(_examSignature));
      _boundSet(_seenExams, 300);
      _baselined.add(NotifyKind.exams);
      return;
    }
    final fresh = rows.where((row) => _seenExams.add(_examSignature(row))).toList();
    if (fresh.isEmpty) return;
    await _postList(
      NotifyKind.exams,
      fresh.map(_examTitle).toList(),
      '场新考试',
    );
    _boundSet(_seenExams, 300);
  }

  String _examSignature(Map<String, dynamic> row) => [
    for (final field in ['KCM', 'KSMC', 'KSRQ', 'KSSJMS', 'JASMC', 'ZWH'])
      academicText(row, field),
  ].join('|');

  String _examTitle(Map<String, dynamic> row) =>
      '${academicText(row, 'KCM')} · ${academicText(row, 'KSRQ')} ${academicText(row, 'KSSJMS')}';

  Future<void> _checkGrades() async {
    final fetch = fetchGrades;
    if (fetch == null) return;
    final rows = await fetch();
    if (rows == null) return;

    if (!_baselined.contains(NotifyKind.grades)) {
      _seenGrades.addAll(rows.map(_gradeSignature));
      _boundSet(_seenGrades, 500);
      _baselined.add(NotifyKind.grades);
      return;
    }
    final fresh = rows.where((row) => _seenGrades.add(_gradeSignature(row))).toList();
    if (fresh.isEmpty) return;
    await _postList(
      NotifyKind.grades,
      fresh.map(_gradeTitle).toList(),
      '门新成绩',
    );
    _boundSet(_seenGrades, 500);
  }

  String _gradeSignature(Map<String, dynamic> row) => [
    for (final field in [
      'XNXQDM',
      'KCM',
      'KCH',
      'SJKSRQ',
      'XSZCJMC',
      'ZCJ',
    ])
      academicText(row, field),
  ].join('|');

  String _gradeTitle(Map<String, dynamic> row) {
    final score = academicText(row, 'XSZCJMC');
    final title = academicText(row, 'KCM');
    return score.isEmpty ? title : '$title · $score';
  }

  // ---------------- 电费预警 ----------------

  Future<void> _checkElectricity() async {
    final fetch = fetchElectricity;
    if (fetch == null) return;
    final reading = await fetch();
    if (reading == null) return;
    // 阈值以“度”为单位；只对电量型读数预警，金额型宿舍不猜测换算。
    if (reading.unit != '度') return;
    final threshold = settings.electricityThreshold;
    if (reading.value > threshold) {
      if (!_electricityArmed) {
        _electricityArmed = true;
        _persistState();
      }
      return;
    }
    if (!_electricityArmed) return;
    _electricityArmed = false;
    await _post(
      NotifyKind.electricity,
      '电费预警',
      '宿舍剩余电量 ${reading.value.toStringAsFixed(2)} 度，已低于预警阈值 $threshold 度，请及时充电。',
    );
  }

  // ---------------- 状态重置与持久化 ----------------

  void _resetCategory(NotifyKind kind) {
    switch (kind) {
      case NotifyKind.chaoxingWork:
        _seenWork.clear();
        _workBuckets.clear();
      case NotifyKind.bulletins:
        _seenBulletins.clear();
      case NotifyKind.exams:
        _seenExams.clear();
      case NotifyKind.grades:
        _seenGrades.clear();
      case NotifyKind.electricity:
        _electricityArmed = true;
      case NotifyKind.authFailure:
        _authNotified = false;
    }
    _baselined.remove(kind);
  }

  /// 账号变化：全部去重状态与基线清空，避免跨账号串扰或补发。
  void _resetAllState() {
    for (final kind in NotifyKind.values) {
      _resetCategory(kind);
    }
    _authNotified = false;
    _persistState();
  }

  void _boundSet(Set<String> values, int limit) {
    if (values.length > limit) {
      values.removeAll(values.take(values.length - limit));
    }
  }

  void _persistState() {
    final snapshot = jsonEncode({
      'baselined': [for (final kind in _baselined) kind.name],
      'seenWork': _seenWork.toList(),
      'workBuckets': {
        for (final entry in _workBuckets.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value.toList(),
      },
      'seenBulletins': _seenBulletins.toList(),
      'seenExams': _seenExams.toList(),
      'seenGrades': _seenGrades.toList(),
      'electricityArmed': _electricityArmed,
    });
    _stateWrite = _stateWrite
        .catchError((Object _) {})
        .then((_) => _prefs.setString(_stateKey, snapshot));
  }

  /// 恢复持久化的去重状态。start() 会自动调用一次；测试可显式调用。
  Future<void> restoreState() async {
    try {
      final raw = await _prefs.getString(_stateKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _resetAllMemory();
      for (final name in decoded['baselined'] as List? ?? []) {
        for (final kind in NotifyKind.values) {
          if (kind.name == name) _baselined.add(kind);
        }
      }
      void strings(String field, Set<String> target) {
        for (final value in decoded[field] as List? ?? []) {
          if (value is String) target.add(value);
        }
      }

      strings('seenWork', _seenWork);
      strings('seenBulletins', _seenBulletins);
      strings('seenExams', _seenExams);
      strings('seenGrades', _seenGrades);
      final buckets = decoded['workBuckets'];
      if (buckets is Map) {
        for (final entry in buckets.entries) {
          if (entry.key is String && entry.value is List) {
            final set = {
              for (final bucket in entry.value as List)
                if (bucket is int) bucket,
            };
            if (set.isNotEmpty) _workBuckets[entry.key as String] = set;
          }
        }
      }
      final armed = decoded['electricityArmed'];
      if (armed is bool) _electricityArmed = armed;
    } catch (_) {
      // 损坏状态按全新处理。
    }
  }

  void _resetAllMemory() {
    _baselined.clear();
    _seenWork.clear();
    _workBuckets.clear();
    _seenBulletins.clear();
    _seenExams.clear();
    _seenGrades.clear();
    _electricityArmed = true;
  }

  // ---------------- 投递 ----------------

  Future<void> _post(NotifyKind kind, String title, String body) =>
      poster.show(kind, _id(kind, '$title|$body'), title, body);

  /// 多条聚合：单条逐条投递，多条合并为一条汇总，避免瞬时刷屏。
  Future<void> _postList(NotifyKind kind, List<String> titles, String suffix) {
    if (titles.isEmpty) return Future.value();
    if (titles.length == 1) {
      return _post(kind, _summaryTitle(kind), titles.single);
    }
    final preview = titles.take(3).join('；');
    final body = titles.length > 3
        ? '$preview 等'
        : preview;
    return _post(
      kind,
      _summaryTitle(kind),
      '新增 ${titles.length} $suffix：$body',
    );
  }

  String _summaryTitle(NotifyKind kind) => switch (kind) {
    NotifyKind.chaoxingWork => '学习通有新作业',
    NotifyKind.bulletins => '学校有新公告',
    NotifyKind.exams => '教务发布新考试',
    NotifyKind.grades => '教务发布新成绩',
    _ => kind.label,
  };

  int _id(NotifyKind kind, String key) =>
      kind.index * 0x100000 + (key.hashCode & 0xFFFFF);
}
