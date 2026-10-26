// Small image helpers (no external packages needed).
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes [bytes] (png/jpg/webp...) and re-encodes them as a PNG that is at
/// most [size] pixels wide. Account icons are stored inside the database, so
/// keeping them tiny keeps backups small and lists fast.
Future<Uint8List> resizeToIcon(Uint8List bytes, {int size = 160}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: size);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('Could not process the image');
  return data.buffer.asUint8List();
}
