import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../theme_settings.dart';
import '../widgets.dart';
import 'invite_codes.dart';

/// 内测注册码页面：首次启动且尚未注册（也未完成过向导）时显示。
/// 输入有效邀请码后写入本地注册标记，随后进入正常的设置向导。
class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key, required this.state});
  final AppState state;
  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final controller = TextEditingController();
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> register() async {
    final code = controller.text;
    if (!isValidInviteCode(code)) {
      setState(() => error = '邀请码不正确。请核对后重试，或向开发者索取新的邀请码。');
      return;
    }
    await uiAction(context, widget.state.setRegistered);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('内测邀请')),
      body: SafeArea(
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
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/branding/app_icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              '信大AIO 内部版本测试',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Text(
              '当前为内部测试阶段，软件通过邀请码定向分发。输入你收到的邀请码完成注册；注册结果只保存在本机，之后不会再要求注册。',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(height: 1.7, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: inviteCodeLength + 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => register(),
              onChanged: (value) {
                if (error != null) setState(() => error = null);
              },
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
              ],
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'XXXX-XXXX-XXXX-XXXX',
                counterText: '',
                prefixIcon: const Icon(Icons.key_outlined),
                errorText: error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '大小写不敏感，连字符可省略。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: register,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: const Text('完成注册'),
              ),
            ),
            const SizedBox(height: 30),
            EmptyCard(
              icon: Icons.lock_outline,
              title: '没有邀请码？',
              message: '内测期间原则上不接受公开注册，但您还是可以尝试联系开发者 ded000@retr0.xyz。',
            ),
          ],
        ),
      ),
    );
  }
}
