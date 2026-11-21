import 'dart:async';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../campus_ui.dart';
import '../services/site_registry.dart';
import 'announcement.dart';
import 'announcement_service.dart';

/// The public notice strip shown above the homepage greeting.
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key, required this.controller});
  final AnnouncementController controller;

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  @override
  void initState() {
    super.initState();
    // main() already starts the fetch. This fallback covers hosts and widget
    // tests that mount CampusApp directly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.refreshOnStartup();
    });
  }

  void open() {
    final announcement = widget.controller.announcement;
    if (announcement == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnnouncementPage(
          announcement: announcement,
          fromCache: widget.controller.fromCache,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final announcement = widget.controller.announcement;
      if (announcement == null || widget.controller.dismissed) {
        return const SizedBox.shrink();
      }
      final colors = Theme.of(context).colorScheme;
      final published = announcement.publishedLabel;
      final subtitle = [
        announcement.publisher,
        if (published.isNotEmpty) published,
        '点击查看详情',
      ].join(' · ');
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          color: colors.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            container: true,
            label: '公告：${announcement.title}',
            child: ListTile(
              contentPadding: const EdgeInsets.only(
                left: 14,
                right: 2,
                top: 5,
                bottom: 5,
              ),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.campaign_outlined,
                  color: colors.onPrimaryContainer,
                  size: 24,
                ),
              ),
              title: Text(
                announcement.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600, height: 1.35),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '关闭公告',
                    icon: const Icon(Icons.close, size: 20),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.controller.dismiss,
                  ),
                  Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                ],
              ),
              onTap: open,
            ),
          ),
        ),
      );
    },
  );
}

/// Full Markdown content of the current public notice.
class AnnouncementPage extends StatelessWidget {
  const AnnouncementPage({
    super.key,
    required this.announcement,
    this.fromCache = false,
    this.openLink,
  });

  final Announcement announcement;
  final bool fromCache;

  /// Test seam; production opens the system browser.
  final Future<bool> Function(Uri url)? openLink;

  Future<void> _open(BuildContext context, Uri url) async {
    var opened = false;
    try {
      opened =
          await (openLink?.call(url) ??
              launchUrl(url, mode: LaunchMode.externalApplication));
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      showCampusSnackBar(
        context,
        const SnackBar(content: Text('无法打开链接，请检查默认浏览器设置。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final published = announcement.publishedLabel;
    return Scaffold(
      appBar: AppBar(title: const Text('公告')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                MediaQuery.paddingOf(context).bottom + 28,
              ),
              children: [
                Text(
                  announcement.title,
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 17,
                      color: colors.onSurfaceVariant,
                    ),
                    Text(
                      announcement.publisher,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (published.isNotEmpty)
                      Text(
                        '· $published',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                if (fromCache) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 17,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '当前显示上次成功读取的公告；联网后会自动更新。',
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Divider(height: 34, color: colors.outlineVariant),
                MarkdownBody(
                  data: announcement.body,
                  selectable: true,
                  styleSheet: _styleSheet(context),
                  imageBuilder: (uri, title, alt) =>
                      _image(context, uri, alt, announcement.source),
                  onTapLink: (text, href, title) {
                    final reference = href == null ? null : Uri.tryParse(href);
                    final resolved = reference == null
                        ? null
                        : resolveAnnouncementUri(
                            reference,
                            AppAnnouncementSource.page,
                          );
                    if (resolved == null) {
                      showCampusSnackBar(
                        context,
                        const SnackBar(content: Text('该链接地址无效，已阻止打开。')),
                      );
                      return;
                    }
                    unawaited(_open(context, resolved));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final body = theme.textTheme.bodyLarge?.copyWith(
      height: 1.75,
      color: colors.onSurface,
    );
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      a: body?.copyWith(
        color: colors.primary,
        decoration: TextDecoration.underline,
        decorationColor: colors.primary,
      ),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      blockSpacing: 14,
      listIndent: 22,
      blockquote: body?.copyWith(color: colors.onSurfaceVariant),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      blockquoteDecoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      code: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: colors.surfaceContainerHighest,
      ),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
    );
  }

  Widget _image(BuildContext context, Uri reference, String? alt, Uri base) {
    final candidates = resolveAnnouncementImageCandidates(reference, base);
    if (candidates.isEmpty) {
      return _imagePlaceholder(context, alt, '图片地址无效或不是 HTTP(S) 地址。');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _AnnouncementImage(urls: candidates, alt: alt),
      ),
    );
  }
}

class _AnnouncementImage extends StatefulWidget {
  const _AnnouncementImage({required this.urls, this.alt});

  final List<Uri> urls;
  final String? alt;

  @override
  State<_AnnouncementImage> createState() => _AnnouncementImageState();
}

class _AnnouncementImageState extends State<_AnnouncementImage> {
  int _index = 0;
  bool _retryScheduled = false;

  @override
  void didUpdateWidget(covariant _AnnouncementImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.isEmpty ||
        widget.urls.isEmpty ||
        oldWidget.urls.first != widget.urls.first) {
      _index = 0;
    } else if (_index >= widget.urls.length) {
      _index = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = widget.urls[_index];
    return Image.network(
      uri.toString(),
      key: ValueKey(uri),
      fit: BoxFit.contain,
      semanticLabel: widget.alt,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        final total = progress.expectedTotalBytes;
        return Container(
          height: 180,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          alignment: Alignment.center,
          child: CircularProgressIndicator(
            value: total == null || total == 0
                ? null
                : progress.cumulativeBytesLoaded / total,
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        if (_index + 1 < widget.urls.length) {
          if (!_retryScheduled) {
            _retryScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _retryScheduled = false;
              if (_index + 1 < widget.urls.length) {
                setState(() => _index++);
              }
            });
          }
          return _imagePlaceholder(context, widget.alt, '图片加载失败，正在尝试备用地址…');
        }
        return _imagePlaceholder(context, widget.alt, '图片加载失败，请检查网络或图片地址。');
      },
    );
  }
}

Widget _imagePlaceholder(BuildContext context, String? alt, String message) {
  final colors = Theme.of(context).colorScheme;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    color: colors.surfaceContainerLow,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.image_not_supported_outlined,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(height: 8),
        Text(
          alt == null || alt.isEmpty ? message : '$message\n$alt',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    ),
  );
}
