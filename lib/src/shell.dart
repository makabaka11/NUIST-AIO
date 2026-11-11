import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'campus_ui.dart';

import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_liquid_glass_nav_bar/flutter_liquid_glass_nav_bar.dart';

import 'app_state.dart';
import 'about/about_page.dart';
import 'updates/update_ui.dart';
import 'library/library_page.dart';
import 'chaoxing/chaoxing_page.dart';
import 'calendar/calendar_page.dart';
import 'services/browser_links.dart';
import 'services/site_registry.dart';
import 'profile/profile_header.dart';
import 'bulletin/bulletin_page.dart';
import 'network/network_settings.dart';
import 'academic/academic.dart';
import 'academic/academic_page.dart';
import 'accounts/accounts_page.dart';
import 'accounts/dorm_picker.dart';
import 'home_page.dart';
import 'schedule/learning_page.dart';
import 'schedule/schedule_widgets.dart';
import 'auth/login_page.dart';
import 'onboarding.dart';
import 'theme_settings.dart';
import 'widgets.dart';
import 'wiki/wiki_page.dart';

final _features = <({String name, String group, String detail, IconData icon})>[
  (
    name: '我的课表',
    group: '学习',
    detail: '查看课程与上课安排',
    icon: Icons.calendar_month_outlined,
  ),
  (
    name: '空闲教室',
    group: '学习',
    detail: '寻找适合自习的教室',
    icon: Icons.meeting_room_outlined,
  ),
  (
    name: '成绩查询',
    group: '学习',
    detail: '查看学期成绩',
    icon: Icons.assessment_outlined,
  ),
  (
    name: '考试安排',
    group: '学习',
    detail: '掌握考试时间与地点',
    icon: Icons.edit_calendar_outlined,
  ),
  (
    name: '学业监测',
    group: '学习',
    detail: '学分完成情况与学期 GPA',
    icon: Icons.school_outlined,
  ),
  (
    name: '校园卡',
    group: '生活',
    detail: '余额与校园卡服务',
    icon: Icons.credit_card_outlined,
  ),
  (name: '宿舍电费', group: '生活', detail: '查看宿舍用电余额', icon: Icons.bolt_outlined),
  (
    name: '学校公告',
    group: '资源',
    detail: '今日通知、分类公告与正文',
    icon: Icons.campaign_outlined,
  ),
  (
    name: '图书馆',
    group: '资源',
    detail: '馆藏检索与借阅信息',
    icon: Icons.local_library_outlined,
  ),
  (
    name: '校历',
    group: '资源',
    detail: '学期安排与重要日期',
    icon: Icons.date_range_outlined,
  ),
  ...SchoolBrowserLinks.all.map(
    (l) => (
      name: l.name,
      group: l.group,
      detail: l.detail,
      icon: l.instructions == null
          ? Icons.open_in_new
          : Icons.chat_bubble_outline,
    ),
  ),
];

class CampusShell extends StatefulWidget {
  const CampusShell({super.key, required this.state});
  final AppState state;
  @override
  State<CampusShell> createState() => _CampusShellState();
}

/// 带淡入动画的 IndexedStack。切换标签时新页面从 opacity 0→1 淡入，
/// 保留所有子页面的 State（IndexedStack 始终挂载全部子节点），
/// 避免硬切闪现。
class _TabFadeStack extends StatefulWidget {
  const _TabFadeStack({required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<_TabFadeStack> createState() => _TabFadeStackState();
}

class _TabFadeStackState extends State<_TabFadeStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  late int _shown = widget.index;

  @override
  void didUpdateWidget(covariant _TabFadeStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _shown = widget.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    child: IndexedStack(index: _shown, children: widget.children),
  );
}

class _CampusShellState extends State<CampusShell> {
  int selected = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.state.connectedAt != null &&
          widget.state.cardSession.available &&
          widget.state.servicesNotice == null) {
        widget.state.connectCampusServices();
      }
    });
  }

  void login() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => LoginPage(state: widget.state)),
  );

  Widget _buildAppBarTitle(int selected, ColorScheme colors) {
    if (selected != 0) {
      return Text(['首页', '学习', '功能', '我的'][selected]);
    }
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(15),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/branding/app_icon.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '信大AIO',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'NUIST · 校园助手',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// MIUIX 风格顶栏：squircle 容器、毛玻璃可选、MiuixText 标题。
  /// 作为 PreferredSizeWidget 注入 Scaffold.appBar。
  PreferredSizeWidget _buildMiuixAppBar(int selected, MiuixColors colors) {
    final theme = MiuixTheme.of(context);
    final isHome = selected == 0;
    final titleText = ['首页', '学习', '功能', '我的'][selected];
    final height = isHome
        ? MediaQuery.textScalerOf(context).scale(56).clamp(56.0, 120.0)
        : 56.0;
    return PreferredSize(
      preferredSize: Size.fromHeight(height),
      child: Material(
        color: colors.surface,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  if (isHome) ...[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/branding/app_icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MiuixText(
                            '信大AIO',
                            style: theme.textStyles.title3,
                            color: colors.onSurface,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          MiuixText(
                            'NUIST · 校园助手',
                            style: theme.textStyles.body2,
                            color: colors.onSurfaceVariantSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: MiuixText(
                          titleText,
                          style: theme.textStyles.title2,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  if (isHome)
                    IconButton(
                      tooltip: '外观与主题',
                      icon: const Icon(Icons.palette_outlined),
                      color: colors.onSurface,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ThemeSettingsPage(state: widget.state),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiuixNavBar(MiuixColors colors) {
    return MiuixNavigationBar(
      color: colors.surface,
      children: [
        MiuixNavigationBarItem(
          selected: selected == 0,
          onPressed: () => setState(() => selected = 0),
          icon: const Icon(Icons.home_outlined),
          label: '首页',
        ),
        MiuixNavigationBarItem(
          selected: selected == 1,
          onPressed: () => setState(() => selected = 1),
          icon: const Icon(Icons.auto_stories_outlined),
          label: '学习',
        ),
        MiuixNavigationBarItem(
          selected: selected == 2,
          onPressed: () => setState(() => selected = 2),
          icon: const Icon(Icons.widgets_outlined),
          label: '功能',
        ),
        MiuixNavigationBarItem(
          selected: selected == 3,
          onPressed: () => setState(() => selected = 3),
          icon: const Icon(Icons.person_outline),
          label: '我的',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final state = widget.state;
    final isMiuix = state.uiStyle == UiStyle.miuix;
    final liquidNav = !isMiuix && state.liquidGlassNav;

    final pages = <Widget>[
      CampusHomePage(
        state: state,
        onLogin: login,
        onLearning: () => setState(() => selected = 1),
        onFeatures: () => setState(() => selected = 2),
      ),
      LearningPage(state: state),
      _FeaturesPage(state: state),
      _ProfilePage(state: state, onLogin: login),
    ];

    if (isMiuix) {
      final miuixColors = MiuixTheme.of(context).colors;
      return Scaffold(
        appBar: _buildMiuixAppBar(selected, miuixColors),
        body: SafeArea(
          top: false,
          child: _TabFadeStack(index: selected, children: pages),
        ),
        // flutter_miuix 1.3 的底栏项固定为 64dp；限制此处标签缩放，
        // 正文仍完整遵循系统大字体，避免底栏标签被裁切。
        bottomNavigationBar: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: _buildMiuixNavBar(miuixColors),
        ),
      );
    }

    return Scaffold(
      // Extend content behind the glass, but bound the navigation slot below:
      // the package's Align otherwise expands to the full scaffold height.
      extendBody: liquidNav,
      appBar: AppBar(
        toolbarHeight: 80,
        title: _buildAppBarTitle(selected, colors),
        actions: [
          if (selected == 0)
            IconButton(
              tooltip: '外观与主题',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ThemeSettingsPage(state: state),
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        // 液态玻璃底栏悬浮时让内容延伸到底栏背后，呈现毛玻璃折射效果。
        bottom: !liquidNav,
        child: _TabFadeStack(index: selected, children: pages),
      ),
      bottomNavigationBar: liquidNav
          ? SizedBox(
              // Match the package's 58px bar + 14px floating gap and its safe
              // area factor. Scaffold can now reserve this actual height.
              height: 58 + 14 + MediaQuery.paddingOf(context).bottom * 0.45,
              child: LiquidGlassNavBar(
                height: 58,
                floatingOffset: 14,
                // 流光是无限循环动画，会让 widget 测试中的 pumpAndSettle
                // 永远无法安定，因此在测试环境下关闭。
                enableShimmer:
                    kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST'),
                // 提高透光率并加强高斯模糊，让底栏后方内容清晰透出，
                // 呈现明显的玻璃质感（浅色/深色分别调参）。
                glassOpacity: colors.brightness == Brightness.dark
                    ? 0.10
                    : 0.14,
                glassBlurSigma: colors.brightness == Brightness.dark ? 26 : 22,
                pillOpacity: colors.brightness == Brightness.dark ? 0.26 : 0.32,
                pillBlurSigma: colors.brightness == Brightness.dark ? 13 : 11,
                currentIndex: selected,
                onTap: (value) => setState(() => selected = value),
                selectedItemColor: colors.primary,
                items: const [
                  LiquidGlassNavBarItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: '首页',
                  ),
                  LiquidGlassNavBarItem(
                    icon: Icons.auto_stories_outlined,
                    activeIcon: Icons.auto_stories,
                    label: '学习',
                  ),
                  LiquidGlassNavBarItem(
                    icon: Icons.widgets_outlined,
                    activeIcon: Icons.widgets,
                    label: '功能',
                  ),
                  LiquidGlassNavBarItem(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    label: '我的',
                  ),
                ],
              ),
            )
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (value) =>
                  setState(() => selected = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: '首页',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_stories_outlined),
                  selectedIcon: Icon(Icons.auto_stories),
                  label: '学习',
                ),
                NavigationDestination(
                  icon: Icon(Icons.widgets_outlined),
                  selectedIcon: Icon(Icons.widgets),
                  label: '功能',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: '我的',
                ),
              ],
            ),
    );
  }
}

class _FeaturesPage extends StatefulWidget {
  const _FeaturesPage({required this.state});
  final AppState state;
  @override
  State<_FeaturesPage> createState() => _FeaturesPageState();
}

class _FeaturesPageState extends State<_FeaturesPage> {
  String query = '';
  String group = '全部';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _features
        .where(
          (f) =>
              (group == '全部' || group == f.group) &&
              (f.name.contains(query.trim()) ||
                  f.detail.contains(query.trim())),
        )
        .toList();
    return PageBody(
      children: [
        TextField(
          controller: search,
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: '搜索校园功能',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      search.clear();
                      setState(() => query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in ['全部', '学习', '生活', '资源'])
              ChoiceChip(
                label: Text(name),
                selected: group == name,
                onSelected: (_) => setState(() => group = name),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: EmptyCard(
              icon: Icons.search_off_outlined,
              title: '没有找到相关功能',
              message: '换一个关键词，或试试其他分类。',
            ),
          ),
        for (final name in ['学习', '生活', '资源'])
          if (matches.any((f) => f.group == name)) ...[
            SectionTitle(name),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Column(
                children: [
                  for (final feature in matches.where((f) => f.group == name))
                    if (SchoolBrowserLinks.all.any(
                      (l) => l.name == feature.name,
                    ))
                      SchoolBrowserEntryTile(
                        link: SchoolBrowserLinks.all.singleWhere(
                          (l) => l.name == feature.name,
                        ),
                        state: widget.state,
                      )
                    else
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: Icon(
                          feature.icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(feature.name),
                        subtitle: Text(feature.detail),
                        trailing:
                            [
                              '图书馆',
                              '校历',
                              '学校公告',
                              '我的课表',
                              '校园卡',
                              '宿舍电费',
                              ...AcademicFeature.values.map((f) => f.label),
                            ].contains(feature.name)
                            ? const Icon(Icons.chevron_right)
                            : const Text('待接入'),
                        onTap: () => feature.name == '图书馆'
                            ? openLibrary(context, widget.state)
                            : feature.name == '校历'
                            ? Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      SchoolCalendarPage(state: widget.state),
                                ),
                              )
                            : feature.name == '我的课表'
                            ? Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                    appBar: AppBar(title: const Text('我的课表')),
                                    body: LearningPage(state: widget.state),
                                  ),
                                ),
                              )
                            : feature.name == '学校公告'
                            ? Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      BulletinPage(state: widget.state),
                                ),
                              )
                            : feature.name == '校园卡'
                            ? openAccounts(context, widget.state)
                            : feature.name == '宿舍电费'
                            ? openAccounts(
                                context,
                                widget.state,
                                section: AccountSection.electricity,
                              )
                            : AcademicFeature.values.any(
                                (f) => f.label == feature.name,
                              )
                            ? openAcademic(
                                context,
                                widget.state,
                                AcademicFeature.values.singleWhere(
                                  (f) => f.label == feature.name,
                                ),
                              )
                            : showPendingFeature(context, feature.name),
                      ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.state, required this.onLogin});
  final AppState state;
  final VoidCallback onLogin;
  Future<void> disconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除本机登录会话？'),
        content: const Text(
          '将清除本软件中的会话凭据、课表、校园账户缓存、宿舍选择与网页登录数据。不会退出系统浏览器中的学校账号。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await uiAction(context, state.disconnect);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDisconnect =
        state.connectedAt != null ||
        state.schedule != null ||
        state.dorm != null ||
        state.accounts.wallet != null ||
        state.accounts.bills != null ||
        state.accounts.electricity != null;
    return PageBody(
      children: [
        ProfileHeader(state: state, onLogin: onLogin),
        const SectionTitle('偏好设置'),
        PreferenceGroup(
          children: [
            PreferenceRow(
              icon: Icons.settings_ethernet,
              title: '网络设置',
              subtitle: '校园直连与学校 WebVPN',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => NetworkSettingsPage(state: state),
                ),
              ),
            ),
            PreferenceRow(
              icon: Icons.palette_outlined,
              title: '外观与主题',
              subtitle: '主题配色、明暗模式、动态取色与界面风格',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ThemeSettingsPage(state: state),
                ),
              ),
            ),
            PreferenceRow(
              icon: Icons.explore_outlined,
              title: '重新查看设置向导',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => OnboardingPage(state: state),
                ),
              ),
            ),
          ],
        ),
        const SectionTitle('课表管理'),
        PreferenceGroup(
          children: [
            PreferenceRow(
              icon: Icons.calendar_month_outlined,
              title: '获取 / 更新课表',
              subtitle: state.schedule?.termName ?? '从学校教务系统导入',
              onTap: () => openScheduleImport(context, state),
            ),
          ],
        ),
        const SectionTitle('校园生活'),
        PreferenceGroup(
          children: [
            PreferenceRow(
              icon: Icons.apartment_outlined,
              title: '实际宿舍',
              subtitle: state.dorm?.label ?? '尚未选择宿舍',
              onTap: () => openDormPicker(context, state),
            ),
            PreferenceRow(
              icon: Icons.credit_card_outlined,
              title: '校园卡与账单',
              onTap: () => openAccounts(context, state),
            ),
          ],
        ),
        const SectionTitle('学习账号'),
        Card(child: ChaoxingAccountTile(state: state)),
        const SectionTitle('账号与隐私'),
        PreferenceGroup(
          children: [
            PreferenceRow(
              icon: Icons.shield_outlined,
              title: '本机会话',
              subtitle: state.connectedAt == null
                  ? '尚未保存凭据'
                  : '上次连接：${state.connectedAt!.month}月${state.connectedAt!.day}日',
              onTap: () {},
              trailing: canDisconnect
                  ? TextButton(
                      onPressed: () => disconnect(context),
                      child: const Text('移除'),
                    )
                  : null,
            ),
          ],
        ),
        const SectionTitle('Wiki'),
        PreferenceGroup(
          children: [
            PreferenceRow(
              icon: Icons.menu_book_outlined,
              title: '南信大公众号与服务',
              subtitle: '官方公众号、总后勤、图书馆等二维码',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const WikiPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        PreferenceGroup(
          children: [
            PreferenceRow(
              icon: Icons.system_update_outlined,
              title: '更新设置',
              subtitle: '版本检查、下载源与更新提醒',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => UpdateSettingsPage(updates: state.updates),
                ),
              ),
            ),
            PreferenceRow(
              icon: Icons.info_outline,
              title: '关于应用',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const AboutPage()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
