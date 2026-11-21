// Privacy rules that travel with the engine:
// - no MediaPipe, ML Kit or Firebase anywhere in the dependency tree;
// - nothing in lib/ names them either.
// The example app's lock file is the resolved tree, so it is checked too.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _banned = RegExp(r'mediapipe|ml_?kit|firebase', caseSensitive: false);

void main() {
  test('pubspec declares no banned dependency', () {
    final names = File('pubspec.yaml')
        .readAsLinesSync()
        .map((l) => RegExp(r'^\s{2}([a-z0-9_]+):').firstMatch(l)?.group(1))
        .whereType<String>();
    expect(names.where(_banned.hasMatch), isEmpty);
  });

  test('lib/ never imports a banned library', () {
    final hits = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && _banned.hasMatch(f.readAsStringSync())) f.path,
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
}
