// ignore_for_file: invalid_use_of_visible_for_testing_member
// Offline documentation fixtures. initialize:false skips services, permissions and pairing.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phonelink_android/main.dart';
import 'package:phonelink_android/design.dart';

void main() {
  final boundaryKey = GlobalKey();
  final output = Directory(
    Platform.environment['PHONELINK_SCREENSHOT_DIR'] ?? '../docs/images',
  );
  setUpAll(() async {
    final loader = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await loader.load();
  });
  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await output.create(recursive: true);
      await File(
        '${output.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('render phone using fictional connection and activity data', (
    tester,
  ) async {
    final previousShadowSetting = debugDisableShadows;
    debugDisableShadows = false;
    try {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      for (final dark in [true, false]) {
        phoneThemeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: phoneLinkTheme(),
              home: Home(key: ValueKey(dark), initialize: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(Home));
        state.connected = true;
        state.wantConnected = true;
        state.host.text = '192.168.50.10:8766';
        // No token means the offstage file tab cannot create a network client.
        state.log.addAll([
          'Connected to your demo PC',
          'Clipboard from PC',
          'Sent 6 recent messages',
          'File received: Weekend notes.pdf',
          'Clipboard sent to PC',
          'File sent: Project sketches.zip',
          'Phone storage access allowed',
          'Background connection ready',
        ]);
        state.notificationAccess = true;
        state.connectionNotificationsEnabled = true;
        state.storageAccess = true;
        tester.element(find.byType(Home)).markNeedsBuild();
        await capture(
          tester,
          dark ? 'phone-device-dark' : 'phone-device-light',
        );
        if (dark) {
          await tester.tap(find.bySemanticsLabel('Settings'));
          await capture(tester, 'phone-settings-dark');
        }
      }
    } finally {
      debugDisableShadows = previousShadowSetting;
    }
  });
}
