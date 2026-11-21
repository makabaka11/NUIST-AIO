/// A public announcement loaded from the application's GitHub repository.
///
/// The file is a Markdown document with a small YAML-style header:
///
/// ```markdown
/// ---
/// title: 关于期末考试安排的通知
/// publisher: 教务处
/// date: 2026-11-20
/// ---
///
/// 正文……
/// ```
///
/// A plain Markdown heading is accepted as a fallback:
///
/// ```markdown
/// # 关于期末考试安排的通知
/// 发布者：教务处
///
/// 正文……
/// ```
class Announcement {
  const Announcement({
    required this.title,
    required this.publisher,
    required this.body,
    required this.source,
    this.publishedAt,
  });

  final String title;
  final String publisher;
  final String body;

  /// Canonical location of the announcement file. Relative images resolve
  /// against this URI.
  final Uri source;
  final DateTime? publishedAt;

  String get signature => '$title\u0000$publisher\u0000$body';

  String get publishedLabel {
    final value = publishedAt;
    if (value == null) return '';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  Map<String, Object?> toCacheJson() => {
    'title': title,
    'publisher': publisher,
    'body': body,
    'source': source.toString(),
    'date': publishedAt?.toIso8601String(),
  };

  static Announcement? fromCacheJson(Object? value) {
    if (value is! Map) return null;
    final title = value['title'];
    final publisher = value['publisher'];
    final body = value['body'];
    final sourceValue = value['source'];
    final dateValue = value['date'];
    final source = sourceValue is String ? Uri.tryParse(sourceValue) : null;
    if (title is! String ||
        publisher is! String ||
        body is! String ||
        title.trim().isEmpty ||
        publisher.trim().isEmpty ||
        body.trim().isEmpty ||
        source == null ||
        source.scheme != 'https' ||
        source.host.isEmpty) {
      return null;
    }
    return Announcement(
      title: title,
      publisher: publisher,
      body: body,
      source: source,
      publishedAt: dateValue is String ? DateTime.tryParse(dateValue) : null,
    );
  }
}

/// Parses the public announcement document.
///
/// Unknown front-matter keys, including future extensions, are ignored. The
/// title, publisher and body are required so a malformed notice is never shown
/// as an empty banner.
Announcement parseAnnouncement(String input, {required Uri source}) {
  final text = input.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n');
  final lines = text.replaceAll('\r', '\n').split('\n');
  var index = 0;
  while (index < lines.length && lines[index].trim().isEmpty) {
    index++;
  }
  if (index >= lines.length) {
    throw const FormatException('公告文件为空。');
  }

  if (lines[index].trim() == '---') {
    final end = _findFrontMatterEnd(lines, index + 1);
    if (end == null) {
      throw const FormatException('公告头部缺少结束标记“---”。');
    }
    final meta = _parseMetadata(lines, index + 1, end);
    return _build(
      meta: meta,
      body: lines.sublist(end + 1).join('\n'),
      source: source,
    );
  }

  return _parseHeadingFormat(lines, index, source);
}

int? _findFrontMatterEnd(List<String> lines, int start) {
  for (var i = start; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line == '---' || line == '...') return i;
  }
  return null;
}

Map<String, String> _parseMetadata(List<String> lines, int start, int end) {
  final meta = <String, String>{};
  for (var i = start; i < end; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf(':');
    if (separator <= 0) {
      throw FormatException('公告头部第 ${i - start + 1} 行格式无效，应为“键: 值”。');
    }
    final key = line
        .substring(0, separator)
        .trim()
        .toLowerCase()
        .replaceAll('-', '_');
    final value = _unquote(line.substring(separator + 1));
    if (key.isNotEmpty) meta[key] = value;
  }
  return meta;
}

Announcement _parseHeadingFormat(List<String> lines, int start, Uri source) {
  String? title;
  var titleIndex = -1;
  for (var i = start; i < lines.length; i++) {
    final match = RegExp(r'^#{1,6}\s+(.+?)\s*#*\s*$')
        .firstMatch(lines[i].trim());
    if (match != null) {
      title = match.group(1)!.trim();
      titleIndex = i;
      break;
    }
  }
  if (title == null || title.isEmpty) {
    throw const FormatException('公告缺少标题，请使用“---”头部或一级标题。');
  }

  final meta = <String, String>{};
  var lastMetaLine = titleIndex;
  for (var i = titleIndex + 1; i < lines.length; i++) {
    final raw = lines[i];
    final line = raw.trim().replaceFirst(RegExp(r'^>\s*'), '');
    if (line.isEmpty) {
      if (lastMetaLine == i - 1) {
        // Blank lines between the title and metadata are allowed.
        lastMetaLine = i;
        continue;
      }
      break;
    }
    final publisher = _headerValue(line, const [
      '发布者',
      '发布单位',
      '作者',
      'publisher',
      'author',
    ]);
    if (publisher != null) {
      meta['publisher'] = publisher;
      lastMetaLine = i;
      continue;
    }
    final date = _headerValue(line, const [
      '发布时间',
      '发布日期',
      '日期',
      'date',
      'published',
      'published_at',
    ]);
    if (date != null) {
      meta['date'] = date;
      lastMetaLine = i;
      continue;
    }
    break;
  }

  final body = lines.sublist(lastMetaLine + 1).join('\n');
  return _build(meta: {...meta, 'title': title}, body: body, source: source);
}

String? _headerValue(String line, List<String> keys) {
  for (final key in keys) {
    final match = RegExp(
      '^${RegExp.escape(key)}\\s*[：:]\\s*(.+)\$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match != null) return _unquote(match.group(1)!);
  }
  return null;
}

String _cleanBody(String body) {
  // Remove blank separator lines without eating the indentation of a code
  // block that legitimately starts the announcement body.
  var value = body.replaceFirst(RegExp(r'^(?:[ \t]*\n)+'), '');
  value = value.trimRight();
  return value;
}

String _unquote(String value) {
  var result = value.trim();
  if (result.length >= 2) {
    final first = result[0], last = result[result.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      result = result.substring(1, result.length - 1).trim();
    }
  }
  return result;
}

Announcement _build({
  required Map<String, String> meta,
  required String body,
  required Uri source,
}) {
  String? pick(List<String> keys) {
    for (final key in keys) {
      final value = meta[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  final title = pick(const ['title', '标题']);
  final publisher = pick(const ['publisher', 'author', '发布者', '发布单位', '作者']);
  final content = _cleanBody(body);
  if (title == null) throw const FormatException('公告缺少标题。');
  if (publisher == null) throw const FormatException('公告缺少发布者。');
  if (content.isEmpty) throw const FormatException('公告正文为空。');

  return Announcement(
    title: title,
    publisher: publisher,
    body: content,
    source: source,
    publishedAt: _parseDate(
      pick(const ['date', 'published', 'published_at', '发布时间', '发布日期']),
    ),
  );
}

DateTime? _parseDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Resolves a Markdown link or image against [base], accepting only HTTP(S).
///
/// This deliberately rejects `javascript:`, `file:` and other schemes even if
/// the announcement file is later edited by a compromised account.
Uri? resolveAnnouncementUri(Uri reference, Uri base) {
  final Uri resolved;
  if (reference.hasScheme) {
    resolved = reference;
  } else {
    if (!base.hasScheme || base.host.isEmpty) return null;
    try {
      resolved = base.resolveUri(reference);
    } catch (_) {
      return null;
    }
  }
  if (resolved.scheme != 'https' && resolved.scheme != 'http') return null;
  if (resolved.host.isEmpty || resolved.userInfo.isNotEmpty) return null;
  return resolved;
}

/// Image URLs to try in order. Relative images live on
/// `raw.githubusercontent.com`, which is not reachable from every campus
/// network, so the same file is tried through the built-in GitHub mirror and
/// jsDelivr first. Absolute image URLs are never rewritten.
List<Uri> resolveAnnouncementImageCandidates(Uri reference, Uri base) {
  final resolved = resolveAnnouncementUri(reference, base);
  if (resolved == null) return const [];
  if (resolved.host != 'raw.githubusercontent.com') return [resolved];
  final segments = resolved.pathSegments;
  if (segments.length < 4) return [resolved];
  final owner = segments[0];
  final repository = segments[1];
  final branch = segments[2];
  final path = segments.sublist(3).join('/');
  final mirror = Uri.parse('https://gh-proxy.org/$resolved');
  final jsDelivr = Uri.https(
    'cdn.jsdelivr.net',
    '/gh/$owner/$repository@$branch/$path',
  );
  final candidates = <Uri>[];
  for (final uri in [mirror, jsDelivr, resolved]) {
    if (!candidates.contains(uri)) candidates.add(uri);
  }
  return candidates;
}
