/// Speech and vision models for the interview simulator.
///
/// None of them ship with the app. Each one is downloaded only when the user
/// asks, from the project that publishes it, checked against the SHA-256
/// pinned here, and kept in the shared model folder on a desktop or the
/// app's own data folder on a phone (never synced; see model_folder.dart).
/// The user sees the size before downloading and can delete any of them.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../interview/offline_guard.dart';

/// What a model is for.
enum ModelRole { voice, vad, transcribe, face }

/// One downloadable model, pinned by URL, size and SHA-256.
class SpeechModel {
  const SpeechModel({
    required this.id,
    required this.label,
    required this.role,
    required this.url,
    required this.sha256,
    required this.bytes,
    required this.entry,
    required this.source,
    required this.licence,
    this.archive = false,
    this.drop = const [],
  });

  /// Folder name under the models folder; never changes once released.
  final String id;
  final String label;
  final ModelRole role;

  /// The official release URL.
  final String url;

  /// SHA-256 of the downloaded file (the archive, for an archive).
  final String sha256;

  /// Size of the download in bytes, shown before it starts.
  final int bytes;

  /// The main file, relative to the model's folder, once installed.
  final String entry;

  /// Who publishes it, shown with the licence.
  final String source;
  final String licence;

  /// A .tar.bz2 that is unpacked after the check.
  final bool archive;

  /// Paths in the archive that are not needed and are deleted after
  /// unpacking.
  final List<String> drop;
}

/// The models the interview simulator can use. URLs are the publishers' own
/// release links; hashes are the publishers' (GitHub release digests) or,
/// for MediaPipe, measured on 2026-11-19.
const speechModels = <SpeechModel>[
  SpeechModel(
    id: 'kokoro-en-gb-int8',
    label: 'Interviewer voice (Kokoro, British English)',
    role: ModelRole.voice,
    url:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'kokoro-int8-multi-lang-v1_0.tar.bz2',
    sha256: '72c347230107ef8a31098ec4d468a605244beef5f1ed00db97efa13518800653',
    bytes: 132353410,
    entry: 'kokoro-int8-multi-lang-v1_0/model.int8.onnx',
    source: 'hexgrad/Kokoro-82M via k2-fsa/sherpa-onnx',
    licence: 'Apache-2.0',
    archive: true,
    // Only the English parts are kept: the Chinese dictionaries and rules,
    // the US lexicon and espeak-ng's data (unused since sherpa-onnx 2.0).
    drop: [
      'kokoro-int8-multi-lang-v1_0/espeak-ng-data',
      'kokoro-int8-multi-lang-v1_0/dict',
      'kokoro-int8-multi-lang-v1_0/lexicon-zh.txt',
      'kokoro-int8-multi-lang-v1_0/lexicon-us-en.txt',
      'kokoro-int8-multi-lang-v1_0/date-zh.fst',
      'kokoro-int8-multi-lang-v1_0/number-zh.fst',
      'kokoro-int8-multi-lang-v1_0/phone-zh.fst',
    ],
  ),
  SpeechModel(
    id: 'silero-vad',
    label: 'Speech detector (Silero VAD)',
    role: ModelRole.vad,
    url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
    sha256: '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
    bytes: 643854,
    entry: 'silero_vad.onnx',
    source: 'snakers4/silero-vad via k2-fsa/sherpa-onnx',
    licence: 'MIT',
  ),
  SpeechModel(
    id: 'moonshine-base-en',
    label: 'Transcriber (Moonshine base, English)',
    role: ModelRole.transcribe,
    url:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
        'sherpa-onnx-moonshine-base-en-quantized-2026-02-27.tar.bz2',
    sha256: '43232c1d13013d37317163baec3135bd771a186a4356f28c889bab453bb0e891',
    bytes: 111266225,
    entry: 'sherpa-onnx-moonshine-base-en-quantized-2026-02-27/encoder_model.ort',
    source: 'moonshine-ai/moonshine via k2-fsa/sherpa-onnx',
    // The English Moonshine models are MIT; other languages are not, so
    // only English is offered.
    licence: 'MIT',
    archive: true,
    drop: ['sherpa-onnx-moonshine-base-en-quantized-2026-02-27/test_wavs'],
  ),
  SpeechModel(
    id: 'moonshine-tiny-en',
    label: 'Transcriber, lighter (Moonshine tiny, English)',
    role: ModelRole.transcribe,
    url:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
        'sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27.tar.bz2',
    sha256: '9ec31b342d8fa3240c3b81b8f82e1cf7e3ac467c93ca5a999b741d5887164f8d',
    bytes: 29858559,
    entry: 'sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27/encoder_model.ort',
    source: 'moonshine-ai/moonshine via k2-fsa/sherpa-onnx',
    licence: 'MIT',
    archive: true,
    drop: ['sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27/test_wavs'],
  ),
  SpeechModel(
    id: 'blazeface-short-range',
    label: 'Face finder (MediaPipe BlazeFace, short range)',
    role: ModelRole.face,
    url:
        'https://storage.googleapis.com/mediapipe-models/face_detector/'
        'blaze_face_short_range/float16/1/blaze_face_short_range.tflite',
    sha256: 'b4578f35940bf5a1a655214a1cce5cab13eba73c1297cd78e1a04c2380b0152f',
    bytes: 229746,
    entry: 'blaze_face_short_range.tflite',
    source: 'Google MediaPipe model card (model file only; no MediaPipe runtime)',
    licence: 'Apache-2.0',
  ),
];

SpeechModel speechModel(String id) => speechModels.firstWhere((m) => m.id == id);

/// Folders earlier versions downloaded and no longer use (the I0 spike's
/// whisper.cpp models). The lab offers to delete them.
const retiredModelIds = ['whisper-base-en', 'whisper-small-en'];

/// The default transcriber, voice and speech detector of a spoken round.
const defaultTranscriber = 'moonshine-base-en';
const voiceModelId = 'kokoro-en-gb-int8';
const vadModelId = 'silero-vad';
const faceModelId = 'blazeface-short-range';

/// A download that failed; [message] is for the user.
class ModelException implements Exception {
  ModelException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// "21.1 MB" from a byte count.
String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(0)} kB';
  if (bytes < 1000 * 1000 * 1000) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
  return '${(bytes / 1e9).toStringAsFixed(2)} GB';
}

/// Downloads, checks, lists and deletes [speechModels] under [root].
///
/// Layout: `<root>/<id>/...` holds an installed model, with a `.verified`
/// file holding the SHA-256 it was checked against. A download in progress
/// is `<root>/<id>.<pid>-<random>.part` and is unpacked into a staging
/// folder of the same name ending `.new`, so two downloads never write to
/// the same file; a failed or mismatched one is deleted.
///
/// On a desktop the folder is shared by Udyoga and Vidya (see
/// model_folder.dart), so two apps may want the same model at once. Each
/// model has a lock file under `<root>/.locks/`, held with an operating
/// system file lock (and a lock inside this process for two managers in
/// one app) while it is downloaded, installed or deleted. The second app
/// waits, finds the model installed and checked, and does not download it
/// again. A delete never waits: while another download holds the lock it
/// is refused with a [ModelException].
///
/// The apps that use the folder say so with [registerUser], so a screen can
/// warn that deleting a model deletes it for the other app too
/// ([users], [modelSharingNote]).
class ModelManager {
  ModelManager(this.root, {this.client, this.voiceCache});

  final Directory root;

  /// The interviewer voice's ready-made clips (see voice_cache.dart), made
  /// by the voice model: deleting the voice deletes them too.
  final Directory? voiceCache;

  /// The HTTP client to use; null means a fresh one per download.
  final http.Client? client;

  static const _marker = '.verified';

  Directory _dir(SpeechModel m) => Directory('${root.path}/${m.id}');

  /// The installed model's main file.
  String path(SpeechModel m) => '${_dir(m).path}/${m.entry}';

  /// The folder holding the main file (a sherpa voice needs its tokens and
  /// espeak-ng-data, which sit beside the model).
  String folder(SpeechModel m) => File(path(m)).parent.path;

  /// True once [m] was downloaded and matched its SHA-256.
  Future<bool> installed(SpeechModel m) async {
    final marker = File('${_dir(m).path}/$_marker');
    if (!await marker.exists() || !await File(path(m)).exists()) return false;
    return (await marker.readAsString()).trim() == m.sha256;
  }

  /// Bytes [m] takes on disk (0 when not installed).
  Future<int> sizeOnDisk(SpeechModel m) async {
    final d = _dir(m);
    if (!await d.exists()) return 0;
    var n = 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) n += await e.length();
    }
    return n;
  }

  /// Downloads [m], checks its size and SHA-256, and installs it. A
  /// mismatch deletes the download and throws [ModelException]; nothing is
  /// installed. [onProgress] gets bytes received and the expected total.
  ///
  /// When another app (or another manager in this one) is downloading the
  /// same model into the same folder, this waits for it to finish; if that
  /// left the model installed and checked, nothing is downloaded again.
  Future<void> download(SpeechModel m, {void Function(int received, int total)? onProgress}) async {
    // Offline interview practice: no download, whatever the screen offers.
    if (OfflineGuard.instance.active) throw ModelException(offlineDownloadMessage);
    await root.create(recursive: true);
    final held = (await _ModelLock.acquire(root, m.id, wait: true))!;
    final tag = '$pid-${math.Random.secure().nextInt(1 << 32).toRadixString(16)}';
    final part = File('${root.path}/${m.id}.$tag.part');
    try {
      if (await installed(m)) {
        onProgress?.call(m.bytes, m.bytes);
        return;
      }
      // Holding the lock, so anything else of this model's is left over
      // from a download that crashed.
      await _clearStale(m);
      final c = client ?? http.Client();
      try {
        final res = await c.send(http.Request('GET', Uri.parse(m.url)));
        if (res.statusCode != 200) {
          throw ModelException('${m.label}: the download failed (HTTP ${res.statusCode}).');
        }
        final sink = part.openWrite();
        final digest = _DigestSink();
        final hasher = sha256.startChunkedConversion(digest);
        var received = 0;
        try {
          await for (final chunk in res.stream) {
            received += chunk.length;
            if (received > m.bytes) {
              throw ModelException('${m.label}: the download is bigger than expected, so it was stopped.');
            }
            hasher.add(chunk);
            sink.add(chunk);
            onProgress?.call(received, m.bytes);
          }
        } finally {
          await sink.close();
        }
        hasher.close();
        if (received != m.bytes) {
          throw ModelException('${m.label}: the download is incomplete ($received of ${m.bytes} bytes).');
        }
        if (digest.value.toString() != m.sha256) {
          throw ModelException(
            '${m.label}: the file does not match its published checksum, so it was deleted.',
          );
        }
        await _install(m, part, tag);
      } finally {
        if (client == null) c.close();
      }
    } finally {
      if (await part.exists()) await part.delete();
      await held.release();
    }
  }

  /// Deletes this model's half-finished downloads and staging folders.
  /// Called only while holding the model's lock.
  Future<void> _clearStale(SpeechModel m) async {
    if (!await root.exists()) return;
    await for (final e in root.list(followLinks: false)) {
      final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      if (!name.startsWith('${m.id}.') || !(name.endsWith('.part') || name.endsWith('.new'))) continue;
      await e.delete(recursive: true);
    }
  }

  Future<void> _install(SpeechModel m, File verified, String tag) async {
    final dir = _dir(m);
    final staging = Directory('${root.path}/${m.id}.$tag.new');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      if (m.archive) {
        final from = verified.path, to = staging.path;
        await Isolate.run(() {
          final tar = BZip2Decoder().decodeBytes(File(from).readAsBytesSync());
          extractArchiveToDiskSync(TarDecoder().decodeBytes(tar), to);
        });
      } else {
        await verified.rename('${staging.path}/${m.entry}');
      }
      for (final d in m.drop) {
        final e = FileSystemEntity.typeSync('${staging.path}/$d');
        if (e == FileSystemEntityType.directory) {
          await Directory('${staging.path}/$d').delete(recursive: true);
        }
        if (e == FileSystemEntityType.file) await File('${staging.path}/$d').delete();
      }
      if (!await File('${staging.path}/${m.entry}').exists()) {
        throw ModelException('${m.label}: the download does not hold ${m.entry}.');
      }
      await File('${staging.path}/$_marker').writeAsString(m.sha256);
      if (await dir.exists()) await dir.delete(recursive: true);
      await staging.rename(dir.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  /// Bytes held by [retiredModelIds] folders still on this device.
  Future<int> retiredBytes() async {
    var n = 0;
    for (final id in retiredModelIds) {
      final d = Directory('${root.path}/$id');
      if (!await d.exists()) continue;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) n += await e.length();
      }
    }
    return n;
  }

  /// Deletes every [retiredModelIds] folder.
  Future<void> deleteRetired() async {
    for (final id in retiredModelIds) {
      final d = Directory('${root.path}/$id');
      if (await d.exists()) await d.delete(recursive: true);
    }
  }

  /// Deletes [m] and any half-finished download of it. Deleting a voice
  /// also deletes the clips it made.
  ///
  /// In a shared folder this deletes it for every app that uses the folder
  /// (say so first: [modelSharingNote]). While a download of [m] is running,
  /// here or in another app, nothing is deleted and a [ModelException]
  /// says so.
  Future<void> delete(SpeechModel m) async {
    if (await root.exists()) {
      final held = await _ModelLock.acquire(root, m.id, wait: false);
      if (held == null) throw ModelException(modelBusyMessage(m));
      try {
        if (await _dir(m).exists()) await _dir(m).delete(recursive: true);
        await _clearStale(m);
      } finally {
        await held.release();
      }
    }
    if (m.role == ModelRole.voice) await clearVoiceCache();
  }

  // ---- who shares the folder ----

  Directory get _usersDir => Directory('${root.path}/$usersFolderName');

  /// Records that [app] (a short id such as `udyoga` or `vidya`) uses this
  /// folder. Apps call it when they open their model manager, so the other
  /// app's screens can say the models are shared.
  Future<void> registerUser(String app) async {
    final id = app.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(id)) throw ArgumentError.value(app, 'app', 'a short lowercase id');
    await _usersDir.create(recursive: true);
    await File('${_usersDir.path}/$id').writeAsString('');
  }

  /// The ids of the apps that registered with [registerUser], sorted.
  Future<List<String>> users() async {
    if (!await _usersDir.exists()) return const [];
    return [
      await for (final e in _usersDir.list(followLinks: false))
        if (e is File) e.uri.pathSegments.last,
    ]..sort();
  }

  /// Bytes the voice's ready-made clips take (0 with none).
  Future<int> voiceCacheBytes() async {
    final d = voiceCache;
    if (d == null || !await d.exists()) return 0;
    var n = 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) n += await e.length();
    }
    return n;
  }

  /// Deletes the voice's ready-made clips; they are made again as needed.
  Future<void> clearVoiceCache() async {
    final d = voiceCache;
    if (d != null && await d.exists()) await d.delete(recursive: true);
  }
}

/// The folder under a model folder that holds one lock file per model.
const lockFolderName = '.locks';

/// The folder under a model folder where apps register ([ModelManager.registerUser]).
const usersFolderName = '.users';

/// The apps of the suite that share the desktop model folder, by id.
const modelFolderApps = {'udyoga': 'Udyoga', 'vidya': 'Vidya'};

/// An app's name for [id]: "Udyoga" for `udyoga`; an unknown id with its
/// first letter in capitals.
String appName(String id) =>
    modelFolderApps[id] ?? (id.isEmpty ? id : '${id[0].toUpperCase()}${id.substring(1)}');

/// Said when a delete is refused because the model is being downloaded.
String modelBusyMessage(SpeechModel m) =>
    '${m.label} is being downloaded right now, by this app or another app that shares the model folder. '
    'Try again when the download finishes.';

/// What a models list (and a delete confirmation) says about who else uses
/// the models, for the app [app] (an id from [modelFolderApps]).
///
/// [shared] is true when the models are in the shared desktop folder
/// ([sharedModelFolder] was not null); [users] are the apps registered in it
/// ([ModelManager.users]). In a shared folder, deleting a model deletes it
/// for the other app too, and the note says so by name.
String modelSharingNote({required String app, required bool shared, Iterable<String> users = const []}) {
  final me = appName(app);
  final others = {
    for (final u in users)
      if (u != app) appName(u),
  }.toList()..sort();
  final siblings = [
    for (final e in modelFolderApps.entries)
      if (e.key != app) e.value,
  ];
  if (!shared) {
    return 'These models are $me\'s own copy on this device. ${siblings.isEmpty ? 'Other apps keep' : '${_list(siblings)} keeps'} '
        'its own copy, so deleting one here does not affect ${siblings.isEmpty ? 'them' : _list(siblings)}.';
  }
  if (others.isNotEmpty) {
    return 'These models are shared with ${_list(others)} on this computer: one copy in one folder. Deleting one '
        'here deletes it for ${_list(others)} too.';
  }
  return 'These models are kept in one folder on this computer, shared with ${_list(siblings)} when it is '
      'installed. Deleting one here deletes it for ${_list(siblings)} too.';
}

String _list(List<String> names) => switch (names.length) {
  0 => 'other apps',
  1 => names.single,
  _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
};

/// One model's lock: an operating system lock on `<root>/.locks/<id>.lock`
/// (so another app waits), plus a lock in this process (file locks do not
/// keep out a second manager in the same process). Lock files are never
/// deleted: deleting one while another app waits on it would let two hold
/// it at once.
class _ModelLock {
  _ModelLock._(this._path, this._file, this._mine);

  static final _inProcess = <String, Completer<void>>{};

  final String _path;
  final RandomAccessFile _file;
  final Completer<void> _mine;

  /// Takes the lock, waiting for it when [wait]; without [wait] gives null
  /// when someone else holds it.
  static Future<_ModelLock?> acquire(Directory root, String id, {required bool wait}) async {
    final dir = Directory('${root.path}/$lockFolderName');
    await dir.create(recursive: true);
    final path = File('${dir.path}/$id.lock').absolute.path;
    for (var other = _inProcess[path]; other != null; other = _inProcess[path]) {
      if (!wait) return null;
      await other.future;
    }
    final mine = _inProcess[path] = Completer<void>();
    RandomAccessFile? file;
    try {
      file = await File(path).open(mode: FileMode.append);
      await file.lock(wait ? FileLock.blockingExclusive : FileLock.exclusive);
      return _ModelLock._(path, file, mine);
    } on FileSystemException {
      await file?.close();
      _free(path, mine);
      if (!wait) return null;
      rethrow;
    }
  }

  static void _free(String path, Completer<void> mine) {
    if (identical(_inProcess[path], mine)) _inProcess.remove(path);
    if (!mine.isCompleted) mine.complete();
  }

  Future<void> release() async {
    try {
      await _file.unlock();
    } on FileSystemException {
      // Closing the file below drops the lock anyway.
    }
    await _file.close();
    _free(_path, _mine);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
