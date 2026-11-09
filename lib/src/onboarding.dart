import 'package:flutter/material.dart';

import 'app_state.dart';
import 'accounts/dorm_picker.dart';
import 'auth/login_page.dart';
import 'theme_settings.dart';
import 'widgets.dart';
import 'services/initialization_panel.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.state});
  final AppState state;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int step = 0;
  bool saving = false;
  void goTo(int value) {
    setState(() => step = value);
    if (value == 3 && widget.state.connectedAt != null) {
      widget.state.connectCampusServices(synchronizeData: false);
    }
  }

  Future<void> login() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            LoginPage(state: widget.state, initializeServices: false),
      ),
    );
    if (mounted && widget.state.connectedAt != null) goTo(3);
  }

  Future<void> finish() async {
    setState(() => saving = true);
    final replay = widget.state.onboarded;
    await uiAction(context, widget.state.finishOnboarding);
    if (widget.state.connectedAt != null) widget.state.connectCampusServices();
    if (mounted && replay) {
      Navigator.pop(context);
      return;
    }
    if (mounted) {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          leading: step > 0
              ? IconButton(
                  tooltip: '上一步',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.state.connectingServices
                      ? null
                      : () => goTo(step - 1),
                )
              : null,
          title: const Text('欢迎使用'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Center(
                child: Text(
                  '${step + 1} / 5',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: LinearProgressIndicator(
                  value: (step + 1) / 5,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              Expanded(
                child: PageBody(
                  children: [
                    const SizedBox(height: 26),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Icon(
                          [
                            Icons.school_outlined,
                            Icons.palette_outlined,
                            Icons.verified_user_outlined,
                            Icons.hub_outlined,
                            Icons.apartment_outlined,
                          ][step],
                          size: 36,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      [
                        '校园日常，一站就好。',
                        '选一个喜欢的模样。',
                        '连接你的校园。',
                        '初始化校园服务。',
                        '选好你的宿舍。',
                      ][step],
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      [
                        '欢迎来到信大AIO。将学习与校园服务收在一处，从容安排每一天。',
                        '主题会应用到整个软件，也可以随时在“我的”中调整。',
                        '前往学校统一身份认证页面，自行完成登录。我们会在成功返回门户后识别并保存会话凭据。',
                        '使用刚刚的主账号会话自动连接已接入的子站点，分别获取并验证业务凭据。未接入的站点会保留在清单中。',
                        '从学校完整目录选择服务范围与房间，让电量查询准确对应你的宿舍。',
                      ][step],
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.7,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (step == 0) ...[
                      const SizedBox(height: 34),
                      for (final item in [
                        (Icons.calendar_today_outlined, '学习有安排', '课表、教室与学习入口'),
                        (Icons.widgets_outlined, '服务在身边', '校园卡、电费与图书馆'),
                        (Icons.lock_outline, '账号由你掌握', '官方页面登录，不保存账号密码'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: colors.secondaryContainer,
                              child: Icon(
                                item.$1,
                                color: colors.onSecondaryContainer,
                              ),
                            ),
                            title: Text(item.$2),
                            subtitle: Text(item.$3),
                          ),
                        ),
                    ],
                    if (step == 1) ThemeControls(state: widget.state),
                    if (step == 2) ...[
                      const SizedBox(height: 30),
                      EmptyCard(
                        icon: widget.state.connectedAt != null
                            ? Icons.check_circle_outline
                            : Icons.lock_outline,
                        title: widget.state.connectedAt != null
                            ? '已获取登录会话'
                            : '只在学校官方页面登录',
                        message: widget.state.connectedAt != null
                            ? '准备好了。会话到期后可在“我的”中重新连接。'
                            : '密码与验证码由你在官方页面输入。会话保留在本机，不上传到我们的服务器。',
                        action: widget.state.connectedAt == null
                            ? FilledButton.icon(
                                icon: const Icon(Icons.arrow_outward),
                                label: const Text('前往统一认证'),
                                onPressed: login,
                              )
                            : null,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '也可以稍后连接。进入“学习”即可从教务系统获取课表，其他校园服务将逐步接入。',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ],
                    if (step == 3) ...[
                      const SizedBox(height: 24),
                      ServiceInitializationPanel(state: widget.state),
                    ],
                    if (step == 4) ...[
                      const SizedBox(height: 28),
                      EmptyCard(
                        icon: Icons.apartment_outlined,
                        title: widget.state.dorm == null ? '选择实际宿舍' : '宿舍已选择',
                        message:
                            widget.state.dorm?.label ??
                            '本部、沁园 42/43、金牛湖使用不同电费入口。可按园区、楼栋和房号搜索选择。',
                        action: FilledButton.icon(
                          onPressed: () =>
                              openDormPicker(context, widget.state),
                          icon: const Icon(Icons.edit_location_alt_outlined),
                          label: Text(
                            widget.state.dorm == null ? '选择宿舍' : '修改宿舍',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('也可以稍后在“我的 → 实际宿舍”中设置。宿舍选择只保存在本机，不绑定学校缴费账户。'),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        saving || (step == 3 && widget.state.connectingServices)
                        ? null
                        : () {
                            if (step < 4) {
                              goTo(step + 1);
                            } else {
                              finish();
                            }
                          },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    child: Text(
                      step < 4
                          ? (step == 0 ? '开始设置' : '下一步')
                          : (widget.state.dorm != null ? '开启校园日常' : '稍后选择，先逛逛'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
