// 南信大 Wiki 页面：聚合校内常用公众号与论坛等入口。
// 每个条目点击后展示对应二维码弹窗（带"保存"与"关闭"按钮），
// 用户可扫码关注或保存到本机。

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/site_registry.dart';

import '../campus_ui.dart';

import '../miuix_widgets.dart';
import '../widgets.dart';

/// 一条 Wiki 条目：公众号 / 论坛 / 服务号的展示信息。
class WikiEntry {
  const WikiEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.assetPath,
    required this.fileNamePrefix,
  });

  /// 展示标题。
  final String title;

  /// 用途说明，作为副标题展示在条目下方。
  final String subtitle;

  /// 条目图标。
  final IconData icon;

  /// assets 目录下二维码图片路径。
  final String assetPath;

  /// 保存到本机时的文件名前缀，避免不同二维码相互覆盖。
  final String fileNamePrefix;
}

/// 当前已挂载的南信大公众号 / 服务号条目。
/// 新增条目时只需追加到此列表，页面会自动渲染。
const List<WikiEntry> nuistWikiEntries = <WikiEntry>[
  WikiEntry(
    title: '南信大公众号',
    subtitle: '学校官方公众号，发布校园新闻与通知',
    icon: Icons.campaign_outlined,
    assetPath: 'assets/qrcode_nuist1960_1.jpg',
    fileNamePrefix: 'nuist1960',
  ),
  WikiEntry(
    title: '南信大总后勤',
    subtitle: '食堂和宿舍调整等信息（例如假期宿舍开放情况）',
    icon: Icons.restaurant_outlined,
    assetPath: 'assets/qrcode_nuistzw_1.jpg',
    fileNamePrefix: 'nuistzw',
  ),
  WikiEntry(
    title: '南信大图书馆',
    subtitle: '检索馆藏图书、预约自习空间',
    icon: Icons.local_library_outlined,
    assetPath: 'assets/tdc_weixin.png',
    fileNamePrefix: 'nuist_tdc',
  ),
];

/// 南信大 Wiki 页面。从"我的"页面进入。
///
/// 列出已挂载的公众号 / 服务号条目，点击任一条目弹出对应二维码，
/// 弹窗提供"保存"与"关闭"两个按钮。
class WikiPage extends StatelessWidget {
  const WikiPage({super.key});

  Future<void> openCampusPolice(BuildContext context) async {
    const number = '58736110';
    try {
      if (await launchUrl(
        Uri(scheme: 'tel', path: number),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    try {
      await Clipboard.setData(const ClipboardData(text: number));
      if (context.mounted) {
        showCampusSnackBar(
          context,
          const SnackBar(content: Text('无法打开拨号页，校内报警电话已复制')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        showCampusSnackBar(
          context,
          const SnackBar(content: Text('请手动拨打校内报警电话：58736110')),
        );
      }
    }
  }

  Future<void> openForum(BuildContext context) async {
    try {
      if (await launchUrl(
        WikiCommunitySources.tieba,
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (context.mounted) {
      showCampusSnackBar(
        context,
        const SnackBar(content: Text('无法打开贴吧，请检查系统浏览器')),
      );
    }
  }

  void showMarket(BuildContext context) => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('校园集市'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('复制下方小程序链接，粘贴到微信任意对话并发送后，点击即可打开。'),
          SizedBox(height: 16),
          SelectableText(WikiCommunitySources.campusMarket),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await Clipboard.setData(
                const ClipboardData(text: WikiCommunitySources.campusMarket),
              );
              if (dialog.mounted) {
                showCampusSnackBar(
                  dialog,
                  const SnackBar(content: Text('小程序链接已复制，请粘贴到微信对话')),
                );
              }
            } catch (_) {
              if (dialog.mounted) {
                showCampusSnackBar(
                  dialog,
                  const SnackBar(content: Text('复制失败，请长按链接手动复制')),
                );
              }
            }
          },
          child: const Text('复制链接'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: campusAppBar(context, title: '南信大 Wiki'),
      body: PageBody(
        children: [
          PreferenceGroup(
            children: [
              PreferenceRow(
                icon: Icons.local_police_outlined,
                title: '校内报警电话',
                subtitle: '58736110 · 点击拨号，不支持时复制',
                onTap: () => openCampusPolice(context),
              ),
              PreferenceRow(
                icon: Icons.local_shipping_outlined,
                title: '常用收货地址',
                subtitle: '东苑、中苑与西苑快递站 · 支持复制',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const DeliveryAddressesPage(),
                  ),
                ),
              ),
            ],
          ),
          const SectionTitle('公众号与服务'),
          PreferenceGroup(
            children: [
              for (final entry in nuistWikiEntries)
                PreferenceRow(
                  icon: entry.icon,
                  title: entry.title,
                  subtitle: entry.subtitle,
                  onTap: () => showAssetQrDialog(
                    context,
                    title: entry.title,
                    assetPath: entry.assetPath,
                    fileNamePrefix: entry.fileNamePrefix,
                    caption: entry.subtitle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '点击上方公众号条目查看对应二维码，可在弹窗中保存到本机后用微信扫码关注。',
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SectionTitle('论坛'),
          PreferenceGroup(
            children: [
              PreferenceRow(
                icon: Icons.forum_outlined,
                title: '贴吧',
                subtitle: '南京信息工程大学吧 · 在系统浏览器中打开',
                onTap: () => openForum(context),
              ),
              PreferenceRow(
                icon: Icons.storefront_outlined,
                title: '校园集市',
                subtitle: '复制小程序链接，粘贴到微信对话后打开',
                onTap: () => showMarket(context),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            '如有遗漏或建议欢迎反馈补充',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

const deliveryAddresses = <String, List<String>>{
  '东苑': ['江苏省南京市浦口区南京信息工程大学文德楼快递站，210044', '江苏省南京市浦口区盘锦花园菜鸟驿站，210044'],
  '中苑/通用': ['江苏省南京市浦口区南信大气象谷快递站，210044'],
  '西苑': ['江苏省南京市浦口区南京信息工程大学滨江楼快递站，210044'],
};

class DeliveryAddressesPage extends StatelessWidget {
  const DeliveryAddressesPage({super.key});

  Future<void> copy(BuildContext context, String address) async {
    try {
      await Clipboard.setData(ClipboardData(text: address));
      if (context.mounted) {
        showCampusSnackBar(context, const SnackBar(content: Text('收货地址已复制')));
      }
    } catch (_) {
      if (context.mounted) {
        showCampusSnackBar(context, const SnackBar(content: Text('复制失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: campusAppBar(context, title: '常用收货地址'),
    body: PageBody(
      children: [
        for (final group in deliveryAddresses.entries) ...[
          SectionTitle(group.key),
          PreferenceGroup(
            children: [
              for (final address in group.value)
                ListTile(
                  title: Text(address),
                  subtitle: const Text('点击复制收货地址'),
                  trailing: const Icon(Icons.copy_outlined),
                  onTap: () => copy(context, address),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}
