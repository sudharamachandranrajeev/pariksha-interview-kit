import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import 'support.dart';

/// Every kit widget builds in light and dark, with and without an installed
/// palette, and stands still under reduced motion. No goldens: behaviour
/// only.
void main() {
  final widgets = <String, Widget Function()>{
    'BlurFadeIn': () => const BlurFadeIn(index: 3, child: Text('faded')),
    'BorderBeam': () => const BorderBeam(child: SizedBox(width: 200, height: 80)),
    'DotGrid': () => const SizedBox(width: 200, height: 120, child: DotGrid(child: Text('dots'))),
    'Glass': () => const Glass(padding: EdgeInsets.all(8), child: Text('glass')),
    'RollingNumber': () => const RollingNumber(1234, prefix: '£'),
    'ShimmerSkeleton': () => const ShimmerSkeleton(width: 120),
    'SkeletonCards': () => const SingleChildScrollView(child: SkeletonCards(count: 2)),
    'SpotlightCard': () => const SpotlightCard(child: Text('card')),
    'StatGrid': () => const SingleChildScrollView(
      child: StatGrid(
        children: [
          StatTile(label: 'Streak', icon: Icons.local_fire_department, value: 4, suffix: ' days'),
          StatTile(label: 'Minutes', icon: Icons.timer_outlined, value: null),
          StatTile(
            label: 'Ready',
            icon: Icons.check,
            value: 2,
            caption: 'Two of five',
            status: KitStatus.good,
          ),
        ],
      ),
    ),
    'StatusPill': () => const StatusPill('Closes soon', status: KitStatus.warning),
    'Tilt': () => const Tilt(child: Text('press me')),
    'TiltGrid': () => const TiltGrid(children: [Text('a'), Text('b')]),
    'Headline': () => const Headline(['Good ', 'morning', '.']),
    'Backdrop': () => const SizedBox(width: 300, height: 300, child: Backdrop(child: Text('page'))),
  };

  for (final MapEntry(key: name, value: build) in widgets.entries) {
    group(name, () {
      for (final b in Brightness.values) {
        testWidgets('builds in ${b.name} mode', (tester) async {
          await tester.pumpWidget(kitApp(build(), brightness: b));
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('builds on a theme with no KitPalette', (tester) async {
        await tester.pumpWidget(kitApp(build(), palette: false, brightness: Brightness.dark));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
      });

      testWidgets('nothing moves under reduced motion', (tester) async {
        await tester.pumpWidget(kitApp(build(), reduced: true));
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0, reason: '$name kept a ticker running');
      });
    });
  }

  testWidgets('paced durations drop to zero under reduced motion', (tester) async {
    late Duration normal, reduced;
    await tester.pumpWidget(kitApp(Builder(builder: (c) => Text('${normal = paced(c, Pace.slow)}'))));
    await tester.pumpWidget(
      kitApp(Builder(builder: (c) => Text('${reduced = paced(c, Pace.slow)}')), reduced: true),
    );
    expect(normal, Pace.slow);
    expect(reduced, Duration.zero);
  });

  testWidgets('BlurFadeIn fades in, then leaves its child bare', (tester) async {
    await tester.pumpWidget(kitApp(const BlurFadeIn(child: Text('x'))));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.ancestor(of: find.text('x'), matching: find.byType(Opacity)), findsWidgets);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.ancestor(of: find.text('x'), matching: find.byType(ImageFiltered)), findsNothing);
  });

  testWidgets('BorderBeam runs, and stops under reduced motion', (tester) async {
    await tester.pumpWidget(kitApp(const BorderBeam(child: SizedBox(width: 50, height: 50))));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(kitApp(const BorderBeam(child: SizedBox(width: 50, height: 50)), reduced: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  group('RollingNumber', () {
    test('formats with grouping, prefix, suffix and sign', () {
      expect(RollingNumber.format(1234), '1,234');
      expect(RollingNumber.format(1250, prefix: '£', showSign: true), '+£1,250');
      expect(RollingNumber.format(-1250, prefix: '£'), '−£1,250');
      expect(RollingNumber.format(12.5, fractionDigits: 1, suffix: '%'), '12.5%');
    });

    testWidgets('rolls and lands on the final value', (tester) async {
      await tester.pumpWidget(kitApp(const RollingNumber(5)));
      await tester.pumpWidget(kitApp(const RollingNumber(1234)));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('1,234'), findsNothing);
      expect(find.bySemanticsLabel('1,234'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1,234'), findsOneWidget);
    });

    testWidgets('shows the new value at once under reduced motion', (tester) async {
      await tester.pumpWidget(kitApp(const RollingNumber(3), reduced: true));
      await tester.pumpWidget(kitApp(const RollingNumber(42, prefix: '£'), reduced: true));
      expect(find.text('£42'), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  test('StatGrid picks a column count the tiles divide into', () {
    expect(StatGrid.columnsFor(6, 700), 3);
    expect(StatGrid.columnsFor(4, 700), 4);
    expect(StatGrid.columnsFor(3, 320), 2);
    expect(StatGrid.columnsFor(0, 320), 1);
  });

  group('RisePageTransitionsBuilder', () {
    Widget app({required bool reduced, Widget Function(Widget)? backdrop = kitBackdrop}) => MaterialApp(
      theme: ThemeData(
        extensions: const [azureLight],
        pageTransitionsTheme: PageTransitionsTheme(
          builders: RisePageTransitionsBuilder.everywhere(RisePageTransitionsBuilder(backdrop: backdrop)),
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('next')))),
          child: const Text('go'),
        ),
      ),
    );

    testWidgets('a pushed page rises into place on its own canvas', (tester) async {
      await tester.pumpWidget(app(reduced: false));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final lift = tester.widget<Transform>(
        find.ancestor(of: find.text('next'), matching: find.byType(Transform)).first,
      );
      expect(lift.transform.getTranslation().y, greaterThan(0));
      expect(find.ancestor(of: find.text('next'), matching: find.byType(Backdrop)), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('next'), findsOneWidget);
    });

    testWidgets('under reduced motion it only fades', (tester) async {
      await tester.pumpWidget(app(reduced: true, backdrop: null));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.ancestor(of: find.text('next'), matching: find.byType(FadeTransition)), findsWidgets);
      expect(find.ancestor(of: find.text('next'), matching: find.byType(Backdrop)), findsNothing);
    });
  });

  // KitSheet only lives inside a sheet route, so it is tested through
  // showSheet, in both modes.
  testWidgets('sheets open and close; at once under reduced motion', (tester) async {
    for (final (reduced, b) in [
      (false, Brightness.light),
      (true, Brightness.light),
      (false, Brightness.dark),
      (true, Brightness.dark),
    ]) {
      await tester.pumpWidget(kitApp(const SizedBox(), reduced: reduced, brightness: b));
      final context = tester.element(find.byType(SizedBox).last);
      showSheet<void>(context, builder: (_) => const Text('In a sheet'));
      await tester.pump();
      if (reduced) {
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
      } else {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.text('In a sheet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.text('In a sheet'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('In a sheet'), findsNothing);
    }
  });

  testWidgets('Headline paints the picked-out phrase in the palette primary', (tester) async {
    await tester.pumpWidget(kitApp(const Headline(['Hello ', 'there'])));
    final rich = tester.widget<Text>(find.byType(Text).last).textSpan! as TextSpan;
    expect((rich.children![1] as TextSpan).style!.color, azureLight.primary);
  });
}
