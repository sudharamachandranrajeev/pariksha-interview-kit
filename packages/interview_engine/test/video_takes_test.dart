// Video takes (J7): the store, retention and delete-all, the opt-in round
// hook, seeking from a quoted line, and the privacy rules (a video path
// never reaches a brain request or the synced answer text). The camera
// itself is a fake: real recording is checked on a device with
// tool/video_take_check.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_engine/interview_engine.dart';
import 'package:interview_engine/testing.dart';

Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

/// A fictional answer in three stretches of speech.
final segments = [
  SpokenSegment(s(1), s(5), 'I ran the weekend rota for a small team.'),
  SpokenSegment(s(6), s(14), 'Two people were off, so I rang the bank staff and moved the training day.'),
  SpokenSegment(s(15), s(19), 'Every shift was covered.'),
];

CapturedAnswer answerOf(List<SpokenSegment> segs, {double seconds = 20}) =>
    CapturedAnswer(Pcm(Float32List((seconds * 16000).round())), segs);

Future<String> tempVideo(Directory dir, [String name = 'camera_tmp.mp4']) async {
  await dir.create(recursive: true);
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(List.filled(2048, 1), flush: true);
  return f.path;
}

void main() {
  late Directory tmp;
  late Directory root;
  var now = DateTime.utc(2026, 11, 22, 9);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('engine-video-');
    root = Directory('${tmp.path}/video-takes');
    now = DateTime.utc(2026, 11, 22, 9);
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  VideoTakeStore store() => VideoTakeStore(root, clock: () => now);

  group('store', () {
    test(
      'save moves the camera file in, pairs the audio and the timestamps, and keeps only file names',
      () async {
        final cam = await tempVideo(Directory('${tmp.path}/camera'));
        final t = await store().save(
          roundId: 'round-1',
          question: 0,
          take: 1,
          recorded: cam,
          audio: Pcm(Float32List(16000)),
          segments: segments,
          audioLead: s(0.25),
        );
        expect(File(cam).existsSync(), isFalse, reason: 'the temporary file is moved, not copied');
        expect(t.videoPath, startsWith(root.path));
        expect(t.videoPath, endsWith('.mp4'));
        expect(File(t.audioPath!).readAsBytesSync().sublist(0, 4), ascii.encode('RIFF'));
        expect(t.transcript, contains('bank staff'));
        final sidecar = File('${root.path}/round-1/${t.id}.json').readAsStringSync();
        expect(sidecar, isNot(contains(tmp.path)), reason: 'a sidecar holds file names, never full paths');

        final listed = await store().list(roundId: 'round-1');
        expect(listed.single.id, t.id);
        expect(listed.single.segments.map((x) => x.text), segments.map((x) => x.text));
        expect(listed.single.audioLead, s(0.25));
        expect(listed.single.recordedAt, now);
      },
    );

    test('a round id cannot climb out of the folder', () async {
      final t = await store().save(
        roundId: '../../escape',
        question: 0,
        take: 1,
        recorded: await tempVideo(tmp),
        segments: segments,
      );
      expect(t.videoPath, startsWith(root.path));
      expect(File(t.videoPath).parent.parent.path, root.path);
    });

    test('remove, removeTake and removeRound delete the video, audio and sidecar', () async {
      final st = store();
      Future<VideoTake> save(int q, int take, {int part = 0, String round = 'r'}) async => st.save(
        roundId: round,
        question: q,
        take: take,
        part: part,
        recorded: await tempVideo(tmp, 'v$q$take$part$round.mp4'),
        audio: Pcm(Float32List(160)),
        segments: segments,
      );
      final a = await save(0, 1);
      await save(0, 2);
      await save(0, 2, part: 1);
      await save(1, 1);
      await save(0, 1, round: 'other');

      await st.remove(a);
      expect(File(a.videoPath).existsSync(), isFalse);
      expect(File(a.audioPath!).existsSync(), isFalse);
      expect((await st.list(roundId: 'r')).length, 3);

      await st.removeTake('r', 0, 2);
      expect([for (final t in await st.list(roundId: 'r')) (t.question, t.take)], [(1, 1)]);

      await st.removeRound('r');
      expect(await st.list(roundId: 'r'), isEmpty);
      expect((await st.list()).single.roundId, 'other');
    });
  });

  group('the temporary clip', () {
    List<String> names(Directory d) => d.existsSync()
        ? [for (final e in d.listSync(recursive: true)) e.path.substring(d.path.length + 1)]
        : const [];

    test('across disks it is copied to a hidden .part file, renamed into place, then deleted', () async {
      final renames = <(String, String)>[];
      final st = VideoTakeStore(
        root,
        clock: () => now,
        rename: (from, to) async {
          if (from.path.contains('/camera/')) throw const FileSystemException('cross-device link');
          renames.add((from.uri.pathSegments.last, to.split('/').last));
          await from.rename(to);
        },
      );
      final cam = await tempVideo(Directory('${tmp.path}/camera'), 'camera_desktop_0_3.mp4');
      final t = await st.save(
        roundId: 'r',
        question: 0,
        take: 1,
        recorded: cam,
        audio: Pcm(Float32List(1600)),
        segments: segments,
      );
      expect(File(cam).existsSync(), isFalse, reason: 'the temporary clip is gone');
      expect(renames.map((r) => r.$1), everyElement(allOf(startsWith('.'), endsWith('.part'))));
      expect(renames.map((r) => r.$2), [
        '${t.id}.mp4',
        '${t.id}.wav',
        '${t.id}.json',
      ], reason: 'sidecar last');
      expect(names(root).where((n) => n.endsWith('.part')), isEmpty);
      expect((await st.list()).single.id, t.id);
    });

    test('a failed save deletes the temporary clip and everything it wrote', () async {
      final st = VideoTakeStore(
        root,
        clock: () => now,
        rename: (from, to) async {
          if (to.endsWith('.json')) throw const FileSystemException('disk full');
          await from.rename(to);
        },
      );
      final cam = await tempVideo(Directory('${tmp.path}/camera'));
      await expectLater(
        st.save(
          roundId: 'r',
          question: 0,
          take: 1,
          recorded: cam,
          audio: Pcm(Float32List(1600)),
          segments: segments,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(cam).existsSync(), isFalse);
      expect(names(root), isEmpty, reason: 'no clip, audio, sidecar or .part left behind');
      expect(await st.list(), isEmpty);
    });

    test(
      'after a crash the next start sweeps .part files, clips without a sidecar and stale camera files',
      () async {
        final st = store();
        final cam = await tempVideo(Directory('${tmp.path}/camera'));
        final kept = await st.save(roundId: 'r', question: 0, take: 1, recorded: cam, segments: segments);
        // What a crash mid-save leaves: a half copy and a clip whose sidecar never came.
        final dir = Directory('${root.path}/r');
        File('${dir.path}/.q2-t1-p0-1.mp4.part').writeAsBytesSync([1, 2]);
        File('${dir.path}/q3-t1-p0-2.mp4').writeAsBytesSync([1, 2]);
        File('${dir.path}/q3-t1-p0-2.wav').writeAsBytesSync([1, 2]);
        Directory('${root.path}/crashed').createSync();
        File('${root.path}/crashed/.q1-t1-p0-3.json.part').writeAsStringSync('{');
        // The recorder's temporary folder: an old clip, one still being written, and someone else's file.
        final camTmp = Directory('${tmp.path}/systmp')..createSync();
        final old = File('${camTmp.path}/camera_desktop_0_7.mp4')..writeAsBytesSync([1]);
        old.setLastModifiedSync(now.subtract(const Duration(hours: 1)));
        final android = File('${camTmp.path}/REC2049581.mp4')..writeAsBytesSync([1]);
        android.setLastModifiedSync(now.subtract(const Duration(days: 2)));
        final live = File('${camTmp.path}/camera_desktop_1_8.mkv')..writeAsBytesSync([1]);
        live.setLastModifiedSync(now.subtract(const Duration(minutes: 1)));
        final other = File('${camTmp.path}/holiday.mp4')..writeAsBytesSync([1]);
        other.setLastModifiedSync(now.subtract(const Duration(days: 30)));

        final retention = VideoRetention(st, () => 14, recorderTemps: [camTmp]);
        await retention.start();
        retention.stop();

        expect(names(dir)..sort(), ['${kept.id}.json', '${kept.id}.mp4']);
        expect(Directory('${root.path}/crashed').existsSync(), isFalse);
        expect(old.existsSync(), isFalse);
        expect(android.existsSync(), isFalse);
        expect(live.existsSync(), isTrue, reason: 'a recording in progress is left alone');
        expect(other.existsSync(), isTrue, reason: 'only the camera plugins\' file names are touched');
        expect((await st.list()).single.id, kept.id);
      },
    );
  });

  group('retention', () {
    test('takes older than 14 days go by default; newer ones stay', () async {
      final st = store();
      now = DateTime.utc(2026, 11, 1);
      final old = await st.save(
        roundId: 'r',
        question: 0,
        take: 1,
        recorded: await tempVideo(tmp, 'a.mp4'),
        segments: segments,
      );
      now = DateTime.utc(2026, 11, 10);
      final mid = await st.save(
        roundId: 'r',
        question: 1,
        take: 1,
        recorded: await tempVideo(tmp, 'b.mp4'),
        segments: segments,
      );
      now = DateTime.utc(2026, 11, 14, 12);
      expect(VideoTakeStore.defaultKeepDays, 14);
      expect(await st.purge(), 0, reason: '14 days have not passed for either');
      now = DateTime.utc(2026, 11, 15, 12).add(const Duration(days: 1));
      expect(await st.purge(), 1);
      final left = await st.list();
      expect(left.map((t) => t.id), [mid.id]);
      expect(File(old.videoPath).existsSync(), isFalse);
    });

    test('the user can keep them for fewer days, or more', () async {
      final st = store();
      await st.save(roundId: 'r', question: 0, take: 1, recorded: await tempVideo(tmp), segments: segments);
      now = now.add(const Duration(days: 3));
      expect(await st.purge(keepDays: 30), 0);
      expect(await st.purge(keepDays: 2), 1);
      expect(await st.list(), isEmpty);
      expect(root.listSync(), isEmpty, reason: 'the empty round folder goes too');
    });

    test('stray files older than the limit (an interrupted save) are cleaned up', () async {
      final st = store();
      final stray = File('${root.path}/r/q1-t1-p0-1.mp4')..createSync(recursive: true);
      stray.writeAsBytesSync([1, 2, 3]);
      stray.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 40)));
      now = DateTime.now().toUtc();
      await st.purge();
      expect(stray.existsSync(), isFalse);
    });

    test('VideoRetention purges at start and again on its timer', () async {
      final st = store();
      await st.save(
        roundId: 'r',
        question: 0,
        take: 1,
        recorded: await tempVideo(tmp, 'a.mp4'),
        segments: segments,
      );
      var days = 14;
      final ret = VideoRetention(st, () => days, every: const Duration(milliseconds: 20));
      expect(await ret.start(), 0);
      // The user shortens the limit and time passes: the next daily run purges.
      now = now.add(const Duration(days: 2));
      days = 1;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await st.list(), isEmpty);
      ret.stop();
    });

    test('delete all removes every take, and storage used counts the bytes', () async {
      final st = store();
      expect(await st.bytesUsed(), 0);
      await st.save(
        roundId: 'a',
        question: 0,
        take: 1,
        recorded: await tempVideo(tmp, 'a.mp4'),
        audio: Pcm(Float32List(1600)),
        segments: segments,
      );
      await st.save(
        roundId: 'b',
        question: 0,
        take: 1,
        recorded: await tempVideo(tmp, 'b.mp4'),
        segments: segments,
      );
      expect(await st.bytesUsed(), greaterThan(2 * 2048 + 3200));
      await st.deleteAll();
      expect(await st.list(), isEmpty);
      expect(await st.bytesUsed(), 0);
      expect(root.existsSync(), isFalse);
    });
  });

  group('seeking from a quoted line', () {
    VideoTake take({
      int number = 1,
      int part = 0,
      Duration lead = Duration.zero,
      List<SpokenSegment>? segs,
    }) => VideoTake(
      id: 't$number-$part',
      roundId: 'r',
      question: 0,
      take: number,
      part: part,
      recordedAt: now,
      videoPath: '/x.mp4',
      audioPath: null,
      audioLead: lead,
      segments: segs ?? segments,
    );

    test('a quote at the start of a stretch seeks to the stretch, half a second early', () {
      final seek = seekToQuote([take()], 'Two people were off')!;
      expect(seek.audio, s(5.5));
      expect(seek.video, s(5.5));
    });

    test('inside a stretch the moment is placed by the words before it', () {
      // "so I rang the bank staff..." starts at word 4 of 15 in 6 s – 14 s.
      final seek = seekToQuote([take()], 'so I rang the bank staff', leadIn: Duration.zero)!;
      expect(seek.audio, s(6) + s(8) * (4 / 15));
    });

    test('case, punctuation and a quote running over two stretches still match', () {
      final seek = seekToQuote(
        [take()],
        '"...moved the training day. Every shift was covered!"',
        leadIn: Duration.zero,
      );
      expect(seek, isNotNull);
      expect(seek!.audio, greaterThan(s(6)));
      expect(seek.audio, lessThan(s(14)));
    });

    test('the picture started after the audio: the video moment is earlier by that much', () {
      final seek = seekToQuote([take(lead: s(0.4))], 'Every shift was covered', leadIn: Duration.zero)!;
      expect(seek.audio, s(15));
      expect(seek.video, s(14.6));
      expect(seek.take.audioAt(seek.video), s(15));
    });

    test('the newest take wins, and a follow-up clip is found by its own words', () {
      final first = take(number: 1);
      final latest = take(number: 2);
      final follow = take(
        number: 2,
        part: 1,
        segs: [SpokenSegment(s(2), s(6), 'I would ask the manager first.')],
      );
      expect(seekToQuote([first, latest, follow], 'Every shift was covered')!.take, same(latest));
      expect(seekToQuote([first, latest, follow], 'ask the manager first')!.take, same(follow));
    });

    test('a quote no clip holds, or an empty quote, gives null; never a negative time', () {
      expect(seekToQuote([take()], 'I led the national programme'), isNull);
      expect(seekToQuote([take()], '...'), isNull);
      expect(seekToQuote(const [], 'Every shift was covered'), isNull);
      final early = seekToQuote([take(lead: s(3))], 'I ran the weekend rota')!;
      expect(early.video, Duration.zero);
    });
  });

  group('the round', () {
    const questions = [
      RoundQuestion('Tell us about a time you covered a gap at short notice.', tests: 'Problem solving.'),
      RoundQuestion('How do you decide what to do first?', tests: 'Organisation.'),
    ];

    SpokenRound round({VideoTakes? video, List<CapturedAnswer>? answers, ListSink? sink}) => SpokenRound(
      questions: questions,
      voice: FakeVoice(),
      listener: FakeListener(answers ?? [answerOf(segments)]),
      takes: MemoryTakes(),
      sink: sink ?? ListSink(),
      video: video,
      pause: (_) async {},
    )..start();

    test('video is off by default: no recorder is asked for anything', () async {
      final r = round();
      expect(r.video, isNull);
      await r.ask();
      await r.done();
      expect(r.state.latest!.transcript, contains('bank staff'));
      await r.close();
    });

    test('opted in: each kept answer becomes a clip with its audio and timestamps', () async {
      final rec = FakeVideoRecorder(Directory('${tmp.path}/camera'));
      final video = RoundVideo(roundId: 'round-7', recorder: rec, store: store());
      final r = round(video: video);
      await r.ask();
      expect(video.recording, isTrue, reason: 'the indicator shows while the microphone is open');
      expect(rec.starts, 1);
      await r.done();
      expect(video.recording, isFalse);
      final kept = await store().list(roundId: 'round-7');
      expect(kept.single.question, 0);
      expect(kept.single.take, 1);
      expect(kept.single.segments, hasLength(3));
      expect(kept.single.audioPath, isNotNull);
      expect(Directory('${tmp.path}/camera').listSync(), isEmpty, reason: 'the camera file was moved');
      await r.close();
    });

    test('a dropped answer keeps no clip; a replaced middle take loses its clip; take 1 stays', () async {
      final rec = FakeVideoRecorder(Directory('${tmp.path}/camera'));
      final video = RoundVideo(roundId: 'r', recorder: rec, store: store());
      final r = round(video: video);
      await r.ask();
      await r.typeInstead();
      expect(rec.cancels, 1);
      await r.submitTyped('A typed answer has no video.');
      for (var i = 0; i < 3; i++) {
        await r.retake();
        await r.done();
      }
      // Takes 2, 3 and 4 were spoken; 2 and 3 were replaced; 1 was typed.
      final kept = await store().list(roundId: 'r');
      expect([for (final t in kept) t.take], [4]);
      await r.skip();
      await r.close();
    });

    test('a camera that will not record leaves the round audio-only and says why', () async {
      final rec = FakeVideoRecorder(Directory('${tmp.path}/camera'), failStart: true);
      final video = RoundVideo(roundId: 'r', recorder: rec, store: store());
      final r = round(video: video);
      await r.ask();
      expect(r.phase, RoundPhase.answering);
      expect(r.error, isNull);
      await r.done();
      expect(r.state.latest!.transcript, isNotEmpty);
      expect(video.error, contains('did not start recording'));
      expect(await store().list(), isEmpty);
      await r.close();
    });
  });

  group('privacy', () {
    test('a video path never reaches a brain request or the synced answer text', () async {
      final rec = FakeVideoRecorder(Directory('${tmp.path}/camera'));
      final video = RoundVideo(roundId: 'round-p', recorder: rec, store: store());
      final sink = ListSink();
      final r = SpokenRound(
        questions: const [RoundQuestion('Why this role?', tests: 'Motivation.')],
        voice: FakeVoice(),
        listener: FakeListener([answerOf(segments)]),
        takes: MemoryTakes(),
        sink: sink,
        video: video,
        pause: (_) async {},
      )..start();
      await r.ask();
      await r.done();
      final clip = (await store().list(roundId: 'round-p')).single;

      final brain = ScriptedBrain(
        (_) => {
          'answers': [
            {
              'question': 1,
              'scores': [
                {'criterion': 'c1', 'level': '3', 'quote': 'I rang the bank staff'},
              ],
              'strength': 'A clear example.',
              'strengthQuote': 'Every shift was covered.',
              'fix': 'Say what you learned.',
            },
          ],
        },
      );
      await brain.scoreRound(
        role: 'Clerk',
        framework: Framework.of('private'),
        criteria: const [Criterion(id: 'c1', text: 'Organising work')],
        answers: [
          for (final (i, s) in r.states.indexed)
            (index: i, question: r.questions[i].text, criteria: const ['c1'], answer: s.fullTranscript),
        ],
      );
      final sent = [
        for (final q in brain.requests) ...[q.system, ...q.texts],
      ].join('\n');
      final synced = sink.saved.map((x) => x.$2).join('\n');
      for (final leak in [clip.videoPath, clip.id, root.path, '.mp4', '.wav', 'video-takes']) {
        expect(sent, isNot(contains(leak)), reason: 'brain request holds $leak');
        expect(synced, isNot(contains(leak)), reason: 'synced answer text holds $leak');
      }
      expect(synced, contains('bank staff'));
      await r.close();
    });

    test('video takes are written only inside the store\'s own folder', () async {
      final st = store();
      await st.save(
        roundId: 'r',
        question: 0,
        take: 1,
        recorded: await tempVideo(Directory('${tmp.path}/camera')),
        audio: Pcm(Float32List(160)),
        segments: segments,
      );
      final files = tmp.listSync(recursive: true).whereType<File>().map((f) => f.path).toList();
      expect(files, isNotEmpty);
      expect(files.every((p) => p.startsWith(root.path)), isTrue, reason: '$files');
    });
  });
}
