/// Test doubles for apps that use the interview engine: a voice, a
/// listener, a take store, a sink and a coach that run a spoken round with
/// no audio, and a camera that hands out set-up measures by hand.
///
/// For tests only; nothing here touches a microphone, a camera, a model or
/// the network.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'src/interview/delivery.dart' show SpokenSegment;
import 'src/vision/blazeface.dart';
import 'src/vision/camera_coach.dart';
import 'src/vision/setup_check.dart';
import 'src/voice/lab.dart' show Pcm;
import 'src/voice/models.dart';
import 'src/voice/round.dart';

/// An interviewer voice that records what it was asked to say. Set [hold]
/// to keep [say] from finishing until [stop] is called.
class FakeVoice implements InterviewerVoice {
  final prepared = <String>[];
  final said = <String>[];
  var stops = 0;
  var closed = false;
  Completer<void>? hold;

  @override
  void prepare(String text) => prepared.add(text);

  @override
  Future<void> say(String text) async {
    said.add(text);
    if (hold case final h?) await h.future;
  }

  @override
  Future<void> stop() async {
    stops++;
    hold?.complete();
    hold = null;
  }

  @override
  Future<void> close() async => closed = true;
}

/// One answer being heard; complete [end] to say the speaker stopped.
class FakeCapture implements AnswerCapture {
  FakeCapture(this.answer);
  final CapturedAnswer answer;
  final end = Completer<void>();
  final statuses = StreamController<ListenStatus>.broadcast();
  var cancelled = false;

  @override
  Stream<ListenStatus> get status => statuses.stream;
  @override
  Future<void> get heardEnd => end.future;
  @override
  Future<CapturedAnswer> finish() async => answer;
  @override
  Future<void> cancel() async => cancelled = true;
}

/// A listener that hands out [answers] in turn; the last repeats. Set
/// [fail] to act as a missing microphone.
class FakeListener implements AnswerListener {
  FakeListener(this.answers);
  final List<CapturedAnswer> answers;
  final captures = <FakeCapture>[];
  final endSilences = <Duration?>[];
  var fail = false;

  @override
  Future<AnswerCapture> listen({Duration? endSilence}) async {
    endSilences.add(endSilence);
    if (fail) throw StateError('no microphone');
    final c = FakeCapture(answers[captures.length.clamp(0, answers.length - 1)]);
    captures.add(c);
    return c;
  }

  @override
  Future<void> close() async {}
}

/// Takes kept in memory, never on disk.
class MemoryTakes implements TakeStore {
  final kept = <String, Pcm>{};
  final removed = <String>[];

  @override
  Future<String> save(int question, int take, Pcm audio) async {
    final key = 'q$question-t$take';
    kept[key] = audio;
    return key;
  }

  @override
  Future<void> remove(String key) async {
    removed.add(key);
    kept.remove(key);
  }

  @override
  Future<void> removeAll() async => kept.clear();
}

/// Records each saved transcript as (question, text).
class ListSink implements AnswerSink {
  final saved = <(int, String)>[];
  @override
  Future<void> saveTranscript(int question, String text) async => saved.add((question, text));
}

/// A coach with one fixed strength and fix.
class FakeCoach implements ContentCoach {
  final asked = <String>[];
  @override
  Future<ContentNote> feedback(int question, RoundQuestion q, String answer) async {
    asked.add(answer);
    return const ContentNote('A clear example with a result.', 'Say what you yourself did first.');
  }
}

/// A spoken answer of [text]: silent audio [seconds] long, with one
/// stretch of speech from 1 s to the end.
CapturedAnswer spokenAnswer(String text, {double seconds = 4}) => CapturedAnswer(
  Pcm(Float32List((seconds * 16000).round())),
  [SpokenSegment(Duration(seconds: 1), Duration(milliseconds: (seconds * 1000).round()), text)],
);

/// A frame's numbers: a face box centred at ([cx], [cy]) of height [h]
/// (square-ish, as BlazeFace gives), and brightness of the face and the
/// rest. Fictional fixtures: no real picture.
FrameMeasure frameMeasure({
  double cx = 0.5,
  double cy = 0.42,
  double h = 0.32,
  double face = 140,
  double back = 120,
  bool seen = true,
  int faces = 1,
}) => FrameMeasure(
  face: seen ? FaceBox(cx - h * 0.4, cy - h / 2, h * 0.8, h, 0.95) : null,
  faces: seen ? faces : 0,
  faceLuma: face,
  backLuma: back,
  frameLuma: seen ? (face + back) / 2 : back,
);

/// A camera feed whose measures a test sets through [value].
class FakeFeed implements CoachFeed {
  final value = ValueNotifier<FrameMeasure?>(null);
  var closed = false;
  @override
  ValueListenable<FrameMeasure?> get measures => value;
  @override
  Widget? preview() => null;
  @override
  Future<void> close() async => closed = true;
}

/// A camera with no device behind it. [ready] says whether the face model
/// is there; a download just flips it.
class FakeCamera implements CoachCamera {
  FakeCamera({this.ready = true});
  bool ready;
  final feeds = <FakeFeed>[];
  var downloads = 0;
  @override
  SpeechModel get model => speechModel(faceModelId);
  @override
  Future<bool> modelReady() async => ready;
  @override
  Future<void> downloadModel({void Function(double share)? progress}) async {
    downloads++;
    ready = true;
  }

  @override
  Future<CoachFeed> open() async {
    final f = FakeFeed();
    feeds.add(f);
    return f;
  }
}
