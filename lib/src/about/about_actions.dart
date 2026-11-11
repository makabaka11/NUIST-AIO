import 'package:url_launcher/url_launcher.dart';

import '../campus_ui.dart';
import '../widgets.dart';
import '../services/site_registry.dart';

const appVersionLabel = 'v0.5.0 · Build 15';

class AboutActions {
  static Future<void> openLink(
    BuildContext context,
    Uri uri,
    String failure,
  ) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      showCampusSnackBar(context, SnackBar(content: Text(failure)));
    }
  }

  static Future<void> repositories(BuildContext context) async {
    final repository = await showDialog<Uri>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('项目仓库'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, AppReleaseSources.github),
            child: const Text('GitHub'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, AppReleaseSources.gitee),
            child: const Text('Gitee'),
          ),
        ],
      ),
    );
    if (repository == null || !context.mounted) return;
    await openLink(context, repository, '无法打开浏览器，请检查默认浏览器设置。');
  }

  static void feedback(BuildContext context) =>
      showGroupQrDialog(context, '1135530515');
  static void appreciation(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('赞赏码'),
      content: SizedBox(
        width: 280,
        height:
            (MediaQuery.sizeOf(dialog).height -
                    MediaQuery.viewPaddingOf(dialog).vertical -
                    240)
                .clamp(72.0, 280.0),
        child: Image.asset(
          'assets/appreciation_code.png',
          fit: BoxFit.contain,
          semanticLabel: '开发者赞赏码',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  static void introduction(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('关于信大 AIO'),
      content: const Text(
        '为南京信息工程大学同学设计的校园服务整合工具，提供课表、校园账户、图书借阅与校园资讯等功能。\n\n非学校官方应用。密码在学校官方页面输入，会话凭据仅保留在本机。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
  static void developer(BuildContext context) => openLink(
    context,
    Uri.parse('https://www.retr0.xyz'),
    '无法打开浏览器，请检查默认浏览器设置。',
  );
  static void email(BuildContext context) => openLink(
    context,
    Uri.parse('mailto:ded000@retr0.xyz'),
    '无法打开邮件应用，请手动发送至 ded000@retr0.xyz。',
  );
}
