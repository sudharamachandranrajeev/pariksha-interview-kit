// Network-off test: importing the engine and running its pure parts must
// never open a connection to another machine. Every HTTP client and plain
// socket made inside the zone is trapped; connections to this machine (for a
// local Ollama) are allowed. Same approach as Udyoga's offline guard.
//
// The second test runs every part of the engine that works without a device:
// question plans and probes, process templates, criteria, a brain round trip,
// verified-quote scoring and the debrief, a whole spoken round with test
// doubles, the camera set-up check, the offline guard, the model manager and
// the shared model folder. None may reach another machine.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_engine/interview_engine.dart';
import 'package:interview_engine/testing.dart';

import 'engine_test.dart' show CannedBrain;
import 'interview_lab_test.dart' show fakeModel;
import 'model_folder_test.dart' show install;

bool _loopback(String host) {
  final h = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  final ip = InternetAddress.tryParse(h);
  return ip != null && ip.isLoopback;
}

String _hostOf(Object? host) => host is InternetAddress ? host.address : '$host';

/// Records and refuses every attempt to reach another machine.
class _Trap {
  final attempts = <String>[];
  SocketException refuse(String host) {
    attempts.add(host);
    return SocketException('network-off test: $host was not contacted');
  }
}

class _TrapHttp extends HttpOverrides {
  _TrapHttp(this.trap);
  final _Trap trap;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)..findProxy = ((_) => 'DIRECT');
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      if (!_loopback(uri.host)) return Future.error(trap.refuse(uri.host));
      return Socket.startConnect(uri.host, uri.port);
    };
    return client;
  }
}

final class _TrapIo extends IOOverrides {
  _TrapIo(this.trap);
  final _Trap trap;

  @override
  Future<Socket> socketConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    final h = _hostOf(host);
    if (!_loopback(h)) return Future.error(trap.refuse(h));
    return super.socketConnect(
      host,
      port,
      sourceAddress: sourceAddress,
      sourcePort: sourcePort,
      timeout: timeout,
    );
  }

  @override
  Future<ConnectionTask<Socket>> socketStartConnect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
  }) {
    final h = _hostOf(host);
    if (!_loopback(h)) return Future.error(trap.refuse(h));
    return super.socketStartConnect(host, port, sourceAddress: sourceAddress, sourcePort: sourcePort);
  }
}

Future<T> _offline<T>(_Trap trap, Future<T> Function() body) => HttpOverrides.runZoned(
  () => IOOverrides.runZoned(
    body,
    socketConnect: _TrapIo(trap).socketConnect,
    socketStartConnect: _TrapIo(trap).socketStartConnect,
  ),
  createHttpClient: _TrapHttp(trap).createHttpClient,
);

void main() {
  test('the trap works: a request to another machine is refused and recorded', () async {
    final trap = _Trap();
    await _offline(trap, () async {
      final client = HttpClient();
      await expectLater(client.getUrl(Uri.parse('http://192.0.2.10/')), throwsA(isA<SocketException>()));
      client.close(force: true);
      await expectLater(Socket.connect('192.0.2.11', 80), throwsA(isA<SocketException>()));
    });
    expect(trap.attempts, ['192.0.2.10', '192.0.2.11']);
  });

  test('the engine\'s plans, scoring, spoken round, camera check and models make no network calls', () async {
    final trap = _Trap();
    final tmp = await Directory.systemTemp.createTemp('engine-network-off-');
    await _offline(trap, () async {
      // Plans, probes and processes.
      const q = EngineQuestion({
        'question': 'Tell us about a time you covered a gap at short notice.',
        'category': 'Behavioural',
        'why': 'Problem solving.',
      });
      final plan = templatePlan(q);
      expect(plan.expected, hasLength(6));
      expect(ProbePicker.next(plan: plan, heard: 'We managed.', asked: const []), isNotNull);
      expect(mergePlans(const [q], const []), hasLength(1));
      for (final t in processTemplates) {
        expect(t.stages.first.roundQuestions(), isNotEmpty);
      }

      // Criteria, a brain round trip and verified-quote scoring.
      final criteria = parseCriteria({
        'criteria': [
          {
            'text': 'Managing a busy diary',
            'essential': true,
            'kind': 'experience',
            'assessBy': [],
            'question': '',
          },
        ],
      });
      final profile = RoleProfile(id: 'p', title: 'Clerk', frameworkId: 'nhs_values', criteria: criteria);
      const answer = 'I moved the overflow to a Tuesday session. As a result bookings fell from nine to one.';
      final round = DebriefRound.of(
        questions: questionsFromProfile(profile),
        answers: {1: answer},
        profile: profile,
      );
      final brain = CannedBrain([
        {
          'answers': [
            {
              'question': 2,
              'scores': [
                {'criterion': criteria.single.id, 'level': '3', 'quote': 'I moved the overflow'},
              ],
              'strength': 'A clear example.',
              'fix': 'Say what you learned.',
            },
          ],
        },
      ]);
      final raw = await brain.scoreRound(
        role: 'Clerk',
        framework: profile.framework,
        criteria: criteria,
        answers: [
          (index: 1, question: 'Q?', criteria: [criteria.single.id], answer: answer),
        ],
      );
      final verified = verifyScores(raw, profile.framework.scale, heard: round.heard, asked: round.asked);
      expect(verified.scores, isNotEmpty);
      Debrief.build(framework: profile.framework, round: round, verified: verified);

      // A whole spoken round with test doubles.
      final voice = FakeVoice();
      final spoken = SpokenRound(
        questions: const [RoundQuestion('Why this role?', tests: 'Motivation.')],
        voice: voice,
        listener: FakeListener([spokenAnswer('Because I like the work and the team.')]),
        takes: MemoryTakes(),
        sink: ListSink(),
        pause: (_) async {},
      )..start();
      await spoken.ask();
      await spoken.done();
      await spoken.close();
      expect(voice.said, isNotEmpty);

      // The camera set-up check.
      final check = SetupChecker();
      for (var i = 0; i < 15; i++) {
        check.add(frameMeasure());
      }
      expect(check.results, isNotEmpty);

      // The offline guard, the model manager and the shared folder.
      await OfflineGuard.instance.run(() async {
        final mm = ModelManager(Directory('${tmp.path}/models'));
        expect(await mm.installed(speechModel(vadModelId)), isFalse);
        await expectLater(mm.download(speechModel(vadModelId)), throwsA(isA<ModelException>()));
      });
      final body = List<int>.generate(100, (i) => i);
      final m = fakeModel(body);
      await install(Directory('${tmp.path}/own'), m, body);
      final r = await adoptModels(
        from: Directory('${tmp.path}/own'),
        to: Directory('${tmp.path}/shared'),
        models: [m],
      );
      expect(r.moved, [m.id]);

      // Let any timers or microtasks run.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tmp.delete(recursive: true);
    expect(trap.attempts, isEmpty);
  });
}
