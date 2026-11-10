import 'package:url_launcher/url_launcher.dart';

import '../campus_ui.dart';
import '../widgets.dart';

const appVersionLabel = 'v0.3.5 · Build 14';

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

  static void feedback(BuildContext context) =>
      showGroupQrDialog(context, '1135530515');
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
