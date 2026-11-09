import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_liquid_glass_nav_bar/flutter_liquid_glass_nav_bar.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
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

const _features = <({String name, String group, String detail, IconData icon})>[
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
];

class CampusShell extends StatefulWidget {
  const CampusShell({super.key, required this.state});
  final AppState state;
  @override
  State<CampusShell> createState() => _CampusShellState();
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
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final liquidNav = widget.state.liquidGlassNav;
    return Scaffold(
      extendBody: liquidNav,
      appBar: AppBar(
        toolbarHeight: 80,
        title: selected == 0
            ? Row(
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
              )
            : Text(['首页', '学习', '功能', '我的'][selected]),
        actions: [
          if (selected == 0)
            IconButton(
              tooltip: '外观与主题',
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ThemeSettingsPage(state: widget.state),
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
        child: IndexedStack(
          index: selected,
          children: [
            CampusHomePage(
              state: widget.state,
              onLogin: login,
              onLearning: () => setState(() => selected = 1),
              onFeatures: () => setState(() => selected = 2),
            ),
            LearningPage(state: widget.state),
            _FeaturesPage(state: widget.state),
            _ProfilePage(state: widget.state, onLogin: login),
          ],
        ),
      ),
      bottomNavigationBar: liquidNav
          ? LiquidGlassNavBar(
              // 流光是无限循环动画，会让 widget 测试中的 pumpAndSettle
              // 永远无法安定，因此在测试环境下关闭。
              enableShimmer:
                  kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST'),
              // 提高透光率并加强高斯模糊，让底栏后方内容清晰透出，
              // 呈现明显的玻璃质感（浅色/深色分别调参）。
              glassOpacity:
                  colors.brightness == Brightness.dark ? 0.10 : 0.14,
              glassBlurSigma:
                  colors.brightness == Brightness.dark ? 26 : 22,
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
            )
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (value) => setState(() => selected = value),
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
                            '我的课表',
                            '校园卡',
                            '宿舍电费',
                            ...AcademicFeature.values.map((f) => f.label),
                          ].contains(feature.name)
                          ? const Icon(Icons.chevron_right)
                          : const Text('待接入'),
                      onTap: () => feature.name == '我的课表'
                          ? Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text('我的课表')),
                                  body: LearningPage(state: widget.state),
                                ),
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

  Future<void> launchDeveloperLink(
    BuildContext context,
    Uri uri, {
    required String fallback,
  }) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(fallback)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PageBody(
      children: [
        Card(
          color: colors.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colors.primary,
                  child: Icon(
                    Icons.person_outline,
                    size: 30,
                    color: colors.onPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  state.schedule != null
                      ? '课表已导入'
                      : state.connectedAt == null
                      ? '你好，南信同学'
                      : '校园账号已连接',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: colors.onPrimaryContainer),
                ),
                const SizedBox(height: 8),
                Text(
                  state.connectedAt == null
                      ? (state.schedule != null
                            ? '课表已在本机保存，可离线查看。'
                            : '连接账号，开启你的校园日常。')
                      : '已保存本机会话，实际有效性以学校验证为准。',
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.tonalIcon(
                  onPressed: onLogin,
                  icon: const Icon(Icons.link),
                  label: Text(state.connectedAt == null ? '连接校园账号' : '重新连接'),
                ),
              ],
            ),
          ),
        ),
        const SectionTitle('偏好设置'),
        Card(
          color: colors.surfaceContainerLow,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('外观与主题'),
                subtitle: const Text('主题配色、明暗模式与动态取色'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ThemeSettingsPage(state: state),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                title: const Text('重新查看设置向导'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => OnboardingPage(state: state),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('课表管理'),
        Card(
          color: colors.surfaceContainerLow,
          child: ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('获取 / 更新课表'),
            subtitle: Text(state.schedule?.termName ?? '从学校教务系统导入'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openScheduleImport(context, state),
          ),
        ),
        const SectionTitle('校园生活'),
        Card(
          color: colors.surfaceContainerLow,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.apartment_outlined),
                title: const Text('实际宿舍'),
                subtitle: Text(state.dorm?.label ?? '尚未选择宿舍'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openDormPicker(context, state),
              ),
              ListTile(
                leading: const Icon(Icons.credit_card_outlined),
                title: const Text('校园卡与账单'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openAccounts(context, state),
              ),
            ],
          ),
        ),
        const SectionTitle('账号与隐私'),
        Card(
          color: colors.surfaceContainerLow,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('本机会话'),
                subtitle: Text(
                  state.connectedAt == null
                      ? '尚未保存凭据'
                      : '上次连接：${state.connectedAt!.month}月${state.connectedAt!.day}日',
                ),
                trailing:
                    state.connectedAt == null &&
                        state.schedule == null &&
                        state.dorm == null &&
                        state.accounts.wallet == null &&
                        state.accounts.bills == null &&
                        state.accounts.electricity == null
                    ? null
                    : TextButton(
                        onPressed: () => disconnect(context),
                        child: const Text('移除'),
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('关于信大AIO'),
                subtitle: const Text('0.3.5 · 校园账户'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: '信大AIO',
                  applicationVersion: '0.3.5',
                  applicationIcon: Image.asset(
                    'assets/branding/app_icon.png',
                    width: 48,
                    height: 48,
                  ),
                  children: [
                    const Text(
                      '为南京信息工程大学同学设计的校园服务整合工具。已支持教务课表、校园卡余额、账单和宿舍电量查询，其他校园服务逐步接入。\n\n非学校官方应用。密码在学校官方页面输入，会话凭据仅保留在本机。',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('开发者'),
        Card(
          color: colors.surfaceContainerLow,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('Retr0'),
                subtitle: const Text('www.retr0.xyz'),
                trailing: const Icon(Icons.open_in_new_outlined),
                onTap: () => launchDeveloperLink(
                  context,
                  Uri.parse('https://www.retr0.xyz'),
                  fallback: '无法打开浏览器，请检查默认浏览器设置。',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('联系邮箱'),
                subtitle: const Text('ded000@retr0.xyz'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => launchDeveloperLink(
                  context,
                  Uri.parse('mailto:ded000@retr0.xyz'),
                  fallback: '无法打开邮件应用，请手动发送至 ded000@retr0.xyz。',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Text(
            '让校园生活，简单一点。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
