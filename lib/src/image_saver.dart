// 二维码 / asset 图片保存工具。独立于 widgets.dart 与 miuix_widgets.dart，
// 避免两套 UI 实现间相互导入导致的循环依赖。
//
// 把 asset 中的图片落盘到本机 Pictures 目录，供"保存二维码"功能复用。

import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// 把 [assetPath] 指向的 asset 图片保存到本机。
///
/// Android 上写入应用专属外部存储的 Pictures 子目录（无需申请权限，
/// 系统媒体扫描器会扫描到该目录，可在相册或文件管理器中查看）；
/// 其它平台写入应用文档目录的 Pictures 子目录作为回退。
///
/// [fileNamePrefix] 用于生成最终文件名前缀，避免不同来源二维码相互覆盖。
/// 返回最终落盘的文件绝对路径，供调用方在 SnackBar 中提示用户。
Future<String> saveAssetImageToFile(
  String assetPath,
  String fileNamePrefix,
) async {
  final bytes = await rootBundle.load(assetPath);
  final data = Uint8List.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  Directory baseDir;
  if (Platform.isAndroid) {
    baseDir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
  } else {
    baseDir = await getApplicationDocumentsDirectory();
  }
  final picturesDir = Directory('${baseDir.path}/Pictures');
  if (!picturesDir.existsSync()) {
    picturesDir.createSync(recursive: true);
  }
  final ext = assetPath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final file = File('${picturesDir.path}/${fileNamePrefix}_$stamp.$ext');
  await file.writeAsBytes(data, flush: true);
  return file.path;
}
