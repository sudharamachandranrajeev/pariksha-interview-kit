/// The lab's camera: `camera` (CameraX on Android) or `camera_desktop`
/// (GStreamer on Linux, Windows), with BlazeFace drawing a box round the
/// face. Each frame is read in memory, measured and dropped. The only
/// exception is an opt-in video take ([FaceCamera.startRecording], J7): the
/// user turns it on per session, the clip goes to the app's own private
/// storage (video_takes.dart), and the frames the face finder reads are
/// still dropped.
library;

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'blazeface.dart';
import 'setup_check.dart';

/// [img] as a [Frame], without copying the pixels.
Frame frameOf(CameraImage img) {
  if (img.format.group == ImageFormatGroup.yuv420 && img.planes.length == 3) {
    return Frame.yuv420(
      img.width,
      img.height,
      [for (final p in img.planes) p.bytes],
      [for (final p in img.planes) p.bytesPerRow],
      [for (final p in img.planes) p.bytesPerPixel ?? 1],
    );
  }
  final p = img.planes.first;
  return Frame.bgra(img.width, img.height, p.bytes, p.bytesPerRow);
}

/// A camera with a face box. [boxes] and [fps] update as frames arrive.
class FaceCamera {
  FaceCamera._(this.controller, this._detector);

  final CameraController controller;
  final BlazeFaceDetector _detector;

  /// The faces in the latest frame looked at.
  final boxes = ValueNotifier<List<FaceBox>>(const []);

  /// The latest frame as numbers only: the face box and how bright the
  /// face and the rest of the picture are (see setup_check.dart).
  final measure = ValueNotifier<FrameMeasure?>(null);

  /// Frames run through the face finder per second, over the last second.
  final fps = ValueNotifier<double>(0);

  /// Average time the face finder took per frame, in milliseconds.
  final detectMs = ValueNotifier<double>(0);

  bool _busy = false, _closed = false;
  int _frames = 0;
  double _msTotal = 0;
  final _window = Stopwatch();

  /// Opens the first front camera (or any camera) and starts looking for
  /// a face with the BlazeFace model at [modelPath].
  static Future<FaceCamera> open(String modelPath) async {
    final cams = await availableCameras();
    if (cams.isEmpty) throw StateError('No camera was found.');
    final cam = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );
    final controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    final fc = FaceCamera._(controller, BlazeFaceDetector.open(modelPath));
    fc._window.start();
    await controller.startImageStream(fc._onFrame);
    return fc;
  }

  void _onFrame(CameraImage img) {
    // One frame at a time; frames that arrive meanwhile are dropped.
    if (_busy || _closed) return;
    _busy = true;
    try {
      final t = Stopwatch()..start();
      final frame = frameOf(img);
      final found = _detector.detect(frame);
      boxes.value = found;
      measure.value = measureFrame(frame, found);
      _msTotal += t.elapsedMicroseconds / 1000;
      _frames++;
      if (_window.elapsedMilliseconds >= 1000) {
        fps.value = _frames * 1000 / _window.elapsedMilliseconds;
        detectMs.value = _msTotal / _frames;
        _frames = 0;
        _msTotal = 0;
        _window.reset();
      }
    } finally {
      _busy = false;
    }
  }

  /// True while frames do not reach the face finder because the camera is
  /// recording and cannot stream at the same time.
  bool cuesPaused = false;

  /// Starts an opt-in video take (J7). The controller was opened with
  /// `enableAudio: false`, so the clip has no sound: the round's own WAV
  /// is the audio. On Linux and Windows camera_desktop records from a
  /// branch of the same pipeline (a GStreamer tee on Linux), so frames keep
  /// coming. On Android the frames are handed over with the recording; a
  /// camera that refuses both at once records alone and the cues pause.
  Future<void> startRecording() async {
    if (_closed) throw StateError('The camera is closed.');
    if (Platform.isAndroid) {
      if (controller.value.isStreamingImages) await controller.stopImageStream();
      try {
        await controller.startVideoRecording(onAvailable: _onFrame);
        cuesPaused = false;
      } on CameraException {
        await controller.startVideoRecording();
        cuesPaused = true;
      }
    } else {
      // The controller marks the stream stopped (no onAvailable), but the
      // desktop stream keeps running beside the recording; the flag is
      // put back once recording stops, so close() still stops the stream.
      await controller.startVideoRecording();
    }
  }

  /// Stops the video take and returns its temporary file; the frames carry
  /// on as before.
  Future<String> stopRecording() async {
    final f = await controller.stopVideoRecording();
    await _resumeStream();
    return f.path;
  }

  Future<void> _resumeStream() async {
    cuesPaused = false;
    if (_closed || controller.value.isStreamingImages) return;
    if (Platform.isAndroid) {
      await controller.startImageStream(_onFrame);
    } else {
      controller.value = controller.value.copyWith(isStreamingImages: true);
    }
  }

  bool get recording => controller.value.isRecordingVideo;

  Future<void> close() async {
    if (_closed) return;
    if (recording) {
      // A take still recording when the camera closes is not kept.
      try {
        final f = await controller.stopVideoRecording();
        await File(f.path).delete();
      } on Object {
        // Gone with the camera.
      }
    }
    _closed = true;
    if (controller.value.isStreamingImages) await controller.stopImageStream();
    await controller.dispose();
    _detector.close();
    boxes.dispose();
    measure.dispose();
    fps.dispose();
    detectMs.dispose();
  }
}
