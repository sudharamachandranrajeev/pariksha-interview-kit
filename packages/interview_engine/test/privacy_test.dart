// Privacy rules that travel with the engine:
// - no MediaPipe runtime, ML Kit or Firebase anywhere in the dependency tree
//   or imported by lib/ (the BlazeFace model file is published on Google's
//   MediaPipe model page, so its URL and label name MediaPipe; only the
//   model file is used, run by LiteRT);
// - no database: recordings and scores never reach a synced table from here,
//   because the engine imports no database or sync library;
// - recordings stay in the folder the app gives the take store;
// - only text goes to the AI: a brain request holds strings, no audio.
// The example app's lock file is the resolved tree, so it is checked too.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_engine/interview_engine.dart';

final _banned = RegExp(r'mediapipe|ml_?kit|firebase', caseSensitive: false);
final _storage = RegExp(
  r'\b(drift|sqflite|sqlite3?|hive|isar|brahma_core|pocketbase|supabase)\b',
  caseSensitive: false,
);

/// Every import and export URI in lib/.
Iterable<(String, String)> _directives() sync* {
  final uri = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    for (final m in uri.allMatches(f.readAsStringSync())) {
      yield (f.path, m.group(1)!);
    }
  }
}

Iterable<String> _pubspecDeps() =>
    File('pubspec.yaml')
        .readAsLinesSync()
        .map((l) => RegExp(r'^\s{2}([a-z0-9_]+):').firstMatch(l)?.group(1))
        .whereType<String>();

void main() {
  test('pubspec declares no banned or storage dependency', () {
    expect(_pubspecDeps().where(_banned.hasMatch), isEmpty);
    expect(_pubspecDeps().where(_storage.hasMatch), isEmpty);
  });

  test('lib/ never imports a banned library, a database or brahma_core', () {
    final hits = [
      for (final (file, uri) in _directives())
        if (_banned.hasMatch(uri) || _storage.hasMatch(uri)) '$file: $uri',
    ];
    expect(hits, isEmpty);
  });

  test('the resolved tree (example app lock file) has no banned package', () {
    final lock = File('../../example/pubspec.lock');
    if (!lock.existsSync()) {
      markTestSkipped('example/pubspec.lock not found; run flutter pub get in example/');
      return;
    }
    final packages = RegExp(
      r'^  ([a-z0-9_]+):$',
      multiLine: true,
    ).allMatches(lock.readAsStringSync()).map((m) => m.group(1)!);
    expect(packages, contains('sherpa_onnx'), reason: 'sanity: the lock file lists the engine deps');
    expect(packages.where(_banned.hasMatch), isEmpty);
  });

  test('recordings are written only inside the take store\'s own folder', () async {
    final tmp = await Directory.systemTemp.createTemp('engine-takes-');
    final root = Directory('${tmp.path}/takes');
    final store = FileTakeStore(root);
    final key = await store.save(0, 1, Pcm(Float32List(1600)));
    final files = tmp.listSync(recursive: true).whereType<File>().map((f) => f.path).toList();
    expect(files, isNotEmpty);
    expect(files.every((p) => p.startsWith(root.path)), isTrue, reason: '$files');
    await store.remove(key);
    await store.removeAll();
    await tmp.delete(recursive: true);
  });

  test('a brain request is text only: the scoring prompt carries transcripts, never audio', () {
    final r = scoreRequest(
      role: 'Clerk',
      framework: Framework.of('private'),
      criteria: const [Criterion(id: 'c1', text: 'Organising work')],
      answers: const [
        (index: 0, question: 'Q?', criteria: ['c1'], answer: 'I sorted the post.'),
      ],
    );
    expect(r.texts, everyElement(isA<String>()));
    expect(r.texts.join(), isNot(contains('.wav')));
  });
}
