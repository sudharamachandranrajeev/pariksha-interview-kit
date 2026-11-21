import 'dart:io';

import 'package:flutter/material.dart';
import 'package:interview_engine/interview_engine.dart';
import 'package:ui_kit/ui_kit.dart';

/// Build check for the kit. Run with `--probe` to load each native library,
/// print what loaded, and exit (0 when all loaded, 1 otherwise).
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.contains('--probe')) {
    final probe = await probeNative();
    stdout.writeln('pariksha probe: $probe');
    exit(probe.ok ? 0 : 1);
  }
  runApp(const ExampleApp());
}

const _palette = KitPalette(
  top: Color(0xFFF3F1EA),
  bottom: Color(0xFFFBFAF6),
  glow: Color(0x335B7A4A),
  glow2: Color(0x22B5651D),
  surface: Color(0xFFFFFFFF),
  card: Color(0xFFFFFFFF),
  subtle: Color(0xFFF2F0E8),
  raised: Color(0xFFEAE7DD),
  hairline: Color(0xFFE2DED2),
  text: Color(0xFF1F2219),
  heading: Color(0xFF1F2219),
  muted: Color(0xFF5E6355),
  primary: Color(0xFF4F6B3F),
);

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pariksha example',
    theme: ThemeData(extensions: const [_palette]),
    home: const ProbePage(),
  );
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  late final Future<NativeProbe> _probe = probeNative();

  @override
  Widget build(BuildContext context) {
    final p = KitPalette.of(context);
    return Scaffold(
      backgroundColor: p.bottom,
      appBar: AppBar(title: const Text('Pariksha kit: native check')),
      body: FutureBuilder<NativeProbe>(
        future: _probe,
        builder: (context, snap) {
          final r = snap.data;
          if (r == null) return const Center(child: CircularProgressIndicator());
          final status = r.ok ? KitStatus.good : KitStatus.critical;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: Icon(status.icon, color: status.color),
                title: Text(r.ok ? 'All native libraries loaded' : 'Some libraries failed'),
              ),
              ListTile(title: const Text('Speech (sherpa_onnx)'), subtitle: Text(r.sherpaOnnx ?? 'failed')),
              ListTile(title: const Text('Vision (LiteRT)'), subtitle: Text(r.liteRt ?? 'failed')),
              ListTile(title: const Text('Cameras found'), subtitle: Text('${r.cameras ?? 'failed'}')),
              for (final e in r.errors) Text(e, style: TextStyle(color: p.muted)),
            ],
          );
        },
      ),
    );
  }
}
