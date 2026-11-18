import 'dart:async';
import 'package:flutter/services.dart';

/// Uses the native background clipboard bridge without moving/focusing the UI.
/// Platforms without it retain Flutter's normal clipboard behavior.
class DesktopClipboard {
  static const _channel = MethodChannel('phonelink/clipboard');
  Future<bool>? _availability;
  Future<String?>? _reading;

  Future<bool> _available() => _availability ??= () async {
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }();

  Future<String?> readText() => _reading ??= _readText().whenComplete(() {
    _reading = null;
  });

  Future<String?> _readText() async {
    if (!await _available()) {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    }
    try {
      return await _channel
          .invokeMethod<String>('readText')
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> writeText(String text) async {
    if (await _available()) {
      await _channel.invokeMethod<void>('writeText', text);
    } else {
      await Clipboard.setData(ClipboardData(text: text));
    }
  }
}
