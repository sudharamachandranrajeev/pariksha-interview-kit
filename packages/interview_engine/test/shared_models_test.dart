// Two apps (Udyoga and Vidya) share one model folder on a desktop. These
// tests check that they can download the same model at the same time
// without clashing, that a delete never pulls a model out from under a
// running download, and that screens can say who else uses the folder.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:interview_engine/interview_engine.dart';

import 'interview_lab_test.dart' show fakeModel, visible;

/// Serves [body] in [chunks] pieces, waiting for [gate] (when given) before
/// the last piece, and counts the requests in [asked].
MockClient slowServer(List<int> body, {List<Uri>? asked, Completer<void>? gate, int chunks = 5}) =>
    MockClient.streaming((req, _) async {
      asked?.add(req.url);
      final size = (body.length / chunks).ceil();
      Stream<List<int>> parts() async* {
        for (var i = 0; i < body.length; i += size) {
          final end = i + size > body.length ? body.length : i + size;
          if (end == body.length && gate != null) await gate.future;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          yield body.sublist(i, end);
        }
      }

      return http.StreamedResponse(parts(), 200, contentLength: body.length);
    });

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('shared-models-'));
  tearDown(() async => root.delete(recursive: true));

  group('two apps downloading into one folder', () {
    test('the same model at once: one download, both apps end with the checked model', () async {
      final body = List<int>.generate(20000, (i) => i % 241);
      final m = fakeModel(body);
      final asked = <Uri>[];
      final udyoga = ModelManager(root, client: slowServer(body, asked: asked));
      final vidya = ModelManager(root, client: slowServer(body, asked: asked));
      final progress = <int>[];
      await Future.wait([udyoga.download(m), vidya.download(m, onProgress: (got, _) => progress.add(got))]);
      expect(asked, hasLength(1), reason: 'the second app waits, then finds the model installed');
      expect(progress.last, body.length);
      expect(await udyoga.installed(m), isTrue);
      expect(await vidya.installed(m), isTrue);
      expect(await File(vidya.path(m)).readAsBytes(), body);
      expect(visible(root), ['example-model'], reason: 'no .part or .new file is left behind');
    });

    test('different models download side by side', () async {
      final a = List<int>.filled(4000, 3), b = List<int>.filled(3000, 4);
      final ma = fakeModel(a, id: 'model-a'), mb = fakeModel(b, id: 'model-b');
      await Future.wait([
        ModelManager(root, client: slowServer(a)).download(ma),
        ModelManager(root, client: slowServer(b)).download(mb),
      ]);
      final mm = ModelManager(root);
      expect(await mm.installed(ma), isTrue);
      expect(await mm.installed(mb), isTrue);
      expect(visible(root), unorderedEquals(['model-a', 'model-b']));
    });

    test('a download left half done by a crash is cleaned up by the next one', () async {
      final body = List<int>.filled(1000, 9);
      final m = fakeModel(body);
      await File('${root.path}/example-model.4242-dead.part').writeAsBytes([1, 2, 3]);
      await File('${root.path}/example-model.part').writeAsBytes([1, 2, 3]); // older layout
      await Directory('${root.path}/example-model.4242-dead.new').create();
      await File('${root.path}/example-model-other.part').writeAsBytes([1]); // another model's
      await ModelManager(root, client: slowServer(body)).download(m);
      expect(visible(root), unorderedEquals(['example-model', 'example-model-other.part']));
    });

    test('a delete during a download is refused, and the download still finishes', () async {
      final body = List<int>.generate(5000, (i) => i % 7);
      final m = fakeModel(body);
      final gate = Completer<void>();
      final downloading = ModelManager(root, client: slowServer(body, gate: gate)).download(m);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await expectLater(
        ModelManager(root).delete(m),
        throwsA(isA<ModelException>().having((e) => e.message, 'message', contains('being downloaded'))),
      );
      gate.complete();
      await downloading;
      expect(await ModelManager(root).installed(m), isTrue);
      // Once it is done, the delete goes through.
      await ModelManager(root).delete(m);
      expect(await ModelManager(root).installed(m), isFalse);
    });

    test('a download in another process makes this one wait, then use its result', () async {
      // The other app is a separate process holding the model's OS file lock.
      final ProcessResult version;
      try {
        version = await Process.run('dart', ['--version']);
      } on ProcessException {
        markTestSkipped('No dart executable on PATH for the second process.');
        return;
      }
      if (version.exitCode != 0) {
        markTestSkipped('No working dart executable for the second process.');
        return;
      }
      final scripts = await Directory.systemTemp.createTemp('lock-holder-');
      addTearDown(() => scripts.delete(recursive: true));
      final script = File('${scripts.path}/hold.dart');
      await script.writeAsString('''
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final f = await File(args.first).open(mode: FileMode.append);
  await f.lock(FileLock.blockingExclusive);
  stdout.writeln('locked');
  await stdin.transform(utf8.decoder).first;
  await f.unlock();
  await f.close();
}
''');
      final body = List<int>.filled(2000, 5);
      final m = fakeModel(body);
      await Directory('${root.path}/.locks').create(recursive: true);
      final holder = await Process.start('dart', [script.path, '${root.path}/.locks/${m.id}.lock']);
      addTearDown(holder.kill);
      final out = holder.stdout.transform(const SystemEncoding().decoder).asBroadcastStream();
      await out.firstWhere((l) => l.contains('locked')).timeout(const Duration(seconds: 60));

      // While the other process holds the lock: deletes are refused and a
      // download waits.
      await expectLater(ModelManager(root).delete(m), throwsA(isA<ModelException>()));
      final asked = <Uri>[];
      var done = false;
      final downloading = ModelManager(
        root,
        client: slowServer(body, asked: asked),
      ).download(m).then((_) => done = true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(done, isFalse, reason: 'waits for the other app');
      expect(asked, isEmpty);

      holder.stdin.writeln('release');
      await holder.stdin.flush();
      expect(await holder.exitCode.timeout(const Duration(seconds: 30)), 0);
      await downloading.timeout(const Duration(seconds: 30));
      expect(done, isTrue);
      expect(await ModelManager(root).installed(m), isTrue);
    });
  });

  group('who shares the folder', () {
    test('apps register by id; the list is sorted and survives a new manager', () async {
      final mm = ModelManager(root);
      expect(await mm.users(), isEmpty);
      await mm.registerUser('vidya');
      await ModelManager(root).registerUser('udyoga');
      await mm.registerUser('vidya'); // again: still once
      expect(await ModelManager(root).users(), ['udyoga', 'vidya']);
      expect(() => mm.registerUser('Not an id!'), throwsArgumentError);
      expect(visible(root), isEmpty, reason: 'registrations sit in a dot folder');
    });

    test('the note names the other app and says a delete removes it there too', () {
      final both = modelSharingNote(app: 'vidya', shared: true, users: ['udyoga', 'vidya']);
      expect(both, contains('shared with Udyoga'));
      expect(both, contains('deletes it for Udyoga too'));
      final fromUdyoga = modelSharingNote(app: 'udyoga', shared: true, users: ['udyoga', 'vidya']);
      expect(fromUdyoga, contains('shared with Vidya'));
      expect(fromUdyoga, contains('deletes it for Vidya too'));
      // Not registered yet: the folder is still the shared one, and says so.
      final alone = modelSharingNote(app: 'vidya', shared: true, users: ['vidya']);
      expect(alone, contains('shared with Udyoga'));
      expect(alone, contains('deletes it for Udyoga too'));
      // On a phone each app has its own copy.
      final phone = modelSharingNote(app: 'vidya', shared: false);
      expect(phone, contains("Vidya's own copy"));
      expect(phone, contains('Udyoga keeps its own copy'));
      expect(appName('udyoga'), 'Udyoga');
      expect(appName('chanda'), 'Chanda');
    });
  });
}
