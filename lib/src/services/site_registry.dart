import 'navigation.dart';

enum SchoolSiteId { identity, portal, teaching, campusCard, library }

enum SiteAuth {
  primaryCas,
  portalSession,
  casCookies,
  casPageToken,
  unverified,
}

enum SitePhase { waiting, connecting, ready, failed, planned }

class SiteFeature {
  const SiteFeature(
    this.id,
    this.label, {
    this.implemented = false,
    this.entry,
    this.readySelector,
  });
  final String id, label;
  final bool implemented;
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
      asset != null && probeTask != null && navigation != null;
  bool isReady(Map<String, dynamic> data) =>
      data['ok'] == true && (readyField == null || data[readyField] == true);
}

class SchoolSites {
  static final all = List<SchoolSite>.unmodifiable([
    SchoolSite(
      id: SchoolSiteId.identity,
      label: '统一身份认证',
      host: 'authserver.nuist.edu.cn',
      entry: Uri.https('authserver.nuist.edu.cn', '/authserver/login'),
      auth: SiteAuth.primaryCas,
      features: const [],
      credentialRule: '学校页面输入密码；CAS Cookie 由原生 Cookie 容器管理，不导出密码，不拼接跨域 Cookie。',
      renewalRule: '学校判定失效或要求验证码时，返回官方认证页面由用户完成。',
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
        SiteFeature('calendar', '校历'),
      ],
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
      renewalRule: '页面丢失、重启或失效时利用主站 CAS 会话重新换取令牌；最多自动重建一次。余额、账单、三套电费共用该会话。',
    ),
    SchoolSite(
      id: SchoolSiteId.library,
      label: '图书馆',
      host: 'lib.nuist.edu.cn',
      entry: Uri.https('lib.nuist.edu.cn', '/'),
      auth: SiteAuth.unverified,
      dependsOn: const [SchoolSiteId.portal],
      features: const [
        SiteFeature('library_search', '馆藏查询'),
        SiteFeature('library_loans', '借阅信息'),
      ],
      credentialRule: '待实测馆藏与借阅对应的业务域、认证入口、令牌位置和最小权限；公开首页不能作为认证成功依据。',
      renewalRule: '待验证；未实现认证适配器与就绪探针前仅列为待接入，不执行登录或抓取。',
    ),
  ]);
  static SchoolSite get(SchoolSiteId id) =>
      all.singleWhere((site) => site.id == id);
  static Iterable<SchoolSite> get automatic =>
      all.where((site) => site.automatic);
}
