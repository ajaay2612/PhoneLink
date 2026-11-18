// Offline documentation renders. No Hub.start(), real pairing, filesystem or network access.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonelink_desktop/main.dart';
import 'package:phonelink_desktop/design.dart';
import 'package:phonelink_desktop/fs_api.dart';
import 'package:phonelink_desktop/recent_images.dart';

class ScreenshotHub extends Hub {
  @override
  bool get connected => true;
  @override
  int? get listeningPort => kPort;
}

class IllustrationFs extends RemoteFs {
  IllustrationFs(this.pictures)
    : super('127.0.0.1:8767', 'not-a-pairing-secret');
  final List<Uint8List> pictures;
  @override
  Future<Uint8List> imageBytes(
    String path, {
    bool thumbnail = true,
    String? version,
  }) async => pictures[int.parse(path.split('/').last) % pictures.length];
}

Future<Uint8List> illustration(int index) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final colors = [
    [const Color(0xFFBED0C5), const Color(0xFF466B60), const Color(0xFF20473F)],
    [const Color(0xFFE6D1AE), const Color(0xFFC29A65), const Color(0xFF735C43)],
    [const Color(0xFFBBD0DB), const Color(0xFF6D93A6), const Color(0xFF345A68)],
    [const Color(0xFFDDD0D7), const Color(0xFFAA8699), const Color(0xFF6E5365)],
  ][index % 4];
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 360, 360),
    Paint()..color = colors[0],
  );
  canvas.drawCircle(
    Offset(250 - index * 5.0, 95),
    42,
    Paint()..color = const Color(0xFFF6E9C7),
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, 260)
      ..lineTo(120, 100 + index * 8.0)
      ..lineTo(280, 300)
      ..lineTo(360, 200)
      ..lineTo(360, 360)
      ..lineTo(0, 360)
      ..close(),
    Paint()..color = colors[1],
  );
  canvas.drawPath(
    Path()
      ..moveTo(0, 315)
      ..quadraticBezierTo(130, 200, 360, 290)
      ..lineTo(360, 360)
      ..lineTo(0, 360)
      ..close(),
    Paint()..color = colors[2],
  );
  final image = await recorder.endRecording().toImage(360, 360);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

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
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await output.create(recursive: true);
      await File(
        '${output.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('render fictional desktop messages and clipboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final hub = ScreenshotHub()
      ..phoneName = 'Demo Phone'
      ..phoneStatus = {'battery': 76, 'charging': false, 'fileReady': true};
    addTearDown(hub.dispose);
    final now = DateTime(2026, 1, 12, 10, 42);
    hub.messages.addAll([
      Sms(
        now,
        'Aster ID',
        '482913',
        'Your verification code is 482913. It expires in 5 minutes. Do not share it.',
      ),
      Sms(
        now.subtract(const Duration(minutes: 1)),
        'Aster ID',
        '',
        'A new sign-in was requested for your demo account.',
      ),
      Sms(
        now.subtract(const Duration(minutes: 3)),
        'Aster ID',
        '',
        'This is a fictional preview. No real account is linked.',
      ),
      Sms(
        now.subtract(const Duration(minutes: 4)),
        'Aster ID',
        '',
        'Return to your browser after entering the code.',
      ),
      Sms(
        now.subtract(const Duration(minutes: 5)),
        'Aster ID',
        '',
        'Keep your verification code private. We will never ask you to share it.',
      ),
      Sms(
        now.subtract(const Duration(minutes: 6)),
        'Aster ID',
        '',
        'Welcome to your demo workspace.',
      ),
      Sms(
        now.subtract(const Duration(minutes: 7)),
        'Riley',
        '',
        'The workshop starts at 11. I saved you a seat near the window.',
      ),
      Sms(
        now.subtract(const Duration(minutes: 22)),
        'Parcel Post',
        '',
        'Your parcel is ready for collection. We are open until 6 pm.',
      ),
      Sms(
        now.subtract(const Duration(hours: 1)),
        'Jun',
        '',
        'Just sent the photos from our weekend walk. The light was lovely!',
      ),
      Sms(
        now.subtract(const Duration(hours: 2)),
        'Studio',
        '',
        'Your booking is confirmed for tomorrow at 2 pm. See you then.',
      ),
    ]);
    hub.activity.addAll([
      PhoneNotice(
        '',
        'File received',
        '',
        'Weekend notes.pdf',
        now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
      ),
      PhoneNotice(
        '',
        'Clipboard sent',
        '',
        'Meet at the station at 10:30.',
        now.subtract(const Duration(minutes: 4)).millisecondsSinceEpoch,
      ),
    ]);
    hub.lastClip =
        'Workshop notes\n\nBring the camera, a notebook, and the project sketches.\nMeet at the station at 10:30.';
    for (final dark in [true, false]) {
      desktopDarkMode.value = dark;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PhoneLinkApp(hub: hub),
        ),
      );
      await capture(
        tester,
        dark ? 'desktop-messages-dark' : 'desktop-messages-light',
      );
    }
    desktopDarkMode.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clipboard'));
    await capture(tester, 'desktop-clipboard-dark');
  });

  testWidgets(
    'render real file components with fictional files and generated illustrations',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      desktopDarkMode.value = true;
      final pictures = await tester.runAsync(
        () async => [for (var i = 0; i < 9; i++) await illustration(i)],
      );
      final fs = IllustrationFs(pictures!);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: phoneLinkTheme(),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const PageHeading(title: 'Files'),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: FileBrowser(
                              device: 'phone',
                              available: true,
                              busy: false,
                              path: '/',
                              entries: [
                                FEntry('DCIM', true, 0),
                                FEntry('Documents', true, 0),
                                FEntry('Download', true, 0),
                                FEntry('Pictures', true, 0),
                                FEntry('Weekend notes.pdf', false, 240128),
                                FEntry('Project sketches.zip', false, 1824000),
                              ],
                              showHidden: false,
                              status: '',
                              onToggleHidden: () {},
                              onRefresh: () {},
                              onUpload: () {},
                              onUp: () {},
                              onOpen: (_) {},
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: RecentImagesPanel(
                              fs: fs,
                              images: [
                                for (var i = 0; i < 9; i++)
                                  RemoteImage(
                                    'Demo illustration ${i + 1}',
                                    '/demo/$i',
                                    42000,
                                    0,
                                  ),
                              ],
                              loading: false,
                              error: null,
                              onDownload: (_) async {},
                              onLoadMore: () {},
                              hasMore: false,
                              revision: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byType(RecentImagesPanel));
        for (final picture in pictures) {
          await precacheImage(
            ResizeImage.resizeIfNeeded(480, null, MemoryImage(picture)),
            context,
          );
        }
      });
      await capture(tester, 'desktop-files-preview');
    },
  );
}
