import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phonelink_desktop/desktop_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('phonelink/clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test(
    'native bridge handles reads and writes without a focused Flutter clipboard',
    () async {
      final calls = <String>[];
      String? written;
      messenger.setMockMethodCallHandler(native, (call) async {
        calls.add(call.method);
        if (call.method == 'available') return true;
        if (call.method == 'readText') return 'background copy';
        if (call.method == 'writeText') written = call.arguments as String;
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        fail('Native clipboard must not use the focus-dependent platform path');
      });
      final clipboard = DesktopClipboard();
      expect(await clipboard.readText(), 'background copy');
      await clipboard.writeText('from phone');
      expect(written, 'from phone');
      expect(calls, ['available', 'readText', 'writeText']);
    },
  );

  test('overlapping polls share a single pending native read', () async {
    final pending = Completer<String>();
    final started = Completer<void>();
    var reads = 0;
    messenger.setMockMethodCallHandler(native, (call) async {
      if (call.method == 'available') return true;
      if (call.method == 'readText') {
        reads++;
        started.complete();
        return pending.future;
      }
      return null;
    });
    final clipboard = DesktopClipboard();
    final first = clipboard.readText();
    final second = clipboard.readText();
    await started.future;
    expect(reads, 1);
    pending.complete('one change');
    expect(await first, 'one change');
    expect(await second, 'one change');
  });

  test(
    'failed native read does not replay a stale foreground selection',
    () async {
      messenger.setMockMethodCallHandler(native, (call) async {
        if (call.method == 'available') return true;
        throw PlatformException(code: 'unavailable');
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        fail('Do not fall back to stale foreground clipboard data');
      });
      expect(await DesktopClipboard().readText(), isNull);
    },
  );

  test(
    'uses normal clipboard when a background bridge is unavailable',
    () async {
      String? written;
      messenger.setMockMethodCallHandler(native, (call) async => false);
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': 'standard copy'};
        }
        if (call.method == 'Clipboard.setData') {
          written = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      final clipboard = DesktopClipboard();
      expect(await clipboard.readText(), 'standard copy');
      await clipboard.writeText('standard write');
      expect(written, 'standard write');
    },
  );
}
