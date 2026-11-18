import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonelink_desktop/main.dart';
import 'package:phonelink_desktop/design.dart';

class TestHub extends Hub {
  bool isConnected = true;
  @override
  bool get connected => isConnected;
  @override
  void setAutoCopy(bool value) {
    autoCopy = value;
    notifyListeners();
  }

  @override
  void setClipSync(bool value) {
    clipSync = value;
    notifyListeners();
  }
}

void main() {
  String? clipboard;
  setUp(() {
    clipboard = null;
    desktopDarkMode.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        });
  });
  test(
    'a clipboard read started before an incoming write cannot echo stale text',
    () async {
      final hub = TestHub();
      final pendingRead = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') return pendingRead.future;
            return null;
          });
      final poll = hub.sendClip(force: false);
      await hub.setClip('text from phone');
      pendingRead.complete({'text': 'old PC clipboard'});
      await poll;
      expect(hub.lastClip, 'text from phone');
      expect(hub.activity, isEmpty);
      hub.dispose();
    },
  );

  test(
    'explicit app copy syncs while incoming clipboard writes stay local',
    () async {
      final hub = TestHub();
      await hub.setClip('123456', syncToPhone: true);
      expect(clipboard, '123456');
      expect(hub.activity.single.app, 'Clipboard sent');
      await hub.setClip('received from phone');
      expect(hub.activity.length, 1);
      hub.setClipSync(false);
      await hub.setClip('654321', syncToPhone: true);
      expect(clipboard, '654321');
      expect(hub.activity.length, 1);
      hub.dispose();
    },
  );

  setUpAll(() async {
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await loader.load();
  });
  Future<TestHub> open(
    WidgetTester tester,
    Size size, {
    bool populated = true,
    bool connected = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hub = TestHub()
      ..isConnected = connected
      ..token = 'demo1234'
      ..addresses = ['192.168.1.5:8766'];
    if (populated) {
      hub.messages.addAll([
        Sms(
          DateTime(2026, 11, 15, 10, 42),
          'Example Bank',
          '482913',
          'Your verification code is 482913. Do not share this code.',
        ),
        Sms(
          DateTime(2026, 11, 15, 10, 30),
          'Alex',
          '',
          'On my way. See you in a few minutes!',
        ),
        Sms(
          DateTime(2026, 11, 15, 9, 15),
          'Parcel updates',
          '',
          'Your package is out for delivery today.',
        ),
      ]);
    }
    await tester.pumpWidget(PhoneLinkApp(hub: hub));
    await tester.pumpAndSettle();
    addTearDown(hub.dispose);
    return hub;
  }

  testWidgets('Inbox search, copy and all desktop pages work', (tester) async {
    final hub = await open(tester, const Size(1280, 850));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Copy code').first);
    await tester.pumpAndSettle();
    expect(clipboard, '482913');
    await tester.enterText(find.byType(TextField).first, 'Alex');
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsWidgets);
    expect(find.text('Example Bank'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'no match');
    await tester.pumpAndSettle();
    expect(find.text('No matching messages'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Example Bank'), findsWidgets);
    await tester.tap(find.byTooltip('Clipboard'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Your files, within reach'), findsOneWidget);
    expect(find.text('Recent images'), findsOneWidget);
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
    hub.isConnected = false;
    hub.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pair phone'));
    await tester.pumpAndSettle();
    expect(find.text('Connect in three steps'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byTooltip('Close pairing'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Your files, within reach'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compact and narrow navigation stay usable', (tester) async {
    await open(tester, const Size(760, 700), connected: false);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Pair phone'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byTooltip('Close pairing'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await open(
      tester,
      const Size(600, 800),
      populated: false,
      connected: false,
    );
    expect(find.byTooltip('Messages'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (var i = 1; i < 4; i++) {
      await tester.tap(
        find.byTooltip(['Messages', 'Clipboard', 'Files', 'Pair phone'][i]),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (find.byType(Dialog).evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Close pairing'));
        await tester.pumpAndSettle();
      }
    }
  });
  testWidgets('Tall narrow desktop window keeps all pages usable', (
    tester,
  ) async {
    await open(tester, const Size(430, 800), connected: false);
    expect(tester.takeException(), isNull);
    for (final label in ['Clipboard', 'Files', 'Pair phone', 'Messages']) {
      await tester.tap(find.byTooltip(label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (find.byType(Dialog).evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Close pairing'));
        await tester.pumpAndSettle();
      }
    }
  });
  testWidgets('Device panel remains visible at the reported desktop width', (
    tester,
  ) async {
    await open(tester, const Size(1050, 880));
    expect(find.text('Android phone'), findsOneWidget);
    expect(find.text('Browse phone files'), findsNothing);
    expect(find.text('Pair another device'), findsNothing);
    expect(find.text('On your network'), findsNothing);
    final panel = find.byKey(const ValueKey('workspace-tabs'));
    for (final label in ['Messages', 'Clipboard', 'Files']) {
      expect(
        find.descendant(of: panel, matching: find.byTooltip(label)),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Pairing action follows connection state on wide and narrow windows',
    (tester) async {
      final hub = await open(tester, const Size(1050, 880));
      expect(find.byTooltip('Pair phone'), findsNothing);
      hub.isConnected = false;
      hub.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pair phone'), findsOneWidget);
      tester.view.physicalSize = const Size(600, 800);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pair phone'), findsOneWidget);
      hub.isConnected = true;
      hub.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pair phone'), findsNothing);
    },
  );
  testWidgets('Send files opens the chooser before checking phone readiness', (
    tester,
  ) async {
    await open(tester, const Size(1050, 880), connected: false);
    await tester.tap(find.byTooltip('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('File options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send files'));
    await tester.pumpAndSettle();
    expect(find.text('Choose files to send'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byTooltip('Close file chooser'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Recent images'), findsOneWidget);
  });
  testWidgets('Connected device displays the phone name and status', (
    tester,
  ) async {
    final hub = await open(tester, const Size(1050, 880));
    hub.phoneName = 'My OnePlus';
    hub.phoneStatus = {
      'network': 'Wi-Fi',
      'wifi': 'Connected · 80% signal',
      'battery': 64,
      'charging': true,
    };
    hub.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('My OnePlus'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.byTooltip('Charging'), findsOneWidget);
    expect(find.byTooltip('Wi-Fi: Connected · 80% signal'), findsNothing);
    expect(find.byTooltip('Refresh connection'), findsOneWidget);
    expect(find.text('From phone to PC'), findsNothing);
  });
  testWidgets('Recents combines messages and completed transfer activity', (
    tester,
  ) async {
    final hub = await open(tester, const Size(1280, 850));
    hub.recordActivity('File sent', 'report.pdf');
    hub.recordActivity('Clipboard received', 'Text from phone');
    await tester.pumpAndSettle();
    expect(find.text('Recents'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('Text from phone'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Quick actions'), findsNothing);
    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Theme palettes and clipped control surfaces stay consistent', (
    tester,
  ) async {
    await open(tester, const Size(1280, 850));
    expect(find.byType(AppSwitch), findsOneWidget);
    for (final element in find.byType(Surface).evaluate()) {
      final material = find
          .descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.widget<Material>(material).clipBehavior, Clip.antiAlias);
    }
    desktopDarkMode.value = true;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(HomePage))).brightness,
      Brightness.dark,
    );
    expect(find.byTooltip('Switch to light mode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
