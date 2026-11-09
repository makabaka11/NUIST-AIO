import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/session_store.dart';
import 'schedule/schedule.dart';
import 'accounts/accounts.dart';
import 'services/service_sessions.dart';
import 'services/site_registry.dart';
import 'services/initialization_graph.dart';

enum CampusPalette {
  mist('青岚', Color(0xFF476B57)),
  blue('晴空', Color(0xFF42648E)),
  violet('鸢尾', Color(0xFF75558E)),
  orange('杏橙', Color(0xFFA05A31)),
  rose('蔷薇', Color(0xFF9C4F68)),
  slate('岩灰', Color(0xFF5D666F));

  const CampusPalette(this.label, this.seed);
  final String label;
  final Color seed;
}

class AppState extends ChangeNotifier {
  AppState({ServiceSession? cardSession, ServiceSession? teachingSession})
    : serviceSessions = {
        SchoolSiteId.campusCard:
            cardSession ??
            NativeServiceSession(
              site: SchoolSites.get(SchoolSiteId.campusCard),
            ),
        SchoolSiteId.teaching:
            teachingSession ??
            NativeServiceSession(site: SchoolSites.get(SchoolSiteId.teaching)),
      };
  final Map<SchoolSiteId, ServiceSession> serviceSessions;
  ServiceSession get cardSession => serviceSessions[SchoolSiteId.campusCard]!;
  ServiceSession get teachingSession => serviceSessions[SchoolSiteId.teaching]!;
  bool connectingServices = false;
  int _serviceSyncId = 0;
  bool _disposed = false;
  bool _repairingScheduleCache = false;
  String? servicesNotice;
  final Map<SchoolSiteId, SitePhase> sitePhases = {};
  final Map<SchoolSiteId, String> siteMessages = {};
  SitePhase sitePhase(SchoolSite site) =>
      sitePhases[site.id] ??
      (site.auth == SiteAuth.unverified
          ? SitePhase.planned
          : ((site.id == SchoolSiteId.identity ||
                        site.id == SchoolSiteId.portal) &&
                    connectedAt != null
                ? SitePhase.ready
                : SitePhase.waiting));

  void _setSite(SchoolSiteId id, SitePhase phase, String message) {
    if (_disposed) return;
    sitePhases[id] = phase;
    siteMessages[id] = message;
    notifyListeners();
  }

  Future<void> connectCampusServices({bool synchronizeData = true}) async {
    if (connectingServices) return;
    if (connectedAt == null) {
      servicesNotice = '请先连接校园账号，再初始化校园服务。';
      notifyListeners();
      return;
    }
    final generation = sessionGeneration;
    final syncId = ++_serviceSyncId;
    connectingServices = true;
    servicesNotice = '正在初始化校园服务…';
    for (final site in SchoolSites.automatic) {
      sitePhases[site.id] = SitePhase.waiting;
      siteMessages.remove(site.id);
    }
    notifyListeners();
    final failures = <String>[];
    Future<void> connectTeaching() async {
      _setSite(SchoolSiteId.teaching, SitePhase.connecting, '正在获取教务会话…');
      try {
        final terms = await teachingSession.query('semesters', {});
        if (generation != sessionGeneration) return;
        _setSite(SchoolSiteId.teaching, SitePhase.ready, '教务会话已验证');
        if (synchronizeData && schedule == null) {
          final current = terms['current'];
          final list = (terms['terms'] as List? ?? []);
          final matches = list
              .map((t) => Semester.fromJson(Map<String, dynamic>.from(t)))
              .where((t) => t.code == current)
              .toList();
          if (matches.isEmpty) throw const FormatException('未能识别当前学期。');
          if (matches.isNotEmpty) {
            final result = await teachingSession.query('schedule', {
              'term': current,
              'termName': matches.first.name,
            });
            await saveSchedule(
              ScheduleParser.parse(Map<String, dynamic>.from(result['data'])),
              generation: generation,
            );
          }
        }
      } catch (_) {
        if (generation == sessionGeneration) {
          _setSite(SchoolSiteId.teaching, SitePhase.failed, '需要重试或在教务页面完成额外验证');
        }
        failures.add('教务自动连接未完成，可在“学习”中重试');
      }
    }

    Future<void> connectCard() async {
      if (generation != sessionGeneration) return;
      _setSite(SchoolSiteId.campusCard, SitePhase.connecting, '正在获取并验证一卡通令牌…');
      try {
        final data = await cardSession.query(
          synchronizeData ? 'sync' : 'probe',
          accountArguments(),
        );
        if (generation != sessionGeneration) return;
        if (!synchronizeData) {
          if (!SchoolSites.get(SchoolSiteId.campusCard).isReady(data)) {
            throw const FormatException('令牌尚未就绪。');
          }
          _setSite(SchoolSiteId.campusCard, SitePhase.ready, '一卡通令牌已验证');
          return;
        }
        if (generation != sessionGeneration) return;
        if (!['wallet', 'bills', 'electricity'].any(data.containsKey)) {
          throw const FormatException('未返回账户数据。');
        }
        await saveAccounts(data, generation: generation);
        if (generation != sessionGeneration) return;
        _setSite(
          SchoolSiteId.campusCard,
          SitePhase.ready,
          '一卡通令牌已验证，余额、账单和电费共用会话',
        );
        if ((data['errors'] as List? ?? []).isNotEmpty) {
          failures.add('部分校园账户未更新，可在账户页重试');
        }
      } catch (_) {
        if (generation == sessionGeneration) {
          _setSite(
            SchoolSiteId.campusCard,
            SitePhase.failed,
            '需要重试或在一卡通页面完成额外验证',
          );
        }
        failures.add('一卡通自动连接未完成，可在“校园账户”中重试');
      }
    }

    try {
      await initializeSiteGraph(
        sites: SchoolSites.automatic,
        ready: (id) =>
            generation == sessionGeneration &&
            sitePhase(SchoolSites.get(id)) == SitePhase.ready,
        blocked: (site) {
          if (generation == sessionGeneration) {
            _setSite(site.id, SitePhase.failed, '依赖站点尚未就绪，请先连接主账号或重试');
            failures.add('${site.label}的依赖站点未就绪');
          }
        },
        initialize: (site) => switch (site.id) {
          SchoolSiteId.teaching => connectTeaching(),
          SchoolSiteId.campusCard => connectCard(),
          _ => Future<void>.error(
            StateError('Missing initialization adapter: ${site.id.name}'),
          ),
        },
      );
      if (generation == sessionGeneration) {
        servicesNotice = failures.isEmpty
            ? (synchronizeData ? '教务和一卡通已自动连接，数据已同步。' : '校园服务初始化完成。')
            : failures.join('；');
      }
    } finally {
      if (syncId == _serviceSyncId && !_disposed) {
        connectingServices = false;
        notifyListeners();
      }
    }
  }

  Map<String, dynamic> accountArguments({String? month, int page = 1}) => {
    'month': month ?? currentMonth(),
    'page': page,
    'dorm': dorm?.toJson(),
  };

  Future<void> resetServiceSessions() async {
    _serviceSyncId++;
    connectingServices = false;
    await Future.wait(serviceSessions.values.map((session) => session.close()));
    servicesNotice = null;
    sitePhases.clear();
    siteMessages.clear();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final SessionStore sessions = SessionStore();
  ThemeMode themeMode = ThemeMode.system;
  CampusPalette palette = CampusPalette.mist;
  bool dynamicColor = true;
  bool liquidGlassNav = true;
  bool registered = false;
  bool onboarded = false;
  DateTime? connectedAt;
  String? displayName;
  String? startupNotice;
  Schedule? schedule;
  DormSelection? dorm;
  AccountCache accounts = const AccountCache();

  Future<void> saveAccounts(
    Map<String, dynamic> result, {
    required int generation,
  }) async {
    final operation = _cacheQueue.catchError((Object _) {}).then((_) async {
      if (generation != sessionGeneration) return;
      final data = Map<String, dynamic>.from(result);
      if (data['electricity'] != null &&
          data['electricity']['dormKey'] != dorm?.key) {
        data.remove('electricity');
      }
      final next = accounts.merge(data);
      await sessions.saveAccounts(next);
      if (generation == sessionGeneration) {
        accounts = next;
        notifyListeners();
      }
    });
    _cacheQueue = operation;
    await operation;
  }

  Future<void> setDorm(DormSelection? selected) async {
    final generation = sessionGeneration;
    if (selected != null && !(await DormCatalog.load()).contains(selected)) {
      throw const FormatException('请选择目录中的完整宿舍。');
    }
    final operation = _cacheQueue.catchError((Object _) {}).then((_) async {
      if (generation != sessionGeneration) {
        throw const FormatException('账号状态已变化，请重新选择。');
      }
      final next = accounts.withoutElectricity();
      await sessions.saveDorm(selected);
      await sessions.saveAccounts(next);
      dorm = selected;
      accounts = next;
      notifyListeners();
    });
    _cacheQueue = operation;
    await operation;
  }

  Future<void> clearPrivateData() async {
    await clearSchedule();
    final operation = _cacheQueue.catchError((Object _) {}).then((_) async {
      await sessions.clearAccounts();
      await sessions.saveDorm(null);
      accounts = const AccountCache();
      dorm = null;
      notifyListeners();
    });
    _cacheQueue = operation;
    await operation;
  }

  int sessionGeneration = 0;
  Future<void> _cacheQueue = Future.value();

  Future<void> saveSchedule(Schedule value, {required int generation}) async {
    if (generation != sessionGeneration) {
      return;
    }
    final operation = _cacheQueue.catchError((Object _) {}).then((_) async {
      if (generation != sessionGeneration) {
        return;
      }
      await sessions.saveSchedule(value);
      if (generation == sessionGeneration) {
        schedule = value;
        if (_repairingScheduleCache) {
          startupNotice = null;
          _repairingScheduleCache = false;
        }
        notifyListeners();
      }
    });
    _cacheQueue = operation;
    await operation;
  }

  Future<void> clearSchedule() async {
    sessionGeneration++;
    schedule = null;
    notifyListeners();
    final operation = _cacheQueue
        .catchError((Object _) {})
        .then((_) => sessions.clearSchedule());
    _cacheQueue = operation;
    await operation;
  }

  Future<void> load() async {
    try {
      onboarded = await _prefs.getBool('onboarded') ?? false;
      registered = await _prefs.getBool('registered') ?? false;
      dynamicColor = await _prefs.getBool('dynamicColor') ?? true;
      liquidGlassNav = await _prefs.getBool('liquidGlassNav') ?? true;
      final mode = await _prefs.getString('themeMode');
      final color = await _prefs.getString('palette');
      themeMode = ThemeMode.values.firstWhere(
        (v) => v.name == mode,
        orElse: () => ThemeMode.system,
      );
      palette = CampusPalette.values.firstWhere(
        (v) => v.name == color,
        orElse: () => CampusPalette.mist,
      );
      connectedAt = await sessions.connectionTime();
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.macOS &&
          connectedAt != null) {
        await sessions.restorePortalSession();
      }
      displayName = await sessions.displayName();
      schedule = await sessions.readSchedule();
      if (schedule != null &&
          !schedule!.localEdits &&
          schedule!.courses.isEmpty &&
          schedule!.warnings.any((w) => w.contains('条排课记录'))) {
        schedule = null;
        _repairingScheduleCache = true;
        startupNotice = '旧版课表未完整解析，请重新获取课表或导入已有 JSON。';
      }
      accounts = await sessions.readAccounts();
      dorm = await sessions.readDorm();
    } catch (_) {
      startupNotice = '部分本地设置未能读取，可以继续使用并重新连接账号。';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    sessionGeneration++;
    for (final session in serviceSessions.values) {
      session.close();
    }
    super.dispose();
  }

  Future<void> setMode(ThemeMode value) async {
    await _prefs.setString('themeMode', value.name);
    themeMode = value;
    notifyListeners();
  }

  Future<void> setPalette(CampusPalette value) async {
    await _prefs.setString('palette', value.name);
    await _prefs.setBool('dynamicColor', false);
    palette = value;
    dynamicColor = false;
    notifyListeners();
  }

  Future<void> setDynamic(bool value) async {
    await _prefs.setBool('dynamicColor', value);
    dynamicColor = value;
    notifyListeners();
  }

  Future<void> setLiquidGlassNav(bool value) async {
    await _prefs.setBool('liquidGlassNav', value);
    liquidGlassNav = value;
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    await _prefs.setBool('onboarded', true);
    onboarded = true;
    notifyListeners();
  }

  Future<void> setRegistered() async {
    await _prefs.setBool('registered', true);
    registered = true;
    notifyListeners();
  }

  Future<void> sessionChanged() async {
    sessions.invalidatePortalRead();
    connectedAt = await sessions.connectionTime();
    displayName = await sessions.displayName();
    notifyListeners();
  }

  Future<void> disconnect() async {
    await clearPrivateData();
    await resetServiceSessions();
    await sessions.clear();
    connectedAt = null;
    displayName = null;
    notifyListeners();
  }
}
