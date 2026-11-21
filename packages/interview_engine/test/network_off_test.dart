// Network-off test: importing the engine and running its pure parts must
// never open a connection to another machine. Every HTTP client and plain
// socket made inside the zone is trapped; connections to this machine (for a
// local Ollama) are allowed. Same approach as Udyoga's offline guard.
//
// J2 moves Udyoga's OfflineGuard into this package; this test then grows to
// cover it. For J0 it proves the import and start-up path is quiet.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:interview_engine/interview_engine.dart';

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

  test('engine import and start-up make no network calls', () async {
    final trap = _Trap();
    await _offline(trap, () async {
      final q = EngineQuestion.fromJson({
        'question': 'Why this role?',
        'lookFor': ['Motivation'],
      });
      expect(EngineQuestion.fromJson(q.toJson()).question, q.question);
      const s = QuotedScore(criterion: 'Motivation', score: null, quote: '');
      expect(s.score, isNull);
      // Let any start-up timers or microtasks run.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(trap.attempts, isEmpty);
  });
}
