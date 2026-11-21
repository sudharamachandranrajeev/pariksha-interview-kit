/// A self-check that the engine's native libraries load on this device.
///
/// Used by the example app to prove that sherpa_onnx (speech), LiteRT
/// (on-device vision) and the camera plugin link. It reads version strings
/// and lists cameras; it never opens a camera, records, or downloads.
library;

import 'package:camera/camera.dart' as camera;
import 'package:flutter_litert/flutter_litert.dart' as litert;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// What loaded. A field is null when that library failed; [errors] says why.
class NativeProbe {
  const NativeProbe({this.sherpaOnnx, this.liteRt, this.cameras, this.errors = const []});

  /// sherpa_onnx native version, for example `1.12.x`.
  final String? sherpaOnnx;

  /// LiteRT (TensorFlow Lite) native version.
  final String? liteRt;

  /// How many cameras the platform plugin reports (0 is fine: it still
  /// proves the plugin answered).
  final int? cameras;

  final List<String> errors;

  bool get ok => sherpaOnnx != null && liteRt != null && cameras != null;

  @override
  String toString() =>
      'sherpa_onnx=${sherpaOnnx ?? '-'} litert=${liteRt ?? '-'} cameras=${cameras ?? '-'}'
      '${errors.isEmpty ? '' : ' errors=$errors'}';
}

/// Loads each native library once and reports its version.
Future<NativeProbe> probeNative() async {
  final errors = <String>[];
  String? s;
  String? l;
  int? c;
  try {
    sherpa.initBindings();
    s = sherpa.getVersion();
  } catch (e) {
    errors.add('sherpa_onnx: $e');
  }
  try {
    l = litert.version;
  } catch (e) {
    errors.add('litert: $e');
  }
  try {
    c = (await camera.availableCameras()).length;
  } catch (e) {
    errors.add('camera: $e');
  }
  return NativeProbe(sherpaOnnx: s, liteRt: l, cameras: c, errors: errors);
}
