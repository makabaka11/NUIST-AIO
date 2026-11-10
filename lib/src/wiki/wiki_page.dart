// 南信大 Wiki 页面：聚合校内常用公众号与论坛等入口。
// 每个条目点击后展示对应二维码弹窗（带"保存"与"关闭"按钮），
// 用户可扫码关注或保存到本机。

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: campusAppBar(context, title: '南信大 Wiki'),
      body: PageBody(
        children: [
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
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '点击任一条目查看对应二维码，可在弹窗中保存到本机后用微信扫码关注。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
