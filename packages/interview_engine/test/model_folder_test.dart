import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_engine/interview_engine.dart';

import 'interview_lab_test.dart' show fakeModel;

/// Installs [body] as model [m] under [root] the way [ModelManager] leaves
/// it: the main file plus the `.verified` marker.
Future<void> install(Directory root, SpeechModel m, List<int> body, {String? marker}) async {
  final f = File('${root.path}/${m.id}/${m.entry}');
  await f.create(recursive: true);
  await f.writeAsBytes(body);
  await File('${root.path}/${m.id}/.verified').writeAsString(marker ?? m.sha256);
}

void main() {
  group('the shared folder', () {
    test('Linux uses XDG_DATA_HOME, or ~/.local/share without it', () {
      expect(
        sharedModelFolder(environment: {'XDG_DATA_HOME': '/data/u', 'HOME': '/home/u'}, os: 'linux')!.path,
        '/data/u/pariksha/models',
      );
      expect(
        sharedModelFolder(environment: {'HOME': '/home/u'}, os: 'linux')!.path,
        '/home/u/.local/share/pariksha/models',
      );
      // A relative XDG_DATA_HOME is invalid by the spec and ignored.
      expect(
        sharedModelFolder(environment: {'XDG_DATA_HOME': 'rel', 'HOME': '/home/u'}, os: 'linux')!.path,
        '/home/u/.local/share/pariksha/models',
      );
    });

    test('Windows uses %APPDATA%; macOS uses Application Support', () {
      expect(
        sharedModelFolder(environment: {'APPDATA': r'C:\Users\u\AppData\Roaming'}, os: 'windows')!.path,
        r'C:\Users\u\AppData\Roaming\pariksha\models',
      );
      expect(
        sharedModelFolder(environment: {'HOME': '/Users/u'}, os: 'macos')!.path,
        '/Users/u/Library/Application Support/pariksha/models',
      );
    });

    test('phones keep app-private storage: no shared folder', () {
      expect(sharedModelFolder(environment: {'HOME': '/data'}, os: 'android'), isNull);
      expect(sharedModelFolder(environment: {'HOME': '/var/mobile'}, os: 'ios'), isNull);
      expect(sharedModelFolder(environment: const {}, os: 'linux'), isNull);
    });
  });

  group('adopting an app\'s own models', () {
    late Directory tmp, own, shared;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('engine-adopt-');
      own = Directory('${tmp.path}/app/models');
      shared = Directory('${tmp.path}/pariksha/models');
    });
    tearDown(() async => tmp.delete(recursive: true));

    test('verified models move without a download; the shared manager sees them installed', () async {
      final vadBody = List<int>.generate(4000, (i) => i % 7);
      final voiceBody = List<int>.generate(3000, (i) => i % 11);
      final vad = fakeModel(vadBody, id: 'vad');
      // An unpacked archive cannot be hashed again: its marker stands.
      final voice = fakeModel(voiceBody, id: 'voice', archive: true, entry: 'v1/model.onnx');
      await install(own, vad, vadBody);
      await install(own, voice, voiceBody);

      final r = await adoptModels(from: own, to: shared, models: [vad, voice]);
      expect(r.moved, ['vad', 'voice']);
      expect(r.skipped, isEmpty);
      final mm = ModelManager(shared);
      expect(await mm.installed(vad), isTrue);
      expect(await mm.installed(voice), isTrue);
      expect(await File(mm.path(vad)).readAsBytes(), vadBody);
      expect(Directory('${own.path}/vad').existsSync(), isFalse);

      // Running it again finds nothing to do.
      expect((await adoptModels(from: own, to: shared, models: [vad, voice])).nothing, isTrue);
    });

    test('a file that no longer matches its checksum, or a half download, stays put', () async {
      final body = List<int>.generate(2000, (i) => i % 5);
      final bad = fakeModel(body, id: 'bad');
      final half = fakeModel(body, id: 'half');
      await install(own, bad, [...body.take(1999), 99]);
      await File('${own.path}/half/${half.entry}').create(recursive: true);

      final r = await adoptModels(from: own, to: shared, models: [bad, half]);
      expect(r.moved, isEmpty);
      expect(r.skipped, ['bad', 'half']);
      expect(Directory('${own.path}/bad').existsSync(), isTrue);
      expect(await ModelManager(shared).installed(bad), isFalse);
    });

    test('a model the other app already installed wins; the duplicate copy goes', () async {
      final body = List<int>.generate(1000, (i) => i % 3);
      final m = fakeModel(body, id: 'both');
      await install(own, m, body);
      await install(shared, m, body);
      final r = await adoptModels(from: own, to: shared, models: [m]);
      expect(r.duplicates, ['both']);
      expect(Directory('${own.path}/both').existsSync(), isFalse);
      expect(await ModelManager(shared).installed(m), isTrue);
    });

    test('retired model folders move too, so the lab can still offer to delete them', () async {
      final old = File('${own.path}/${retiredModelIds.first}/ggml.bin');
      await old.create(recursive: true);
      await old.writeAsBytes([1, 2, 3]);
      await adoptModels(from: own, to: shared, models: const []);
      expect(await ModelManager(shared).retiredBytes(), 3);
    });

    test('no own folder, or the same folder, does nothing', () async {
      expect((await adoptModels(from: own, to: shared)).nothing, isTrue);
      await own.create(recursive: true);
      expect((await adoptModels(from: own, to: own)).nothing, isTrue);
    });
  });
}
