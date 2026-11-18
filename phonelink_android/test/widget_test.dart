import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phonelink_android/main.dart';
import 'package:phonelink_android/design.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await loader.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    phoneThemeMode.value = ThemeMode.system;
  });

  Future<void> open(WidgetTester tester, Size size, {double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: phoneLinkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Home(initialize: false),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Pairing home and files navigation render on a phone', (
    tester,
  ) async {
    await open(tester, const Size(390, 844));
    expect(find.text('Scan PC code'), findsOneWidget);
    expect(find.textContaining('To send copied text'), findsNothing);
    expect(find.text('Pair another PC'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('PhoneLink'), findsNothing);
    expect(find.text('My devices'), findsWidgets);
    expect(find.text('Notification access'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Notification access'), findsOneWidget);
    expect(find.byType(DropdownButton<ThemeMode>), findsNothing);
    expect(find.byType(ThemeChoice), findsNWidgets(3));
    expect(find.byType(AppSwitch), findsNothing);
    expect(find.text('Clipboard sync'), findsNothing);
    await tester.tap(find.bySemanticsLabel('PC files'));
    await tester.pumpAndSettle();
    expect(find.text('Your files, within reach'), findsOneWidget);
    await tester.tap(find.byTooltip('File options'));
    await tester.pumpAndSettle();
    expect(find.text('Show hidden files'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Send files'), findsOneWidget);
    await tester.tap(find.text('Show hidden files'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('File options'));
    await tester.pumpAndSettle();
    expect(find.text('Hide hidden files'), findsOneWidget);
    await tester.tap(find.text('Hide hidden files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connect a device'));
    await tester.pumpAndSettle();
    expect(find.text('Scan PC code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Small phone keeps manual pairing reachable with keyboard', (
    tester,
  ) async {
    await open(tester, const Size(360, 640));
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Connect manually'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Connect manually'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == '192.168.1.5:8766',
      ),
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == '192.168.1.5:8766',
      ),
      '192.168.1.5:8766',
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Connect to PC'));
    expect(find.text('Connect to PC').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Large text and landscape do not overflow', (tester) async {
    await open(tester, const Size(390, 844), scale: 1.5);
    expect(tester.takeException(), isNull);
    await tester.tap(find.bySemanticsLabel('PC files'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await open(tester, const Size(760, 360));
    expect(tester.takeException(), isNull);
  });
  test(
    'Disconnected background forwarding does not open a network connection',
    () async {
      SharedPreferences.setMockInitialValues({
        'connectionEnabled': false,
        'token': 'paired-token',
        'host': '127.0.0.1:8766',
      });
      var attempts = 0;
      await HttpOverrides.runZoned(
        () => oneShot({'type': 'sms', 'body': 'test'}),
        createHttpClient: (_) {
          attempts++;
          throw StateError(
            'No network connection is allowed while disconnected',
          );
        },
      );
      expect(attempts, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), 'paired-token');
    },
  );
}
