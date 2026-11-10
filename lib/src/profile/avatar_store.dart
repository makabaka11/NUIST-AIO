import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Only the normalized PNG is kept in the app's private support directory.
/// The source photo, path, EXIF and original file name are never persisted.
class AvatarStore {
  AvatarStore({Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() directory;
  Future<File> _file() async =>
      File('${(await directory()).path}/profile/avatar.png');
  Future<Uint8List?> read() async {
    final f = await _file();
    return await f.exists() ? f.readAsBytes() : null;
  }

  Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }

  Future<void> save(Uint8List bytes) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  static Future<Uint8List> normalize(XFile file) async {
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('图片超过 20 MB，请选择较小的图片。');
    }
    final bytes = await file.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? source, output;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width > 20000 || descriptor.height > 20000) {
        throw const FormatException('图片尺寸过大，请选择较小的图片。');
      }
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = longest > 1024 ? 1024 / longest : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, 1024),
        targetHeight: (descriptor.height * scale).round().clamp(1, 1024),
      );
      source = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
      final side = (source.width < source.height ? source.width : source.height)
          .toDouble();
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          (source.width - side) / 2,
          (source.height - side) / 2,
          side,
          side,
        ),
        const ui.Rect.fromLTWH(0, 0, 512, 512),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        output = await picture.toImage(512, 512);
      } finally {
        picture.dispose();
      }
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const FormatException('无法读取这张图片。');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      source?.dispose();
      output?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
