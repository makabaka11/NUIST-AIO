import 'navigation.dart';

enum SchoolSiteId {
  identity,
  portal,
  teaching,
  campusCard,
  library,
  vpn,
  bulletin,
  enrollment,
  studentAffairs,
  repair,
  innovation,
  campusBus,
  chaoxing,
}

enum SiteAuth {
  primaryCas,
  portalSession,
  casCookies,
  nativeCookies,
  casPageToken,
  unverified,
  webVpnCas,
  campusNetwork,
}

enum SitePhase { waiting, connecting, ready, failed, planned }

class SiteFeature {
  const SiteFeature(
    this.id,
    this.label, {
    this.implemented = false,
    this.browserOnly = false,
    this.entry,
    this.readySelector,
  });
  final String id, label;
  final bool implemented, browserOnly;
  final String? entry;
  final String? readySelector;
}

/// Source of truth for every campus integration. Unverified entries must never
/// run automatically or pretend that a public page establishes authentication.
class SchoolSite {
  const SchoolSite({
    required this.id,
    required this.label,
    required this.auth,
    required this.host,
    required this.entry,
    required this.features,
    required this.credentialRule,
    required this.renewalRule,
    this.dependsOn = const [],
    this.asset,
    this.probeTask,
    this.navigation,
    this.readyField,
    this.browserOnly = false,
    this.onDemand = false,
    this.networkRouting = false,
    this.authEntry,
    this.sessionEntry,
    this.officialWebsite,
    this.probePrefixes = const [],
  });
  final SchoolSiteId id;
  final String label, host;
  final Uri? entry;
  final SiteAuth auth;
  final List<SchoolSiteId> dependsOn;
  final List<SiteFeature> features;
  final String credentialRule, renewalRule;
  final String? asset, probeTask, readyField;
  final bool onDemand, networkRouting, browserOnly;
  final Uri? authEntry, sessionEntry, officialWebsite;
  final List<String> probePrefixes;
  bool acceptsProbeLocation(Uri? uri) =>
      uri != null &&
      uri.scheme == 'https' &&
      uri.host == host &&
      probePrefixes.any(
        (path) =>
            uri.path.startsWith(path) ||
            (path.endsWith('/') &&
                uri.path == path.substring(0, path.length - 1)),
      );
  final bool Function(Uri?)? navigation;
  bool get automatic =>
      !onDemand && asset != null && probeTask != null && navigation != null;
  bool isReady(Map<String, dynamic> data) =>
      data['ok'] == true && (readyField == null || data[readyField] == true);
}

class SchoolSites {
  // Chapter overview discovered in the official course UI protocol; data is
  // accepted only when its explicit completed/total task summary validates.
  static final chaoxingProgressEntry = Uri.https(
    'mooc2-ans.chaoxing.com',
    '/mooc2-ans/mycourse/studentcourse',
  );
  static final all = List<SchoolSite>.unmodifiable([
    SchoolSite(
      id: SchoolSiteId.chaoxing,
      label: '学习通',
      // Authentication is independent; current-term data sync waits for teaching.
      dependsOn: const [],
      host: 'mooc1-api.chaoxing.com',
      entry: Uri.parse(
        'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1',
      ),
      authEntry: Uri.parse('https://passport2.chaoxing.com/login?fid=&refer='),
      auth: SiteAuth.nativeCookies,
      asset: 'assets/js/nuist_chaoxing.js',
      probeTask: 'courses',
      navigation: SchoolNavigation.chaoxing,
      probePrefixes: const ['/mycourse/backclazzdata'],
      features: const [
        SiteFeature('chaoxingCourses', '本学期学习通课程', implemented: true),
        SiteFeature(
          'chaoxingCourseSelection',
          '课程匹配确认与手动选择',
          implemented: true,
        ),
        SiteFeature('chaoxingProgress', '课程任务点进度', implemented: true),
        SiteFeature('chaoxingWork', '学习通作业', implemented: true),
        SiteFeature('chaoxingExam', '学习通考试', implemented: true),
      ],
      credentialRule: '仅在超星官方页登录；Cookie 保留原生作用域，Android 验证后落盘，不导出、不保存密码。仅持久化连接意愿；课程只读接口验证通过后才能同步。',
      renewalRule: '启动及初始化时，仅对保存过连接意愿或旧安装原生会话的账号进行一次有界只读验证，与校园服务并行且不依赖门户。未连接则不请求；失效提示官方登录。教务就绪后再独立同步本学期数据，不等待人工确认来结束初始化；首次或名单变化需用户确认扫描课程；选择按校园账号与学期存于系统安全存储。换号清除连接意愿、Cookie、选择及缓存。',
    ),
    SchoolSite(
      id: SchoolSiteId.identity,
      label: '统一身份认证',
      host: 'authserver.nuist.edu.cn',
      entry: Uri.https('authserver.nuist.edu.cn', '/authserver/login'),
      auth: SiteAuth.primaryCas,
      features: const [
        SiteFeature('passkeyAutoLogin', '通行密钥自动登录', implemented: true),
      ],
      credentialRule: '通行密钥私钥按主账号摘要绑定，仅存系统安全存储；关闭、换号或移除会话即删除。本机软件凭据不要求生物识别，学校端吊销后需重新创建。学校页面输入密码；CAS Cookie 由原生 Cookie 容器管理，不导出密码，不拼接跨域 Cookie。',
      renewalRule: '启动先以门户 /getLoginUser 只读探针验证主账号；失效且启用通行密钥时在 HTTPS 精确认证源尝试一次 WebAuthn 登录，再验证相同账号。失败停止子站初始化，提示官方页面重新认证。VPN 复用 CAS 并独立验证授权目录。',
    ),
    SchoolSite(
      id: SchoolSiteId.portal,
      label: '融合门户',
      host: 'i.nuist.edu.cn',
      entry: Uri.https('i.nuist.edu.cn', '/login'),
      auth: SiteAuth.portalSession,
      dependsOn: const [SchoolSiteId.identity],
      features: const [
        SiteFeature('profile', '姓名', implemented: true),
        SiteFeature(
          'calendar',
          '校历',
          implemented: true,
          readySelector: '#schoolYearCalendar',
          entry: 'https://i.nuist.edu.cn/qljfwapp/sys/lwSchoolCalendar/schoolYearCalendar.do',
        ),
        SiteFeature('eHomeGuide', '信大 E 家 · 企业微信指引', implemented: true),
      ],
      authEntry: SchoolNavigation.portalCasEntry,
      asset: 'assets/js/nuist_calendar.js',
      probeTask: 'calendar',
      onDemand: true,
      probePrefixes: const ['/'],
      navigation: SchoolNavigation.portalCalendar,
      credentialRule:
          'CAS service 使用学校门户回调；/getLoginUser 返回有效账号后保存加密会话快照和显示姓名。',
      renewalRule: '重新走门户 CAS 回调；禁止持久保存或复用一次性 ticket。',
    ),
    SchoolSite(
      id: SchoolSiteId.teaching,
      label: '本科教务',
      host: 'jwxt.nuist.edu.cn',
      entry: SchoolNavigation.scheduleEntry,
      auth: SiteAuth.casCookies,
      dependsOn: const [SchoolSiteId.portal],
      features: const [
        SiteFeature('schedule', '课表', implemented: true),
        SiteFeature(
          'certificatePrint',
          '证明打印 · 系统浏览器',
          implemented: true,
          browserOnly: true,
          entry: 'https://jwxt.nuist.edu.cn/jwapp/sys/zmdynxd/*default/index.do?EMAP_LANG=zh#/zmdy',
        ),
        SiteFeature(
          'studentProfile',
          '学生基本资料',
          implemented: true,
          entry: 'https://jwxt.nuist.edu.cn/jwapp/sys/xyjctjapp/*default/index.do?EMAP_LANG=zh#/grxyjcbg',
          readySelector: '#grxyjcbg-root-div, .jqx-progressbar',
        ),
        SiteFeature('schedule_import_json', '本机课表 JSON 导入', implemented: true),
        SiteFeature('schedule_local_edit', '本机课程编辑与删除', implemented: true),
        SiteFeature(
          'rooms',
          '空闲教室',
          implemented: true,
          entry: 'https://jwxt.nuist.edu.cn/jwapp/sys/kxjas/*default/index.do?EMAP_LANG=zh#/kxjas',
          readySelector: '#kxjas-index-search',
        ),
        SiteFeature(
          'grades',
          '成绩查询',
          implemented: true,
          entry: 'https://jwxt.nuist.edu.cn/jwapp/sys/cjcx/*default/index.do?EMAP_LANG=zh#/cjcx',
          readySelector: '#dqxq-index-table',
        ),
        SiteFeature(
          'gradeAnalysis',
          '成绩分析 GPA',
          implemented: true,
          readySelector: '#cjfx-div',
          entry: 'https://jwxt.nuist.edu.cn/jwapp/sys/cjcx/*default/index.do?EMAP_LANG=zh#/cjfx',
        ),
        SiteFeature(
          'credits',
          '学业监测',
          implemented: true,
          entry: 'https://jwxt.nuist.edu.cn/jwapp/sys/xyjctjapp/*default/index.do?EMAP_LANG=zh#/grxyjcbg',
          readySelector: '#grxyjcbg-root-div, .jqx-progressbar',
        ),
        SiteFeature(
          'exams',
          '考试安排',
          implemented: true,
          entry: 'https://jwxt.nuist.edu.cn/jwapp/sys/studentWdksapApp/*default/index.do?EMAP_LANG=zh#/wdksap',
          readySelector: '#wdksapinfoRight',
        ),
      ],
      probePrefixes: const [
        '/jwapp/sys/wdkb/',
        '/jwapp/sys/kxjas/',
        '/jwapp/sys/cjcx/',
        '/jwapp/sys/studentWdksapApp/',
        '/jwapp/sys/xyjctjapp/',
      ],
      asset: 'assets/js/nuist_schedule.js',
      probeTask: 'semesters',
      navigation: SchoolNavigation.schedule,
      credentialRule:
          '使用同一原生 CAS Cookie 容器进入教务官方入口，教务 Cookie 保留原域及路径；只读学期接口通过后才标记就绪。',
      renewalRule: '只读查询失败时经官方入口重建一次；需要选择角色或额外验证时显示官方页面。',
    ),
    SchoolSite(
      id: SchoolSiteId.campusCard,
      label: '校园一卡通',
      host: 'icard.nuist.edu.cn',
      entry: SchoolNavigation.cardEntry,
      auth: SiteAuth.casPageToken,
      dependsOn: const [SchoolSiteId.portal],
      features: const [
        SiteFeature('wallet', '校园卡余额', implemented: true),
        SiteFeature('bills', '账单', implemented: true),
        SiteFeature('power_main', '本部电费', implemented: true),
        SiteFeature('power_qin', '沁园 42/43 电费', implemented: true),
        SiteFeature('power_jnh', '金牛湖电费', implemented: true),
      ],
      probePrefixes: const ['/plat-pc/', '/campus-card-pc/'],
      asset: 'assets/js/nuist_accounts.js',
      probeTask: 'probe',
      readyField: 'ready',
      navigation: SchoolNavigation.card,
      credentialRule: '官方 CAS 桥接后由学校页面初始化 sessionStorage.access_token；/berserker-base/user 校验成功才就绪。JWT 仅留在驻留页面，同源请求使用 synjones-auth，不传回 Dart。',
      renewalRule: '页面丢失、重启或失效时利用主站 CAS 会话重新换取令牌；落到 CAS 登录表单时，启用通行密钥则至多恢复一次主站认证，再重走一卡通官方入口。CAS 拒绝应用登记时立即独立失败并提示学校入口不可用，不要求反复登录；仍需业务只读探针通过。余额、账单、三套电费共用该会话。',
    ),
    SchoolSite(
      id: SchoolSiteId.vpn,
      label: '学校 WebVPN',
      host: 'client.vpn.nuist.edu.cn',
      entry: SchoolNavigation.vpnEntry,
      authEntry: SchoolNavigation.vpnCasEntry,
      auth: SiteAuth.webVpnCas,
      dependsOn: const [SchoolSiteId.portal],
      onDemand: true,
      features: const [SiteFeature('webvpn', '校外资源访问', implemented: true)],
      asset: 'assets/js/nuist_vpn.js',
      probeTask: 'probe',
      readyField: 'ready',
      probePrefixes: const ['/enlink/'],
      navigation: SchoolNavigation.vpn,
      credentialRule: '经学校已验证 CAS 回调建立网关会话。clientInfo 仅在网关同源内解析，用 userId 查询官方授权资源目录；不导出登录键、sid、身份或 Cookie，只返回已登记站点的路由。',
      renewalRule: '按需连接；资源目录服务端验证失败时最多重建一次。仍需认证时交由用户在学校页面完成；不自动创建通行密钥。',
    ),
    SchoolSite(
      id: SchoolSiteId.bulletin,
      label: '学校公告板',
      host: 'bulletin.nuist.edu.cn',
      entry: Uri.https('bulletin.nuist.edu.cn', '/index.htm'),
      auth: SiteAuth.campusNetwork,
      onDemand: true,
      networkRouting: true,
      features: const [
        SiteFeature('bulletin_list', '公告列表与日期分类', implemented: true),
        SiteFeature('bulletin_detail', '公告正文与附件入口', implemented: true),
      ],
      asset: 'assets/js/nuist_bulletin.js',
      probeTask: 'list',
      probePrefixes: const ['/'],
      navigation: SchoolNavigation.bulletin,
      credentialRule: '直连依赖当前网络可达性，列表和正文结构验证通过才视为可用；校外按官方资源目录返回的 VPN 映射读取，凭据只在原生网关 Cookie 容器。',
      renewalRule:
          '自动模式优先直连，失败后尝试一次 WebVPN 路径；固定模式不偷偷切换。正文/附件保留同一路由，失效时显示官方连接入口。',
    ),
    SchoolSite(
      id: SchoolSiteId.library,
      label: '图书馆',
      officialWebsite: Uri.https('lib.nuist.edu.cn', '/'),
      host: 'elib.nuist.edu.cn',
      entry: Uri.https('elib.nuist.edu.cn', '/space/reader/lendList'),
      authEntry: SchoolNavigation.libraryCasEntry,
      sessionEntry: Uri.https('elib.nuist.edu.cn', '/space/casBoard'),
      auth: SiteAuth.casCookies,
      dependsOn: const [SchoolSiteId.portal],
      asset: 'assets/js/nuist_library.js',
      probeTask: 'probe',
      readyField: 'ready',
      probePrefixes: const ['/space/', '/mspace/'],
      navigation: SchoolNavigation.library,
      features: const [
        SiteFeature(
          'library_search',
          '馆藏查询',
          implemented: true,
          browserOnly: true,
          entry: 'https://elib.nuist.edu.cn/space/index',
        ),
        SiteFeature('library_loans', '借阅信息', implemented: true),
      ],
      credentialRule: '已在 macOS 原生验证 CAS、借阅接口与同域 Cookie。X-CSRF-TOKEN 仅在 elib 源内读取使用；固定只读探针通过才就绪。借阅缓存按主账号绑定到系统安全存储。',
      renewalRule: '从图书馆 rosetta 入口发起 CAS，禁止跳过业务入口直拼 CAS service；有限续接一次，验证码交给官方页面。换号关闭视图并清理 elib Cookie、加密借阅缓存，拒绝旧响应。',
    ),
    for (final link in SchoolBrowserLinks.all.where((e) => e.standalone))
      SchoolSite(
        id: link.site,
        label: link.name,
        host: link.entry!.host,
        entry: link.entry,
        auth: SiteAuth.unverified,
        browserOnly: true,
        onDemand: true,
        features: [
          SiteFeature(
            link.id,
            link.name,
            implemented: true,
            browserOnly: true,
            entry: link.entry.toString(),
          ),
        ],
        credentialRule: '仅跳转系统浏览器，不在 App 获取或保存该站点凭据。',
        renewalRule: '由系统浏览器及学校官方页面处理登录；内网资源可选择官方 VPN 授权目录入口。',
      ),
  ]);
  static SchoolSite get(SchoolSiteId id) =>
      all.singleWhere((site) => site.id == id);
  static Iterable<SchoolSite> get automatic =>
      all.where((site) => site.automatic);
}

/// Browser-only entries: URLs are user-supplied official entries, not API adapters.
class SchoolBrowserLink {
  SchoolBrowserLink(
    this.id,
    this.name,
    this.group,
    this.detail, {
    required this.site,
    String? url,
    this.vpn = false,
    this.studentNumber = false,
    this.standalone = false,
    this.instructions,
    this.directProbeMarkers = const [],
  }) : entry = url == null ? null : Uri.parse(url);
  final String id, name, group, detail;
  final SchoolSiteId site;
  final Uri? entry;
  final bool vpn, studentNumber, standalone;
  final String? instructions;

  /// Anonymous HTML signatures for route reachability, never an auth probe.
  final List<String> directProbeMarkers;
  Uri resolve({String? number}) {
    final uri = entry;
    if (uri == null) throw const FormatException('此功能请在企业微信工作台打开。');
    if (!studentNumber) return uri;
    if (number == null ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(number.trim())) {
      throw const FormatException('请先在“我的”中连接账号并更新学生资料，再打开信大 E 修。');
    }
    final fragment = Uri(
      path: '/index',
      queryParameters: {'WxId': number.trim()},
    );
    return uri.replace(fragment: fragment.toString());
  }
}

class SchoolBrowserLinks {
  static final all = List<SchoolBrowserLink>.unmodifiable([
    SchoolBrowserLink(
      'enrollment',
      '选课系统',
      '学习',
      '在系统浏览器中选课',
      site: SchoolSiteId.enrollment,
      url: 'https://xsxk.nuist.edu.cn/xsxk/profile/index.html',
      standalone: true,
    ),
    SchoolBrowserLink(
      'studentAffairs',
      '奥兰系统',
      '生活',
      '需校园网 · 支持 WebVPN 入口',
      site: SchoolSiteId.studentAffairs,
      url: 'http://stu.nuist.edu.cn/login.aspx',
      directProbeMarkers: const ['奥蓝学生管理信息系统'],
      vpn: true,
      standalone: true,
    ),
    SchoolBrowserLink(
      'certificatePrint',
      '证明打印',
      '学习',
      '在系统浏览器中打开教务证明打印',
      site: SchoolSiteId.teaching,
      url: 'https://jwxt.nuist.edu.cn/jwapp/sys/zmdynxd/*default/index.do?EMAP_LANG=zh#/zmdy',
    ),
    SchoolBrowserLink(
      'repair',
      '信大 E 修',
      '生活',
      '报修 · 需校园网',
      site: SchoolSiteId.repair,
      url: 'http://xdex.nuist.edu.cn:18080/NUIST-WEB/',
      directProbeMarkers: const [
        '南京信息工程大学',
        './static/config.js',
        './static/js/app.',
      ],
      vpn: true,
      studentNumber: true,
      standalone: true,
    ),
    SchoolBrowserLink(
      'eHomeGuide',
      '信大 E 家',
      '生活',
      '请在企业微信工作台中打开',
      site: SchoolSiteId.portal,
      instructions: '请打开企业微信 → 工作台 → 信大 E 家。该服务与微信绑定，本应用不接入其账号认证。',
    ),
    SchoolBrowserLink(
      'campusBus',
      '信大 E 行',
      '生活',
      '校园公交查询',
      site: SchoolSiteId.campusBus,
      url: 'http://www.ns-res.cn/hydxflat/indexelct.html',
      standalone: true,
    ),
    SchoolBrowserLink(
      'innovation',
      '创新创业系统',
      '学习',
      '需校园网 · 支持 WebVPN 入口',
      site: SchoolSiteId.innovation,
      url: 'https://cxcyjy.nuist.edu.cn/pt/System/Home/Index',
      vpn: true,
      standalone: true,
    ),
  ]);
}

/// Public supplemental data, outside campus authentication/initialization.
class PublicHolidaySource {
  static const id = 'apisbo_holidays';
  static const documentation = 'https://apisbo.com/docs/holidays/year/';
  static Uri year(int year) =>
      Uri.https('api.apisbo.com', '/holidays/year/$year');
}

/// Application-owned public update sources. Never use a school session here.
class AppReleaseSources {
  static final github = Uri.parse('https://github.com/makabaka11/NUIST-AIO');
  static final gitee = Uri.parse('https://gitee.com/ded_retr0/NUIST-AIO');
  static Uri get githubReleases => Uri.https(
    'api.github.com',
    '/repos${github.path}/releases',
    {'per_page': '100'},
  );
  static Uri get giteeReleases => Uri.https(
    'gitee.com',
    '/api/v5/repos${gitee.path}/releases',
    {'page': '1', 'per_page': '100'},
  );
}

/// Public community references only; no school authentication or probes.
class WikiCommunitySources {
  static final tieba = Uri.parse(
    'https://tieba.baidu.com/f?kw=%E5%8D%97%E4%BA%AC%E4%BF%A1%E6%81%AF%E5%B7%A5%E7%A8%8B%E5%A4%A7%E5%AD%A6#/',
  );
  static const campusMarket = '#小程序://校园集市/CQeun6LnMHEyMQe';
}
