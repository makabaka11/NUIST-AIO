import 'dart:ffi';

import 'package:flutter/foundation.dart';

import '../services/site_registry.dart';

/// Public GitHub release files use the built-in mirror without a switch.
Uri githubUpdateMirror(Uri url) =>
    url.scheme == 'https' &&
        url.userInfo.isEmpty &&
        (!url.hasPort || url.port == 443) &&
        url.host == 'github.com'
    ? Uri.parse('https://gh-proxy.org/$url')
    : url;

enum UpdateSource {
  github('GitHub'),
  gitee('Gitee');

  const UpdateSource(this.label);
  final String label;
  Uri get repository =>
      this == github ? AppReleaseSources.github : AppReleaseSources.gitee;
  Uri get api => this == github
      ? AppReleaseSources.githubReleases
      : AppReleaseSources.giteeReleases;
  Uri releasePage(String tag) => Uri(
    scheme: repository.scheme,
    host: repository.host,
    pathSegments: [...repository.pathSegments, 'releases', 'tag', tag],
  );
}

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, {this.build});
  final int major, minor, patch;
  final int? build;
  static AppVersion? parse(String text) {
    final match = RegExp(r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:(?:\+|-|\.)(\d+))?$')
        .firstMatch(text.trim());
    if (match == null) return null;
    final values = [
      for (var i = 1; i <= 4; i++)
        match[i] == null ? null : int.tryParse(match[i]!),
    ];
    if (values.take(3).any((v) => v == null)) return null;
    return AppVersion(values[0]!, values[1]!, values[2]!, build: values[3]);
  }

  bool newerThan(AppVersion other) {
    if (major == other.major &&
        minor == other.minor &&
        patch == other.patch &&
        (build == null || other.build == null)) {
      return false;
    }
    return compareTo(other) > 0;
  }

  @override
  int compareTo(AppVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final c = pair.$1.compareTo(pair.$2);
      if (c != 0) return c;
    }
    return (build ?? 0).compareTo(other.build ?? 0);
  }
}

class InstalledBuild {
  const InstalledBuild(this.version, this.buildNumber);
  final String version, buildNumber;
  String get label =>
      'v$version${buildNumber.isEmpty ? '' : ' · Build $buildNumber'}';
  AppVersion get comparable {
    final parsed = AppVersion.parse(version);
    if (parsed == null) throw const FormatException('当前应用版本格式无效，无法比较更新。');
    return AppVersion(
      parsed.major,
      parsed.minor,
      parsed.patch,
      build: int.tryParse(buildNumber) ?? parsed.build,
    );
  }
}

class UpdateRuntime {
  const UpdateRuntime(this.platform, this.arch);
  final TargetPlatform platform;
  final String arch;
  factory UpdateRuntime.current() {
    final abi = Abi.current().toString().toLowerCase();
    final arch = abi.contains('arm64')
        ? 'arm64'
        : abi.contains('arm')
        ? 'arm'
        : abi.contains('x64')
        ? 'x64'
        : 'x86';
    return UpdateRuntime(defaultTargetPlatform, arch);
  }
}

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url);
  final String name;
  final Uri url;
}

class AppRelease {
  const AppRelease({
    required this.source,
    required this.tag,
    required this.version,
    required this.notes,
    required this.page,
    required this.assets,
  });
  final UpdateSource source;
  final String tag, notes;
  final AppVersion version;
  final Uri page;
  final List<ReleaseAsset> assets;
  String get key => '${source.name}:$tag';
  Uri? packageFor(UpdateRuntime runtime) => assetFor(runtime)?.url;

  ReleaseAsset? assetFor(UpdateRuntime runtime) {
    int score(ReleaseAsset asset) {
      final n = asset.name.toLowerCase();
      final ext = switch (runtime.platform) {
        TargetPlatform.android => n.endsWith('.apk'),
        TargetPlatform.macOS => n.endsWith('.dmg') || n.endsWith('.zip'),
        TargetPlatform.windows =>
          n.endsWith('.exe') || n.endsWith('.msix') || n.endsWith('.zip'),
        TargetPlatform.linux => n.endsWith('.appimage') || n.endsWith('.deb'),
        _ => false,
      };
      if (!ext ||
          RegExp(r'(^|[-_.])(debug|test|symbols)([-_.]|$)').hasMatch(n)) {
        return -1;
      }
      if (n.endsWith('.zip') &&
          !RegExp(r'macos|mac|darwin|windows|win64|win32').hasMatch(n)) {
        return -1;
      }
      if (runtime.platform == TargetPlatform.macOS &&
          RegExp(r'windows|win64|win32').hasMatch(n)) {
        return -1;
      }
      if (runtime.platform == TargetPlatform.windows &&
          RegExp(r'macos|darwin|(^|[-_.])mac([-_.]|$)').hasMatch(n)) {
        return -1;
      }
      String? arch;
      if (RegExp(r'arm64|aarch64').hasMatch(n)) {
        arch = 'arm64';
      } else if (RegExp(r'armeabi|armv7|arm32').hasMatch(n)) {
        arch = 'arm';
      } else if (RegExp(r'x86_64|amd64|x64|win64').hasMatch(n)) {
        arch = 'x64';
      } else if (RegExp(r'x86|ia32|win32').hasMatch(n)) {
        arch = 'x86';
      }
      if (arch != null && arch != runtime.arch) return -1;
      return (n.contains('universal')
              ? 80
              : arch == runtime.arch
              ? 100
              : 60) +
          (n.endsWith('.dmg') || n.endsWith('.exe') ? 5 : 0);
    }

    final compatible = assets.where((a) => score(a) >= 0).toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    return compatible.isEmpty ? null : compatible.first;
  }
}

bool _repositoryUrl(Uri uri, UpdateSource source) =>
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443) &&
    uri.host == source.repository.host &&
    uri.path.startsWith('${source.repository.path}/');

List<AppRelease> parseReleases(Object? json, UpdateSource source) {
  if (json is! List) throw const FormatException('更新源未返回有效的 Release 列表。');
  final releases = <AppRelease>[];
  for (final raw in json) {
    if (raw is! Map ||
        raw['draft'] == true ||
        raw['prerelease'] == true ||
        raw['draft'] == 'true' ||
        raw['prerelease'] == 'true') {
      continue;
    }
    final tag = raw['tag_name'];
    if (tag is! String) continue;
    final version = AppVersion.parse(tag);
    if (version == null) continue;
    final assets = <ReleaseAsset>[];
    final collection = raw['assets'];
    final entries = collection is List
        ? collection
        : collection is Map && collection['links'] is List
        ? collection['links'] as List
        : const [];
    for (final a in entries) {
      final rawUrl = a is Map
          ? a['browser_download_url']
          : a is String
          ? a
          : null;
      if (rawUrl is! String) continue;
      final url = Uri.tryParse(rawUrl);
      if (url == null ||
          !_repositoryUrl(url, source) ||
          url.hasFragment ||
          url.pathSegments.isEmpty) {
        continue;
      }
      final name = a is Map && a['name'] is String
          ? a['name'] as String
          : url.pathSegments.last;
      assets.add(ReleaseAsset(name, url));
    }
    final body = raw['body'];
    releases.add(
      AppRelease(
        source: source,
        tag: tag,
        version: version,
        notes: body is String && body.trim().isNotEmpty
            ? body.trim()
            : '此版本未提供更新日志。',
        page: source.releasePage(tag),
        assets: List.unmodifiable(assets),
      ),
    );
  }
  releases.sort((a, b) => b.version.compareTo(a.version));
  return releases;
}
