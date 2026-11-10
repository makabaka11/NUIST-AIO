import '../campus_ui.dart';
import 'about_actions.dart';

/// MD3 使用标准顶栏、主题色容器与图标列表，不使用 MIUIX 的渐变展示页。
class MaterialAboutPage extends StatelessWidget {
  const MaterialAboutPage({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const AppBar(title: Text('关于应用')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                color: colors.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/branding/app_icon.png',
                          width: 80,
                          height: 80,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '信大 AIO',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: colors.onPrimaryContainer),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        appVersionLabel,
                        style: TextStyle(color: colors.onPrimaryContainer),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '让校园生活，简单一点。',
                        style: TextStyle(color: colors.onPrimaryContainer),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.forum_outlined),
                      title: const Text('交流与反馈'),
                      subtitle: const Text('信大AIO交流群 · 1135530515'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => AboutActions.feedback(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('关于信大 AIO'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => AboutActions.introduction(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('开源许可'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showCampusLicenses(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 12),
                child: Text(
                  '开发者',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: colors.primary),
                ),
              ),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.code_outlined),
                      title: const Text('Retr0'),
                      subtitle: const Text('www.retr0.xyz'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => AboutActions.developer(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: const Text('联系邮箱'),
                      subtitle: const Text('ded000@retr0.xyz'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => AboutActions.email(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
