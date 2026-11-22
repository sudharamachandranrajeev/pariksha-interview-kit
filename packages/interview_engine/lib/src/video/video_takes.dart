/// Video takes (journey plan J7): opt-in, per session, on this device only.
///
/// The camera records the picture with no sound of its own, while `record`
/// keeps the WAV that Moonshine writes down, so the microphone is opened
/// once. Each clip is kept with a copy of that WAV and the transcript's
/// timestamps, so playback can pair them and a quoted line can seek to the
/// moment it was said.
///
/// Rules (they replace "video frames are never stored" for video takes
/// only, and only under these conditions):
///
/// - off unless the user turns it on for a session ([SpokenRound.video] is
///   null by default);
/// - kept in the folder the app gives [VideoTakeStore], which must be the
///   app's own private storage, excluded from sync and from any backup;
/// - never sent to an AI: a [BrainRequest] carries transcript text only, and
///   nothing here returns a path to anything but the app's own player;
/// - deleted after [VideoTakeStore.defaultKeepDays] days unless the user
///   picks another number ([VideoTakeStore.purge], [VideoRetention]); and
///   [VideoTakeStore.deleteAll] removes every one at once.
///
/// Nothing reads emotion, identity or eye contact from a clip. Delivery cues
/// stay information only.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../interview/delivery.dart' show SpokenSegment;
import '../voice/lab.dart' show Pcm;
import '../voice/native_engines.dart' show wavBytes;
import '../voice/round.dart' show CapturedAnswer;

/// Records the camera picture (no audio track) for one answer.
abstract class VideoRecorder {
  /// True where the camera cannot hand out frames while it records (some
  /// Android cameras), so the setup cues pause until recording stops.
  bool get pausesCues;

  /// Starts recording.
  Future<void> start();

  /// Stops recording and returns the finished file (in a temporary folder;
  /// [VideoTakeStore.save] moves it into the app's own storage).
  Future<String> stop();

  /// Stops recording and deletes the file.
  Future<void> cancel();
}

/// One recorded clip: one answer, or one follow-up answer, of one take.
class VideoTake {
  const VideoTake({
    required this.id,
    required this.roundId,
    required this.question,
    required this.take,
    required this.part,
    required this.recordedAt,
    required this.videoPath,
    required this.audioPath,
    required this.audioLead,
    required this.segments,
  });

  /// The file name without its extension; unique in the store.
  final String id;
  final String roundId;

  /// The question's index in the round (0-based) and the take number.
  final int question, take;

  /// 0 for the answer itself, then 1, 2… for its follow-ups in order.
  final int part;

  /// When recording stopped, in UTC.
  final DateTime recordedAt;

  /// The picture (no sound) and the paired WAV, both inside the store.
  final String videoPath;
  final String? audioPath;

  /// How long after the audio the picture started: audio position =
  /// video position + [audioLead].
  final Duration audioLead;

  /// What was said, with times from the start of the audio.
  final List<SpokenSegment> segments;

  String get transcript => segments.map((s) => s.text.trim()).where((t) => t.isNotEmpty).join(' ');

  /// Where in the video the audio's moment [audio] is (never negative).
  Duration videoAt(Duration audio) {
    final v = audio - audioLead;
    return v.isNegative ? Duration.zero : v;
  }

  /// Where in the audio the video's moment [video] is (never negative).
  Duration audioAt(Duration video) {
    final a = video + audioLead;
    return a.isNegative ? Duration.zero : a;
  }

  Map<String, Object?> _toJson() => {
    'v': 1,
    'round': roundId,
    'question': question,
    'take': take,
    'part': part,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    // File names only: a sidecar never holds a full path.
    'video': _name(videoPath),
    'audio': audioPath == null ? null : _name(audioPath!),
    'audioLeadMs': audioLead.inMilliseconds,
    'segments': [
      for (final s in segments) [s.start.inMilliseconds, s.end.inMilliseconds, s.text],
    ],
  };

  static VideoTake? _fromJson(String id, Directory dir, Map<String, Object?> j) {
    final video = j['video'], recorded = DateTime.tryParse('${j['recordedAt']}');
    if (video is! String || recorded == null || j['v'] != 1) return null;
    final audio = j['audio'];
    return VideoTake(
      id: id,
      roundId: '${j['round']}',
      question: (j['question'] as num?)?.toInt() ?? 0,
      take: (j['take'] as num?)?.toInt() ?? 1,
      part: (j['part'] as num?)?.toInt() ?? 0,
      recordedAt: recorded.toUtc(),
      videoPath: '${dir.path}/${_name(video)}',
      audioPath: audio is String ? '${dir.path}/${_name(audio)}' : null,
      audioLead: Duration(milliseconds: (j['audioLeadMs'] as num?)?.toInt() ?? 0),
      segments: [
        for (final s in (j['segments'] as List?) ?? const [])
          if (s is List && s.length == 3)
            SpokenSegment(
              Duration(milliseconds: (s[0] as num).toInt()),
              Duration(milliseconds: (s[1] as num).toInt()),
              '${s[2]}',
            ),
      ],
    );
  }
}

String _name(String path) => path.split(RegExp(r'[/\\]')).last;

/// Video takes as files under [root], one folder per round. [root] must be
/// in the app's own private storage, excluded from sync and backup.
class VideoTakeStore {
  VideoTakeStore(this.root, {DateTime Function()? clock, @visibleForTesting this.rename = _rename})
    : _clock = clock ?? DateTime.now;

  final Directory root;
  final DateTime Function() _clock;

  /// Renames [from] to [to]; throws [FileSystemException] across disks.
  /// Tests swap it to force the copy path or a failure.
  final Future<void> Function(File from, String to) rename;

  static Future<void> _rename(File from, String to) => from.rename(to);

  /// Ids being saved now: [sweep] leaves their files alone.
  final _saving = <String>{};

  /// File names the camera plugins give a recording in their temporary
  /// folder: camera_desktop on Linux (`camera_desktop_<cam>_<n>.mp4|mkv`)
  /// and Windows (`camera_desktop_video_<ms>.mp4`), CameraX on Android
  /// (`REC<digits>.mp4` in the app's cache).
  static final recorderTempName = RegExp(
    r'^(camera_desktop_\d+_\d+\.(mp4|mkv|webm)|camera_desktop_video_\d+\.mp4|REC\d+\.mp4)$',
  );

  /// Days a video take is kept unless the user picks another number.
  static const defaultKeepDays = 14;

  /// The range offered in settings.
  static const minKeepDays = 1, maxKeepDays = 90;

  static final _safe = RegExp(r'[^A-Za-z0-9_-]');

  Directory _roundDir(String roundId) => Directory('${root.path}/${roundId.replaceAll(_safe, '_')}');

  /// Moves [recorded] (the recorder's temporary file) into the store with a
  /// copy of [audio] and the [segments]' timestamps. The temporary file is
  /// gone afterwards whatever happens.
  ///
  /// Every file appears under its final name in one rename: across disks the
  /// clip is copied to a hidden `.part` file in the round's folder first. The
  /// sidecar is renamed last, so a take is listed only once it is whole. A
  /// failure removes everything this save wrote; a crash leaves only `.part`
  /// files or a clip without a sidecar, which [sweep] removes on the next
  /// start.
  Future<VideoTake> save({
    required String roundId,
    required int question,
    required int take,
    int part = 0,
    required String recorded,
    Pcm? audio,
    required List<SpokenSegment> segments,
    Duration audioLead = Duration.zero,
  }) async {
    final src = File(recorded);
    final dir = _roundDir(roundId);
    final now = _clock().toUtc();
    final id = 'q${question + 1}-t$take-p$part-${now.microsecondsSinceEpoch}';
    _saving.add(id);
    try {
      await dir.create(recursive: true);
      final ext = _name(recorded).contains('.') ? _name(recorded).split('.').last.toLowerCase() : 'mp4';
      final video = File('${dir.path}/$id.${ext.replaceAll(_safe, '')}');
      await _move(src, video);
      String? audioPath;
      if (audio != null) {
        final wav = File('${dir.path}/$id.wav');
        await _writeAtomic(wav, wavBytes(audio));
        audioPath = wav.path;
      }
      final t = VideoTake(
        id: id,
        roundId: roundId,
        question: question,
        take: take,
        part: part,
        recordedAt: now,
        videoPath: video.path,
        audioPath: audioPath,
        audioLead: audioLead,
        segments: List.unmodifiable(segments),
      );
      await _writeAtomic(File('${dir.path}/$id.json'), utf8.encode(jsonEncode(t._toJson())));
      return t;
    } on Object {
      await _discard(dir, id);
      rethrow;
    } finally {
      _saving.remove(id);
      try {
        if (await src.exists()) await src.delete();
      } on FileSystemException {
        // Already gone, or the next start's sweep takes it.
      }
    }
  }

  static String _part(File f) => '${f.parent.path}/.${_name(f.path)}.part';

  /// Rename when on the same disk; otherwise copy to a `.part` file beside
  /// [to] (the recorder's temporary folder is often another file system),
  /// then rename that into place and delete [from].
  Future<void> _move(File from, File to) async {
    try {
      await rename(from, to.path);
      return;
    } on FileSystemException {
      // Another disk: copy, then rename on this one.
    }
    final part = File(_part(to));
    try {
      await from.copy(part.path);
      await rename(part, to.path);
    } on Object {
      if (await part.exists()) await part.delete();
      rethrow;
    }
    await from.delete();
  }

  /// Writes [bytes] to a `.part` file, then renames it to [to].
  Future<void> _writeAtomic(File to, List<int> bytes) async {
    final part = File(_part(to));
    try {
      await part.writeAsBytes(bytes, flush: true);
      await rename(part, to.path);
    } on Object {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  /// Deletes every file of [id] in [dir], whole or `.part`.
  Future<void> _discard(Directory dir, String id) async {
    try {
      if (!await dir.exists()) return;
      await for (final f in dir.list()) {
        final n = _name(f.path);
        if (f is File && (n.startsWith('$id.') || n.startsWith('.$id.'))) await f.delete();
      }
      await _dropIfEmpty(dir);
    } on FileSystemException {
      // The next start's sweep tries again.
    }
  }

  /// Cleans up after a crash or a failed save; the app runs it when it
  /// starts ([VideoRetention.start]). Removes, at once, half-written `.part`
  /// files and clips without a sidecar in the store (except saves running
  /// now), and recorder files matching [recorderTempName] in
  /// [recorderTemps] that have not changed for [staleAfter] (a recording
  /// in progress, even another app's, keeps writing). Returns how many files
  /// went.
  Future<int> sweep({
    Iterable<Directory> recorderTemps = const [],
    Duration staleAfter = const Duration(minutes: 10),
  }) async {
    var gone = 0;
    Future<void> drop(File f) async {
      try {
        await f.delete();
        gone++;
      } on FileSystemException {
        // In use or already gone: tried again next start.
      }
    }

    if (await root.exists()) {
      await for (final d in root.list()) {
        if (d is! Directory) continue;
        final files = [
          await for (final f in d.list())
            if (f is File) f,
        ];
        final whole = {
          for (final f in files)
            if (_name(f.path).endsWith('.json') && !_name(f.path).startsWith('.'))
              _name(f.path).replaceFirst(RegExp(r'\.json$'), ''),
        };
        for (final f in files) {
          final n = _name(f.path);
          final id = (n.startsWith('.') ? n.substring(1) : n).split('.').first;
          if (_saving.contains(id)) continue;
          if (n.endsWith('.part') || !whole.contains(id)) await drop(f);
        }
        await _dropIfEmpty(d);
      }
    }
    final cutoff = _clock().subtract(staleAfter);
    for (final dir in recorderTemps) {
      if (!await dir.exists()) continue;
      await for (final f in dir.list()) {
        if (f is File &&
            recorderTempName.hasMatch(_name(f.path)) &&
            (await f.lastModified()).isBefore(cutoff)) {
          await drop(f);
        }
      }
    }
    return gone;
  }

  /// Every kept take (of [roundId] when given), oldest first.
  Future<List<VideoTake>> list({String? roundId}) async {
    if (!await root.exists()) return const [];
    final dirs = roundId != null
        ? [_roundDir(roundId)]
        : [
            await for (final e in root.list())
              if (e is Directory) e,
          ];
    final out = <VideoTake>[];
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await for (final f in dir.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        final id = _name(f.path).replaceFirst(RegExp(r'\.json$'), '');
        try {
          final j = jsonDecode(await f.readAsString());
          final t = j is Map ? VideoTake._fromJson(id, dir, j.cast<String, Object?>()) : null;
          if (t != null && await File(t.videoPath).exists()) out.add(t);
        } on FormatException {
          // A half-written sidecar: left for purge.
        }
      }
    }
    out.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return out;
  }

  /// Deletes one take: its video, its audio and its sidecar.
  Future<void> remove(VideoTake t) async {
    final dir = Directory(File(t.videoPath).parent.path);
    if (!_inside(dir)) return;
    await for (final f in dir.list()) {
      if (f is File && _name(f.path).startsWith('${t.id}.')) await f.delete();
    }
    await _dropIfEmpty(dir);
  }

  /// Deletes every clip of take [take] of question [question] in [roundId].
  Future<void> removeTake(String roundId, int question, int take) async {
    for (final t in await list(roundId: roundId)) {
      if (t.question == question && t.take == take) await remove(t);
    }
  }

  /// Deletes every take of [roundId].
  Future<void> removeRound(String roundId) async {
    final dir = _roundDir(roundId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Deletes every take older than [keepDays] days (and any stray file
  /// older than that, such as an interrupted save). Returns how many takes
  /// went.
  Future<int> purge({int keepDays = defaultKeepDays}) async {
    if (!await root.exists()) return 0;
    final cutoff = _clock().toUtc().subtract(Duration(days: keepDays.clamp(minKeepDays, maxKeepDays)));
    var gone = 0;
    final known = <String>{};
    for (final t in await list()) {
      known.addAll([t.videoPath, ?t.audioPath, '${File(t.videoPath).parent.path}/${t.id}.json']);
      if (t.recordedAt.isBefore(cutoff)) {
        await remove(t);
        gone++;
      }
    }
    await for (final e in root.list(recursive: true)) {
      if (e is File && !known.contains(e.path) && (await e.lastModified()).toUtc().isBefore(cutoff)) {
        await e.delete();
      }
    }
    await for (final e in root.list()) {
      if (e is Directory) await _dropIfEmpty(e);
    }
    return gone;
  }

  /// Deletes every video take on this device.
  Future<void> deleteAll() async {
    if (await root.exists()) await root.delete(recursive: true);
  }

  /// Bytes used by video takes (video, audio and sidecars).
  Future<int> bytesUsed() async {
    if (!await root.exists()) return 0;
    var n = 0;
    await for (final e in root.list(recursive: true)) {
      if (e is File) n += await e.length();
    }
    return n;
  }

  bool _inside(Directory d) => d.parent.path == root.path;

  Future<void> _dropIfEmpty(Directory d) async {
    if (_inside(d) && await d.exists() && await d.list().isEmpty) await d.delete();
  }
}

/// Runs [VideoTakeStore.purge] now and then every [every] (a day), with
/// the user's number of days from [keepDays].
class VideoRetention {
  VideoRetention(
    this.store,
    this.keepDays, {
    this.every = const Duration(days: 1),
    this.recorderTemps = const [],
  });

  final VideoTakeStore store;
  final FutureOr<int> Function() keepDays;
  final Duration every;

  /// The camera recorder's temporary folders, swept on [start]
  /// ([VideoTakeStore.sweep]).
  final List<Directory> recorderTemps;
  Timer? _timer;

  /// Sweeps what a crash left, purges now and starts the daily purge.
  /// Returns how many takes went now.
  Future<int> start() async {
    _timer?.cancel();
    try {
      await store.sweep(recorderTemps: recorderTemps);
    } on Object {
      // Tried again next start; purge still runs.
    }
    _timer = Timer.periodic(every, (_) => unawaited(runOnce().catchError((_) => 0)));
    return runOnce();
  }

  Future<int> runOnce() async => store.purge(keepDays: await keepDays());

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Where a quoted line was said: the clip and the moment in its video.
class VideoSeek {
  const VideoSeek(this.take, this.video, this.audio);
  final VideoTake take;

  /// The moment in the video, and the same moment in the paired audio.
  final Duration video, audio;
}

List<String> _words(String s) =>
    RegExp(r"[a-z0-9]+(?:'[a-z0-9]+)?").allMatches(s.toLowerCase()).map((m) => m.group(0)!).toList();

/// Finds where [quote] was said in [takes] (newest take first, then its
/// parts in order) and the moment to seek to, [leadIn] before the line
/// starts. Within a stretch of speech the moment is placed by the share of
/// words before the quote. Null when no clip holds the quote (a typed
/// answer, or a take with no video).
VideoSeek? seekToQuote(
  Iterable<VideoTake> takes,
  String quote, {
  Duration leadIn = const Duration(milliseconds: 500),
}) {
  final q = _words(quote);
  if (q.isEmpty) return null;
  final ordered = [...takes]
    ..sort((a, b) => a.take != b.take ? b.take.compareTo(a.take) : a.part.compareTo(b.part));
  // A full match first; else the quote's first six words (a quote may run
  // over into words the transcriber split differently).
  for (final need in {q.length, if (q.length > 6) 6}) {
    final want = q.take(need).toList();
    for (final t in ordered) {
      final words = <(int seg, int word, int count, String w)>[];
      for (final (i, s) in t.segments.indexed) {
        final ws = _words(s.text);
        for (final (k, w) in ws.indexed) {
          words.add((i, k, ws.length, w));
        }
      }
      for (var start = 0; start + want.length <= words.length; start++) {
        var ok = true;
        for (var k = 0; k < want.length && ok; k++) {
          ok = words[start + k].$4 == want[k];
        }
        if (!ok) continue;
        final (seg, word, count, _) = words[start];
        final s = t.segments[seg];
        final at = s.start + s.length * (word / count) - leadIn;
        final audio = at.isNegative ? Duration.zero : at;
        return VideoSeek(t, t.videoAt(audio), audio);
      }
    }
  }
  return null;
}

/// A round's opt-in video: the camera records while the microphone is open
/// and each kept answer's clip goes to [store] with its audio and
/// timestamps. Every failure is caught and shown in [error]; the round
/// itself never fails because of video.
class RoundVideo extends ChangeNotifier implements VideoTakes {
  RoundVideo({required this.roundId, required this.recorder, required this.store, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String roundId;
  final VideoRecorder recorder;
  final VideoTakeStore store;
  final DateTime Function() _clock;

  DateTime? _audioStart;
  Duration _lead = Duration.zero;
  bool _recording = false, _disposed = false;
  String? _error;

  /// True while the camera is recording: the screen shows the indicator.
  @override
  bool get recording => _recording;

  /// The latest video failure, if any (the answer itself is kept).
  String? get error => _error;

  /// Clips saved this session.
  final saved = <VideoTake>[];

  void _set(bool on, [String? error]) {
    _recording = on;
    if (error != null) _error = error;
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> answerStarted() async {
    if (_recording) await answerDropped();
    _audioStart = _clock();
    try {
      await recorder.start();
      _lead = _clock().difference(_audioStart!);
      _set(true);
    } on Object catch (e) {
      _set(false, 'The camera did not start recording: $e');
    }
  }

  @override
  Future<VideoTake?> answerKept({
    required int question,
    required int take,
    required int part,
    required CapturedAnswer answer,
  }) async {
    if (!_recording) return null;
    try {
      final file = await recorder.stop();
      _set(false);
      final t = await store.save(
        roundId: roundId,
        question: question,
        take: take,
        part: part,
        recorded: file,
        audio: answer.audio,
        segments: answer.segments,
        audioLead: _lead,
      );
      saved.add(t);
      return t;
    } on Object catch (e) {
      _set(false, 'The video of this answer was not kept: $e');
      return null;
    }
  }

  @override
  Future<void> answerDropped() async {
    if (!_recording) return;
    try {
      await recorder.cancel();
    } on Object {
      // Nothing was kept either way.
    }
    _set(false);
  }

  @override
  Future<void> takeReplaced(int question, int take) async {
    saved.removeWhere((t) => t.question == question && t.take == take);
    try {
      await store.removeTake(roundId, question, take);
    } on Object catch (e) {
      _error = 'An older video was not deleted: $e';
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(answerDropped());
    super.dispose();
  }
}

/// What a [SpokenRound] tells its opt-in video. The round calls these only
/// when the user turned video on for the session.
abstract class VideoTakes {
  bool get recording;

  /// The microphone has just opened for an answer.
  Future<void> answerStarted();

  /// The answer was kept: keep its clip, paired with the audio and the
  /// transcript's timestamps.
  Future<VideoTake?> answerKept({
    required int question,
    required int take,
    required int part,
    required CapturedAnswer answer,
  });

  /// The answer was thrown away (typed instead, skipped, nothing heard).
  Future<void> answerDropped();

  /// A newer take replaced take [take] of [question]: its clips go too.
  Future<void> takeReplaced(int question, int take);
}
