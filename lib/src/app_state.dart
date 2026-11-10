import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'library/library.dart';
import 'dashboard/dashboard_config.dart';
import 'dashboard/holiday_source.dart';

import 'chaoxing/chaoxing.dart';
import 'chaoxing/current_term.dart';

import 'package:image_picker/image_picker.dart';

import 'profile/student_profile.dart';
import 'profile/avatar_store.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/session_store.dart';
import 'network/campus_network.dart';
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

/// 界面组件库风格。Material 3 为默认；MIUIX 为 HyperOS 风格组件库。
enum UiStyle {
  material3('Material 3'),
  miuix('MIUIX');

  const UiStyle(this.label);
  final String label;
}

class AppState extends ChangeNotifier {
  AppState({
    ServiceSession? cardSession,
    ServiceSession? teachingSession,
    ServiceSession? portalSession,
    ServiceSession? librarySession,
    PublicHolidayRepository? holidayRepository,
    BulletinRepository? bulletinRepository,
    AvatarStore? avatarStore,
    ChaoxingRepository? chaoxingRepository,
  }) : holidayRepository = holidayRepository ?? PublicHolidayRepository(),
       chaoxing = chaoxingRepository ?? ChaoxingRepository(),
       avatars = avatarStore ?? AvatarStore(),
       bulletins = bulletinRepository ?? BulletinRepository(),
       serviceSessions = {
         SchoolSiteId.library: librarySession ?? NativeLibrarySession(),
         SchoolSiteId.portal:
             portalSession ??
             NativeServiceSession(site: SchoolSites.get(SchoolSiteId.portal)),
         SchoolSiteId.campusCard:
             cardSession ??
             NativeServiceSession(
               site: SchoolSites.get(SchoolSiteId.campusCard),
             ),
         SchoolSiteId.teaching:
             teachingSession ??
             NativeServiceSession(site: SchoolSites.get(SchoolSiteId.teaching)),
       };
  final ChaoxingRepository chaoxing;
  Future<bool> connectChaoxing() async {
    if (chaoxing.busy) return false;
    final generation = sessionGeneration;
    await chaoxing.verify();
    if (_disposed || generation != sessionGeneration || !chaoxing.verified) {
      return false;
    }
    // Authentication ends here; start data synchronization as a distinct phase.
    unawaited(refreshChaoxing());
    return true;
  }

  Future<void> refreshChaoxing() async {
    chaoxing.currentTerm = _currentChaoxingTerm;
    await chaoxing.refresh();
  }

  Future<ChaoxingTermScope> _currentChaoxingTerm() async {
    final generation = sessionGeneration;
    if (connectedAt == null) throw const FormatException('请先连接校园账号，以确认本学期课程。');
    final terms = await teachingSession.query('semesters', {});
    if (generation != sessionGeneration) {
      throw const FormatException('校园账号已变化，请重试。');
    }
    final current = terms['current'];
    final list = (terms['terms'] as List? ?? [])
        .map((t) => Semester.fromJson(Map<String, dynamic>.from(t as Map)))
        .where((t) => t.code == current)
        .toList();
    if (terms['ok'] != true ||
        current is! String ||
        !RegExp(r'^\d{4}-\d{4}-[123]$').hasMatch(current) ||
        list.length != 1) {
      throw const FormatException('教务未返回明确的当前学期，请重新连接教务后再试。');
    }
    // Read the official current timetable separately; never replace the user's
    // selected historical timetable or include locally edited/imported rows.
    final result = await teachingSession.query('schedule', {
      'term': current,
      'termName': list.single.name,
    });
    if (generation != sessionGeneration) {
      throw const FormatException('校园账号已变化，请重试。');
    }
    if (result['ok'] != true || result['data'] is! Map) {
      throw const FormatException('本学期课程名单未读取成功，未开始扫描学习通课程。');
    }
    final scope = ChaoxingTermScope.fromData(
      Map<String, dynamic>.from(result['data'] as Map),
    );
    if (scope.term != current) throw const FormatException('教务返回的课程名单不属于当前学期。');
    return scope;
  }

  DashboardLayout dashboardLayout = const DashboardLayout();
  Future<void> _dashboardWrites = Future.value();
  Future<void> updateDashboard(DashboardLayout value) {
    dashboardLayout = value;
    notifyListeners();
    final operation = _dashboardWrites
        .catchError((Object _) {})
        .then((_) => _prefs.setString('dashboardLayout.v1', value.encode()));
    _dashboardWrites = operation;
    if (value.enabled.contains(DashboardWidgetId.holiday) &&
        connectedAt != null &&
        schoolCalendar == null) {
      unawaited(syncCalendar());
    }
    return operation;
  }

  final PublicHolidayRepository holidayRepository;
  List<PublicHolidayDay> publicHolidays = const [];
  LibraryLoans? libraryLoans;
  bool libraryVerified = false, syncingLibrary = false, syncingCalendar = false;
  String? libraryNotice, calendarNotice;
  Map<String, dynamic>? schoolCalendar;
  int _libraryRequest = 0, _calendarRequest = 0;
  ServiceSession get librarySession => serviceSessions[SchoolSiteId.library]!;
  Future<void> connectLibrary({bool synchronizeData = true}) async {
    if (syncingLibrary || connectedAt == null) return;
    final generation = sessionGeneration;
    syncingLibrary = true;
    libraryNotice = null;
    _setSite(SchoolSiteId.library, SitePhase.connecting, '正在验证图书馆会话…');
    try {
      final result = await librarySession.query('probe', {});
      if (generation != sessionGeneration || _disposed) return;
      if (!SchoolSites.get(SchoolSiteId.library).isReady(result)) {
        throw const FormatException('图书馆会话尚未验证。');
      }
      libraryVerified = true;
      _setSite(SchoolSiteId.library, SitePhase.ready, '图书馆借阅接口已验证');
    } catch (_) {
      if (generation == sessionGeneration && !_disposed) {
        libraryVerified = false;
        libraryNotice = '图书馆尚未连接，请在官方页面完成登录后重试。';
        _setSite(SchoolSiteId.library, SitePhase.failed, libraryNotice!);
      }
    } finally {
      if (generation == sessionGeneration && !_disposed) {
        syncingLibrary = false;
        notifyListeners();
      }
    }
    if (generation == sessionGeneration && libraryVerified && synchronizeData) {
      await syncLibrary();
    }
  }

  Future<void> syncLibrary() async {
    if (syncingLibrary || !libraryVerified || connectedAt == null) return;
    final generation = sessionGeneration, request = ++_libraryRequest;
    syncingLibrary = true;
    libraryNotice = null;
    notifyListeners();
    try {
      final result = await librarySession.query('loans', {});
      if (generation != sessionGeneration ||
          request != _libraryRequest ||
          _disposed) {
        return;
      }
      if (result['ok'] != true ||
          result['books'] is! List ||
          result['total'] != (result['books'] as List).length) {
        throw const FormatException('借阅未完整读取。');
      }
      final value = LibraryLoans(
        (result['books'] as List)
            .map(
              (e) => LibraryBook.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(),
        DateTime.now(),
      );
      final operation = _cacheQueue.catchError((Object _) {}).then((_) async {
        if (generation != sessionGeneration ||
            request != _libraryRequest ||
            _disposed) {
          return;
        }
        await sessions.saveLibrary(value);
        if (generation == sessionGeneration &&
            request == _libraryRequest &&
            !_disposed) {
          libraryLoans = value;
          notifyListeners();
        }
      });
      _cacheQueue = operation;
      await operation;
    } catch (_) {
      if (generation == sessionGeneration && !_disposed) {
        libraryVerified = false;
        libraryNotice = '借阅信息未更新，保留上次缓存。可打开官方页面核对。';
        _setSite(SchoolSiteId.library, SitePhase.failed, '借阅接口需要重新验证，现有数据仅为缓存');
      }
    } finally {
      if (generation == sessionGeneration &&
          request == _libraryRequest &&
          !_disposed) {
        syncingLibrary = false;
        notifyListeners();
      }
    }
  }

  Future<void> syncCalendar() async {
    if (syncingCalendar || connectedAt == null) return;
    final generation = sessionGeneration, request = ++_calendarRequest;
    syncingCalendar = true;
    calendarNotice = null;
    notifyListeners();
    try {
      final result = await portalSession.query('calendar', {});
      if (generation != sessionGeneration ||
          request != _calendarRequest ||
          _disposed) {
        return;
      }
      if (result['ok'] != true ||
          result['year'] is! int ||
          result['terms'] is! List ||
          (result['terms'] as List).length != 2) {
        throw const FormatException('校历不完整。');
      }
      schoolCalendar = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(result)) as Map,
      );
    } catch (_) {
      if (generation == sessionGeneration && !_disposed) {
        calendarNotice = '校历未更新，补充安排以学校通知为准。';
      }
    } finally {
      if (generation == sessionGeneration &&
          request == _calendarRequest &&
          !_disposed) {
        final year = DateTime.now().toUtc().add(const Duration(hours: 8)).year;
        final years = await Future.wait([
          holidayRepository.load(year),
          holidayRepository.load(year + 1),
        ]);
        if (generation == sessionGeneration &&
            request == _calendarRequest &&
            !_disposed) {
          publicHolidays = years.expand((days) => days).toList();
          syncingCalendar = false;
          notifyListeners();
        }
      }
    }
  }

  final Map<SchoolSiteId, ServiceSession> serviceSessions;
  final AvatarStore avatars;
  StudentProfile? studentProfile;
  Uint8List? avatarBytes;
  int avatarColor = Random.secure().nextInt(10);
  bool syncingProfile = false;
  String? profileNotice;
  int _profileRequest = 0;
  Future<void> syncStudentProfile() async {
    if (connectedAt == null || syncingProfile) return;
    final generation = sessionGeneration, request = ++_profileRequest;
    syncingProfile = true;
    profileNotice = null;
    notifyListeners();
    try {
      final result = await teachingSession.query('studentProfile', {});
      if (generation != sessionGeneration ||
          request != _profileRequest ||
          _disposed) {
        return;
      }
      if (result['ok'] != true || result['profile'] is! Map) {
        throw const FormatException('资料未返回。');
      }
      final value = StudentProfile.fromJson(
        Map<String, dynamic>.from(result['profile']),
      );
      final operation = _cacheQueue.catchError((Object _) {}).then((_) async {
        if (generation != sessionGeneration ||
            request != _profileRequest ||
            _disposed) {
          return;
        }
        await sessions.saveProfile(value);
        await sessions.saveAvatarColor(avatarColor);
        if (generation == sessionGeneration &&
            request == _profileRequest &&
            !_disposed) {
          studentProfile = value;
          notifyListeners();
        }
      });
      _cacheQueue = operation;
      await operation;
    } catch (_) {
      if (generation == sessionGeneration &&
          request == _profileRequest &&
          !_disposed) {
        profileNotice = '学生资料未更新，可稍后重试。';
      }
    } finally {
      if (request == _profileRequest && !_disposed) {
        syncingProfile = false;
        notifyListeners();
      }
    }
  }

  Future<void> saveAvatar(XFile file, {required int generation}) async {
    final owner = await sessions.accountKey();
    if (owner == null) return;
    final bytes = await AvatarStore.normalize(file);
    if (generation != sessionGeneration || _disposed) return;
    final operation = _cacheQueue.catchError((Object _) {}).then((_) async {
      if (generation != sessionGeneration || _disposed) return;
      await avatars.save(bytes);
      await sessions.saveAvatarOwner(owner);
      if (generation == sessionGeneration && !_disposed) {
        avatarBytes = bytes;
        notifyListeners();
      }
    });
    _cacheQueue = operation;
    await operation;
  }

  Future<void> chooseAvatar() async {
    final generation = sessionGeneration, owner = await sessions.accountKey();
    if (owner == null || connectedAt == null) {
      throw const FormatException('请先连接校园账号，再设置头像。');
    }
    await sessions.markPendingAvatar(owner);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (file != null && generation == sessionGeneration) {
        await saveAvatar(file, generation: generation);
      }
    } finally {
      if (generation == sessionGeneration) {
        await sessions.markPendingAvatar(null);
      }
    }
  }

  final BulletinRepository bulletins;
  CampusNetworkMode networkMode = CampusNetworkMode.automatic;
  Future<void> setNetworkMode(CampusNetworkMode value) async {
    await _prefs.setString('networkMode', value.name);
    networkMode = value;
    await bulletins.close();
    notifyListeners();
  }

  ServiceSession get portalSession => serviceSessions[SchoolSiteId.portal]!;
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
          SchoolSiteId.library => () async {
            await connectLibrary(synchronizeData: false);
            if (generation == sessionGeneration && !libraryVerified) {
              failures.add('图书馆未连接，可在官方页面完成认证后重试');
            }
          }(),
          _ => Future<void>.error(
            StateError('Missing initialization adapter: ${site.id.name}'),
          ),
        },
      );
      if (generation == sessionGeneration &&
          sitePhase(SchoolSites.get(SchoolSiteId.teaching)) ==
              SitePhase.ready) {
        servicesNotice = '正在同步学生资料…';
        await syncStudentProfile();
        if (profileNotice != null) failures.add('学生资料未更新，可在“我的”中重试');
      }
      if (generation == sessionGeneration &&
          synchronizeData &&
          libraryVerified) {
        await syncLibrary();
        if (libraryNotice != null) failures.add('图书借阅未更新，可在图书馆页面重试');
      }
      if (generation == sessionGeneration &&
          synchronizeData &&
          dashboardLayout.enabled.contains(DashboardWidgetId.holiday)) {
        await syncCalendar();
        if (calendarNotice != null) failures.add('校历未更新，可稍后重试');
      }
      if (generation == sessionGeneration) {
        servicesNotice = failures.isEmpty
            ? (synchronizeData ? '教务、一卡通和图书馆已自动连接，数据已同步。' : '校园服务初始化完成。')
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
    await bulletins.close();
    await chaoxing.close(clearCookies: true);
    connectingServices = false;
    await Future.wait(serviceSessions.values.map((session) => session.close()));
    servicesNotice = null;
    sitePhases.clear();
    siteMessages.clear();
  }

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  final SessionStore sessions = SessionStore();
  ThemeMode themeMode = ThemeMode.system;
  double fontScale = 1.0;
  static const minFontScale = .75;
  static const maxFontScale = 1.5;
  CampusPalette palette = CampusPalette.mist;
  bool dynamicColor = true;
  bool liquidGlassNav = true;
  UiStyle uiStyle = UiStyle.material3;
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
    _libraryRequest++;
    _calendarRequest++;
    libraryVerified = false;
    syncingLibrary = false;
    syncingCalendar = false;
    libraryLoans = null;
    schoolCalendar = null;
    publicHolidays = const [];
    libraryNotice = null;
    calendarNotice = null;
    await chaoxing.close(clearCookies: true);
    _profileRequest++;
    syncingProfile = false;
    studentProfile = null;
    avatarBytes = null;
    profileNotice = null;
    avatarColor = Random.secure().nextInt(10);
    await clearSchedule();
    final operation = _cacheQueue.catchError((Object _) {}).then((_) async {
      await sessions.clearAccounts();
      await sessions.clearLibrary();
      await sessions.clearProfile();
      try {
        await avatars.clear();
      } catch (_) {}
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
      dashboardLayout = DashboardLayout.decode(
        await _prefs.getString('dashboardLayout.v1'),
      );
      final networkName = await _prefs.getString('networkMode');
      networkMode = CampusNetworkMode.values.firstWhere(
        (v) => v.name == networkName,
        orElse: () => CampusNetworkMode.automatic,
      );
      dynamicColor = await _prefs.getBool('dynamicColor') ?? true;
      liquidGlassNav = await _prefs.getBool('liquidGlassNav') ?? true;
      final styleName = await _prefs.getString('uiStyle');
      uiStyle = UiStyle.values.firstWhere(
        (v) => v.name == styleName,
        orElse: () => UiStyle.material3,
      );
      final storedFontScale = await _prefs.getDouble('fontScale') ?? 1.0;
      fontScale = storedFontScale.isFinite
          ? storedFontScale.clamp(minFontScale, maxFontScale)
          : 1.0;
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
      try {
        studentProfile = await sessions.readProfile();
        avatarColor = await sessions.avatarColor() ?? avatarColor;
        await sessions.saveAvatarColor(avatarColor);
      } catch (_) {
        studentProfile = null;
        profileNotice = '本地学生资料未能读取，可更新资料重试。';
      }
      try {
        final owner = await sessions.avatarOwner();
        if (owner != null && owner == await sessions.accountKey()) {
          avatarBytes = await avatars.read();
        }
      } catch (_) {}
      try {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          final pending = await sessions.pendingAvatar();
          if (pending != null) {
            final lost = await ImagePicker().retrieveLostData();
            if (pending == await sessions.accountKey() &&
                connectedAt != null &&
                lost.files?.isNotEmpty == true) {
              await saveAvatar(
                lost.files!.first,
                generation: sessionGeneration,
              );
            }
            await sessions.markPendingAvatar(null);
          }
        }
      } catch (_) {
        await sessions.markPendingAvatar(null);
      }
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
      libraryLoans = await sessions.readLibrary();
      dorm = await sessions.readDorm();
    } catch (_) {
      startupNotice = '部分本地设置未能读取，可以继续使用并重新连接账号。';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    chaoxing.dispose();
    bulletins.close();
    sessionGeneration++;
    for (final session in serviceSessions.values) {
      session.close();
    }
    super.dispose();
  }

  /// 拖动时只预览，松手时持久化，避免连续写入偏好设置。
  Future<void> setFontScale(double value, {bool persist = true}) async {
    final next = value.isFinite ? value.clamp(minFontScale, maxFontScale) : 1.0;
    if (persist) await _prefs.setDouble('fontScale', next);
    fontScale = next;
    notifyListeners();
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

  Future<void> setUiStyle(UiStyle value) async {
    await _prefs.setString('uiStyle', value.name);
    uiStyle = value;
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    await _prefs.setBool('onboarded', true);
    onboarded = true;
    notifyListeners();
  }

  Future<void> sessionChanged() async {
    sessions.invalidatePortalRead();
    connectedAt = await sessions.connectionTime();
    displayName = await sessions.displayName();
    if (connectedAt == null) {
      studentProfile = null;
      avatarBytes = null;
    }
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
