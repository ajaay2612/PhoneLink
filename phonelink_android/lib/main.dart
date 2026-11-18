import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import 'fs_api.dart';
import 'secure_transport.dart';
import 'app_icon.dart';
import 'design.dart';

const int kFilePort = 8767;
const String kPhoneRoot = '/storage/emulated/0';
const String kDownloadDir = '/storage/emulated/0/Download/PhoneLink';

final FlutterLocalNotificationsPlugin notifs =
    FlutterLocalNotificationsPlugin();

/// Opens a short connection, tries the last host then every saved address.
/// Works even when the app is closed (used by the SMS background handler).
Future<void> oneShot(Map<String, dynamic> msg, {int waitMs = 500}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (prefs.getBool('connectionEnabled') == false) return;
  final token = prefs.getString('token') ?? '';
  final pin = prefs.getString('serverPin') ?? '';
  if (!strongPairingToken(token) || !validPin(pin)) return;
  final hosts = <String>{
    if (prefs.getString('host') != null) prefs.getString('host')!,
    ...(prefs.getStringList('addrs') ?? <String>[]),
  };
  for (final h in hosts) {
    try {
      final ch = IOWebSocketChannel.connect(
        secureEndpoint(h, '/', websocket: true),
        headers: {'x-token': token},
        customClient: pinnedClient(pin),
        connectTimeout: Duration(seconds: 3),
      );
      await ch.ready;
      ch.sink.add(
        jsonEncode({
          'type': 'hello',
          'v': secureProtocolVersion,
          'token': token,
        }),
      );
      ch.sink.add(jsonEncode(msg));
      await Future.delayed(Duration(milliseconds: waitMs));
      await ch.sink.close();
      return;
    } catch (_) {}
  }
}

void main() => runApp(PhoneLinkApp());

class PhoneLinkApp extends StatelessWidget {
  const PhoneLinkApp({super.key});
  @override
  Widget build(BuildContext context) => MediaQuery.fromView(
    view: View.of(context),
    child: Builder(
      builder: (context) {
        // Subscribe to system appearance changes even while the app stays open.
        MediaQuery.platformBrightnessOf(context);
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: phoneThemeMode,
          builder: (context, mode, _) => MaterialApp(
            title: 'PhoneLink',
            debugShowCheckedModeBanner: false,
            themeMode: mode,
            theme: phoneLinkTheme(),
            darkTheme: phoneLinkTheme(),
            builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
              value:
                  (phoneDarkMode
                          ? SystemUiOverlayStyle.light
                          : SystemUiOverlayStyle.dark)
                      .copyWith(
                        statusBarColor: Colors.transparent,
                        systemNavigationBarColor: canvas,
                      ),
              child: child!,
            ),
            home: const Home(),
          ),
        );
      },
    ),
  );
}

class Home extends StatefulWidget {
  const Home({super.key, this.initialize = true});
  final bool initialize;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  static const _share = MethodChannel('phonelink/share');
  final host = TextEditingController();
  final token = TextEditingController();
  final fingerprint = TextEditingController();
  String phoneCertificate = '', phonePrivateKey = '';
  final log = <String>[];
  int page = 0;
  List<String> addrs = [];
  IOWebSocketChannel? ch;
  Timer? retryTimer, deviceTimer;
  HttpServer? fileServer;
  bool fileServerStarting = false;
  int connectionGeneration = 0;
  bool notificationAccess = false;
  bool? connectionNotificationsEnabled;
  bool? _notifiedConnection;
  bool? storageAccess;
  bool openingStorageSettings = false;
  bool wantConnected = false, connected = false, connecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialize) _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    host.text = prefs.getString('host') ?? '';
    token.text = prefs.getString('token') ?? '';
    fingerprint.text = prefs.getString('serverPin') ?? '';
    phoneCertificate = prefs.getString('phoneCertificate') ?? '';
    phonePrivateKey = prefs.getString('phonePrivateKey') ?? '';
    addrs = prefs.getStringList('addrs') ?? [];
    phoneThemeMode.value = ThemeMode.values.firstWhere(
      (mode) => mode.name == prefs.getString('themeMode'),
      orElse: () => ThemeMode.system,
    );
    wantConnected = prefs.getBool('connectionEnabled') ?? true;
    if (!strongPairingToken(token.text) || !validPin(fingerprint.text)) {
      token.clear();
      wantConnected = false;
      await prefs.remove('token');
      await prefs.setBool('connectionEnabled', false);
    }
    if (!mounted) return;
    setState(() {});

    _share.setMethodCallHandler((call) async {
      if (call.method == 'notificationEvent' && call.arguments is Map) {
        await _sendMsg(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
    await _refreshNotificationAccess();
    await _refreshStorageAccess();
    final interactive =
        await _share.invokeMethod<bool>('activityAttached') ?? false;
    if (interactive) {
      await [Permission.sms, Permission.phone].request();
    }
    await _initNotification(interactive: interactive);
    await _refreshConnectionNotifications();
    _startFileServer();

    if (wantConnected &&
        token.text.isNotEmpty &&
        (host.text.isNotEmpty || addrs.isNotEmpty)) {
      wantConnected = true;
      _open();
    }
  }

  void _log(String s) {
    if (mounted) setState(() => log.insert(0, s));
  }

  // ---------------------------------------------------- notification ----
  Future<void> _initNotification({required bool interactive}) async {
    await notifs.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final a = notifs
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (interactive) await a?.requestNotificationsPermission();
    await _share.invokeMethod('startClipboardControls');
  }

  // --------------------------------------------------------- sending ----
  Future<void> _sendMsg(Map<String, dynamic> msg, {int waitMs = 500}) async {
    if (!wantConnected) return;
    if (connected && ch != null) {
      ch!.sink.add(jsonEncode(msg));
    } else {
      await oneShot(msg, waitMs: waitMs);
    }
  }

  Future<void> _sendHistory() async {
    try {
      final items = await _share.invokeMethod<List>('getSmsHistory') ?? [];
      if (!wantConnected || !connected) return;
      ch?.sink.add(jsonEncode({'type': 'sms_history', 'items': items}));
      _log('Sent ${items.length} recent messages');
    } catch (e) {
      _log('History failed: $e');
    }
  }

  // ------------------------------------------------------ connection ----
  Future<void> _pairFromQr() async {
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ScanPage()),
    );
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map;
      if (j['v'] != secureProtocolVersion ||
          !strongPairingToken('${j['t']}') ||
          !validPin('${j['p']}')) {
        throw const FormatException(
          'Update both apps and scan the new pairing code',
        );
      }
      final candidates = [for (final a in j['a'] as List) '$a'];
      if (candidates.isEmpty || candidates.length > 16) {
        throw const FormatException('Invalid local addresses');
      }
      connectionGeneration++;
      connecting = false;
      for (final address in candidates) {
        secureEndpoint(address, '/');
      }
      await fileServer?.close(force: true);
      fileServer = null;
      phoneCertificate = '';
      phonePrivateKey = '';
      addrs = candidates;
      fingerprint.text = '${j['p']}';
      token.text = '${j['t']}';
      host.text = addrs.isNotEmpty ? addrs.first : '';
      await _savePrefs();
      wantConnected = true;
      await (await SharedPreferences.getInstance()).setBool(
        'connectionEnabled',
        true,
      );
      _startFileServer();
      _open();
    } catch (_) {
      _log('Use the pairing code from the updated desktop app');
    }
  }

  Future<void> _manualConnect() async {
    if (!strongPairingToken(token.text.trim()) ||
        !validPin(fingerprint.text.trim())) {
      showFeedback(
        context,
        'Copy the new token and certificate fingerprint from your PC',
      );
      return;
    }
    try {
      secureEndpoint(host.text.trim(), '/');
    } catch (_) {
      showFeedback(context, 'Enter a local IPv4 address and port');
      return;
    }
    connectionGeneration++;
    connecting = false;
    await fileServer?.close(force: true);
    fileServer = null;
    phoneCertificate = '';
    phonePrivateKey = '';
    wantConnected = true;
    await (await SharedPreferences.getInstance()).setBool(
      'connectionEnabled',
      true,
    );
    addrs = [host.text.trim()];
    await _savePrefs();
    wantConnected = true;
    _startFileServer();
    _open();
  }

  Future<void> _disconnect() async {
    connectionGeneration++;
    connecting = false;
    wantConnected = false;
    retryTimer?.cancel();
    deviceTimer?.cancel();
    final socket = ch;
    ch = null;
    if (mounted) setState(() => connected = false);
    await (await SharedPreferences.getInstance()).setBool(
      'connectionEnabled',
      false,
    );
    await _notifyConnection(false);
    await fileServer?.close(force: true);
    fileServer = null;
    await socket?.sink.close();
    _log('Disconnected from PC');
  }

  Future<void> _reconnect() async {
    wantConnected = true;
    await (await SharedPreferences.getInstance()).setBool(
      'connectionEnabled',
      true,
    );
    if (mounted) setState(() {});
    _startFileServer();
    _open();
  }

  Future<void> _confirmForget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text('Forget this PC?'),
        content: Text('You will need to scan its QR code again to reconnect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Forget PC'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _forget();
  }

  Future<void> _forget() async {
    await _disconnect();
    wantConnected = false;
    retryTimer?.cancel();
    ch?.sink.close();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('host');
    await prefs.remove('token');
    await prefs.remove('addrs');
    await prefs.remove('serverPin');
    await prefs.remove('phoneCertificate');
    await prefs.remove('phonePrivateKey');
    phoneCertificate = '';
    phonePrivateKey = '';
    fingerprint.clear();
    setState(() {
      host.clear();
      token.clear();
      addrs = [];
      connected = false;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', host.text.trim());
    await prefs.setString('token', token.text.trim());
    await prefs.setString('serverPin', fingerprint.text.trim());
    await prefs.setString('phoneCertificate', phoneCertificate);
    await prefs.setString('phonePrivateKey', phonePrivateKey);
    await prefs.setStringList('addrs', addrs);
    await prefs.setString('themeMode', phoneThemeMode.value.name);
  }

  Future<void> _refreshNotificationAccess() async {
    try {
      final enabled =
          await _share.invokeMethod<bool>('notificationAccess') ?? false;
      if (mounted) setState(() => notificationAccess = enabled);
    } catch (_) {
      /* Older native builds have no listener yet. */
    }
  }

  Future<void> _refreshConnectionNotifications() async {
    try {
      final enabled = await _share.invokeMethod<bool>(
        'connectionNotificationsEnabled',
      );
      if (mounted) setState(() => connectionNotificationsEnabled = enabled);
    } on PlatformException {
      // Keep unknown status rather than implying notification permission is granted.
    } on MissingPluginException {
      // An older installed native build does not provide this status.
    }
  }

  Future<void> _openConnectionNotifications() async {
    try {
      await _share.invokeMethod('openConnectionNotifications');
    } on PlatformException {
      if (mounted) {
        showFeedback(
          context,
          'Open PhoneLink notifications in Android Settings',
        );
      }
    }
  }

  Future<void> _notifyConnection(bool value) async {
    if (_notifiedConnection == value) return;
    try {
      await _share.invokeMethod('connectionState', value);
      _notifiedConnection = value;
    } on PlatformException {
      // A notification failure must not interrupt the encrypted connection.
    } on MissingPluginException {
      // Requires the updated native app.
    }
  }

  Future<void> _openNotificationAccess() async {
    try {
      await _share.invokeMethod('openNotificationAccess');
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Fully rerun the Android app to load notification access settings',
        );
      }
    }
  }

  Future<void> _syncNotifications() async {
    if (!wantConnected || !connected || ch == null) return;
    try {
      final items = await _share.invokeMethod<List>('getNotifications') ?? [];
      if (wantConnected && connected && ch != null) {
        ch!.sink.add(
          jsonEncode({'type': 'notification_snapshot', 'items': items}),
        );
      }
    } catch (_) {
      /* Notification sharing requires the updated native app. */
    }
  }

  Future<Map<String, dynamic>> _deviceStatus() async {
    try {
      return Map<String, dynamic>.from({
        ...await _share.invokeMethod<Map>('deviceStatus') ?? {},
        'fileReady': fileServer != null,
      });
    } catch (_) {
      return {
        'name': 'Android phone',
        'network': 'Unavailable',
        'wifi': 'Unavailable',
        'statusSupported': false,
        'fileReady': fileServer != null,
      };
    }
  }

  Future<void> _sendDeviceStatus() async {
    if (!wantConnected || !connected || ch == null) return;
    final status = await _deviceStatus();
    if (mounted &&
        status['notificationAccess'] is bool &&
        notificationAccess != status['notificationAccess']) {
      setState(() => notificationAccess = status['notificationAccess'] == true);
    }
    if (wantConnected && connected && ch != null) {
      ch!.sink.add(jsonEncode({'type': 'device_status', 'device': status}));
    }
  }

  Future<void> _open() async {
    if (connecting) return;
    if (!strongPairingToken(token.text.trim()) ||
        !validPin(fingerprint.text.trim())) {
      _log('Security update: scan the new pairing code from your PC');
      return;
    }
    final generation = ++connectionGeneration;
    connecting = true;
    ch?.sink.close();
    final candidates = <String>{
      if (host.text.trim().isNotEmpty) host.text.trim(),
      ...addrs,
    };
    for (final a in candidates) {
      try {
        final c = IOWebSocketChannel.connect(
          secureEndpoint(a, '/', websocket: true),
          headers: {'x-token': token.text.trim()},
          customClient: pinnedClient(fingerprint.text.trim()),
          connectTimeout: Duration(seconds: 3),
        );
        await c.ready;
        if (!wantConnected || !mounted || generation != connectionGeneration) {
          await c.sink.close();
          if (generation == connectionGeneration) connecting = false;
          return;
        }
        final device = await _deviceStatus();
        if (!wantConnected || !mounted || generation != connectionGeneration) {
          await c.sink.close();
          if (generation == connectionGeneration) connecting = false;
          return;
        }
        c.sink.add(
          jsonEncode({
            'type': 'hello',
            'v': secureProtocolVersion,
            'token': token.text.trim(),
            'persistent': true,
            'name': device['name'] ?? 'Android phone',
            'device': device,
          }),
        );
        ch = c;
        host.text = a;
        await _savePrefs();
        if (mounted) setState(() => connected = true);
        _log('Connected to $a');
        c.stream.listen(
          (raw) async {
            if (!identical(ch, c) ||
                !wantConnected ||
                generation != connectionGeneration) {
              return;
            }
            final m = jsonDecode(raw as String);
            if (m['type'] == 'secure_identity') {
              final cert = m['certificate'] as String;
              final key = m['key'] as String;
              if (!validPin('${m['pin']}') ||
                  certificatePin(cert) != m['pin']) {
                return;
              }
              serverContext(
                cert,
                key,
              ); // Validate the complete identity before persisting it.
              phoneCertificate = cert;
              phonePrivateKey = key;
              await _savePrefs();
              await _startFileServer();
              if (!identical(ch, c) ||
                  !wantConnected ||
                  generation != connectionGeneration) {
                return;
              }
              await _notifyConnection(true);
              await _sendDeviceStatus();
            } else if (m['type'] == 'unpair') {
              await _forget();
            } else if (m['type'] == 'clip') {
              if (m['text'] is String) _receiveClipboard(m['text'] as String);
            } else if (m['type'] == 'req_status') {
              _sendDeviceStatus();
            } else if (m['type'] == 'req_notifications') {
              _syncNotifications();
            } else if (m['type'] == 'req_sms') {
              _sendHistory();
            }
          },
          onDone: () {
            if (identical(ch, c)) _dropped();
          },
          onError: (_) {
            if (identical(ch, c)) _dropped();
          },
        );
        deviceTimer?.cancel();
        _syncNotifications();
        deviceTimer = Timer.periodic(
          const Duration(seconds: 15),
          (_) => _sendDeviceStatus(),
        );
        connecting = false;
        return;
      } catch (_) {}
    }
    if (generation != connectionGeneration) return;
    connecting = false;
    _dropped();
  }

  void _dropped() {
    if (mounted) setState(() => connected = false);
    _notifyConnection(false);
    deviceTimer?.cancel();
    retryTimer?.cancel();
    if (wantConnected) retryTimer = Timer(Duration(seconds: 5), _open);
  }

  Future<void> _receiveClipboard(String text) async {
    try {
      final applied = await _share.invokeMethod<bool>('receiveClipboard', text);
      if (applied == true) {
        _log('Clipboard from PC');
      }
    } on PlatformException {
      // Locked/off-screen or unavailable clipboard updates are not queued.
    } on MissingPluginException {
      // Require the native lock check; never fall back to an unchecked write.
    }
  }

  // ----------------------------------------------------- file server ----
  Future<void> _startFileServer() async {
    if (!wantConnected ||
        fileServer != null ||
        fileServerStarting ||
        !strongPairingToken(token.text.trim()) ||
        phoneCertificate.isEmpty ||
        phonePrivateKey.isEmpty) {
      return;
    }
    fileServerStarting = true;
    try {
      fileServer = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        kFilePort,
        serverContext(phoneCertificate, phonePrivateKey),
      );
      if (!wantConnected) {
        await fileServer!.close(force: true);
        fileServer = null;
        return;
      }
      fileServer!.idleTimeout = const Duration(seconds: 15);
      final expectedToken = token.text.trim();
      fileServer!.listen((r) => serveFs(r, kPhoneRoot, expectedToken));
    } catch (e) {
      _log('File server: $e');
    } finally {
      fileServerStarting = false;
    }
  }

  Future<void> _refreshStorageAccess() async {
    try {
      final allowed = await _share.invokeMethod<bool>('storageAccess');
      if (mounted) setState(() => storageAccess = allowed == true);
    } on MissingPluginException {
      final allowed = await Permission.manageExternalStorage.isGranted;
      if (mounted) setState(() => storageAccess = allowed);
    } on PlatformException {
      if (mounted) setState(() => storageAccess = false);
    }
  }

  Future<void> _askStorage() async {
    if (openingStorageSettings) return;
    setState(() => openingStorageSettings = true);
    try {
      await _share.invokeMethod('openStorageAccess');
    } on MissingPluginException {
      await Permission.manageExternalStorage.request();
      if (!await Permission.manageExternalStorage.isGranted) {
        await openAppSettings();
      }
    } on PlatformException {
      if (mounted) showFeedback(context, 'Could not open storage settings');
    } finally {
      await _refreshStorageAccess();
      if (mounted) setState(() => openingStorageSettings = false);
    }
  }

  RemoteFs? _pcFs() =>
      (!wantConnected || host.text.trim().isEmpty || token.text.trim().isEmpty)
      ? null
      : RemoteFs(
          host.text.trim(),
          token.text.trim(),
          pin: fingerprint.text.trim(),
        );

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _refreshNotificationAccess();
      _refreshConnectionNotifications();
      _refreshStorageAccess();
      if (wantConnected && !connected) _open();
      if (connected) {
        _sendDeviceStatus();
        _syncNotifications();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    deviceTimer?.cancel();
    retryTimer?.cancel();
    ch?.sink.close();
    fileServer?.close(force: true);
    host.dispose();
    token.dispose();
    fingerprint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    body: SafeArea(
      bottom: false,
      child: IndexedStack(
        index: page,
        children: [
          _connectTab(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              60 +
                  MediaQuery.viewPaddingOf(
                    context,
                  ).bottom.clamp(20.0, double.infinity),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PageHeading(title: 'PC files'),
                Expanded(
                  child: PcFilesTab(
                    getFs: _pcFs,
                    connected: connected,
                    onPair: () => setState(() => page = 0),
                  ),
                ),
              ],
            ),
          ),
          _settingsTab(),
        ],
      ),
    ),
    bottomNavigationBar: PhoneNavigation(
      selectedIndex: page,
      onChanged: (index) => setState(() => page = index),
    ),
  );

  Widget _settingsTab() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
    children: [
      const PageHeading(title: 'Settings'),
      _settingsLabel('Appearance', first: true),
      Surface(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a theme',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'System follows your phone’s appearance',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final mode in ThemeMode.values) ...[
                  if (mode != ThemeMode.system) const SizedBox(width: 8),
                  Expanded(
                    child: ThemeChoice(
                      mode: mode,
                      selected: phoneThemeMode.value == mode,
                      onTap: () {
                        setState(() => phoneThemeMode.value = mode);
                        _savePrefs();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      _settingsLabel('Permissions'),
      Surface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ListTile(
              leading: AppIcon(Icons.notifications_none_rounded, size: 20),
              title: const Text('Notification access'),
              subtitle: Text(notificationAccess ? 'Enabled' : 'Off'),
              trailing: AppIcon(Icons.chevron_right_rounded, size: 18),
              onTap: _openNotificationAccess,
            ),
            const Divider(indent: 48, endIndent: 16),
            ListTile(
              leading: AppIcon(Icons.notifications_active_outlined, size: 20),
              title: const Text('Connection notification'),
              subtitle: Text(
                connectionNotificationsEnabled == null
                    ? 'Checking permission…'
                    : connectionNotificationsEnabled!
                    ? 'Allowed'
                    : 'Off · tap to enable',
              ),
              trailing: AppIcon(Icons.chevron_right_rounded, size: 18),
              onTap: _openConnectionNotifications,
            ),
            const Divider(indent: 48, endIndent: 16),
            ListTile(
              leading: AppIcon(Icons.folder_outlined, size: 20),
              title: const Text('Phone storage access'),
              subtitle: Text(
                storageAccess == null
                    ? 'Checking access…'
                    : storageAccess!
                    ? 'Allowed · all phone files'
                    : 'Not allowed · tap to enable',
              ),
              trailing: AppIcon(Icons.chevron_right_rounded, size: 18),
              onTap: openingStorageSettings ? null : _askStorage,
            ),
          ],
        ),
      ),
      _settingsLabel('Connection'),
      _manualConnection(),
      if (token.text.isNotEmpty) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
            side: BorderSide(
              color: Theme.of(context).colorScheme.error.withValues(alpha: .5),
            ),
          ),
          onPressed: _confirmForget,
          icon: AppIcon(Icons.link_off_rounded, size: 18),
          label: const Text('Forget this PC'),
        ),
      ],
    ],
  );

  Widget _settingsLabel(String text, {bool first = false}) => Padding(
    padding: EdgeInsets.only(top: first ? 0 : 20, bottom: 8),
    child: Text(
      text,
      style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w500),
    ),
  );

  Widget _manualConnection() => Surface(
    padding: EdgeInsets.zero,
    child: ExpansionTile(
      trailing: AppIcon(Icons.expand_more_rounded, size: 20, color: muted),
      shape: Border(),
      collapsedShape: Border(),
      title: Text(
        'Connect manually',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      leading: AppIcon(Icons.tune_rounded, size: 20),
      childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'PC address',
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: host,
          autocorrect: false,
          decoration: InputDecoration(hintText: '192.168.1.5:8766'),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Pairing token',
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: token,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'Enter the token shown on your PC',
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'PC certificate fingerprint',
            style: TextStyle(fontSize: 13, color: muted),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: fingerprint,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'Copy the fingerprint from your PC',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _manualConnect,
            child: Text('Connect to PC'),
          ),
        ),
      ],
    ),
  );

  Widget _connectTab() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
    children: [
      const PageHeading(title: 'My devices'),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: phoneDarkMode ? surface : const Color(0xFF182D29),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: AppIcon(
                    Icons.laptop_rounded,
                    color: Color(0xFFD5E7D4),
                    size: 30,
                  ),
                ),
                const Spacer(),
                AppIcon(
                  connected ? Icons.link_rounded : Icons.link_off_rounded,
                  color: Color(0xFFA8C5B6),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              connected
                  ? 'Your PC is connected'
                  : token.text.isEmpty
                  ? 'Connect your PC'
                  : wantConnected
                  ? 'Finding your PC…'
                  : 'PC disconnected',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w600,
                letterSpacing: -.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              connected
                  ? host.text
                  : token.text.isEmpty
                  ? 'Scan the pairing code on your PC'
                  : wantConnected
                  ? 'Keep both devices on the same network. We’ll reconnect automatically.'
                  : 'Your pairing is saved. Reconnect whenever you’re ready.',
              style: TextStyle(color: Color(0xFFBDCEC6), height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: connected
                  ? OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFFB4AB),
                        side: const BorderSide(color: Color(0xFFFFB4AB)),
                      ),
                      onPressed: _disconnect,
                      icon: AppIcon(Icons.link_off_rounded, size: 20),
                      label: Text('Disconnect'),
                    )
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Color(0xFFD8EBCD),
                        foregroundColor: const Color(0xFF182D29),
                      ),
                      onPressed: token.text.isEmpty ? _pairFromQr : _reconnect,
                      icon: AppIcon(
                        token.text.isEmpty
                            ? Icons.qr_code_scanner_rounded
                            : Icons.link_rounded,
                        size: 20,
                      ),
                      label: Text(
                        token.text.isEmpty ? 'Scan PC code' : 'Reconnect',
                      ),
                    ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          const Text(
            'Recent activity',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const Spacer(),
          Text(
            '${log.length} events',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      const SizedBox(height: 12),
      Surface(
        padding: EdgeInsets.all(16),
        child: log.isEmpty
            ? Text(
                'Your connection and transfers will appear here.',
                style: TextStyle(color: muted, fontSize: 13),
              )
            : Column(
                children: [
                  for (final l in log.take(15))
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: AppIcon(
                              Icons.circle,
                              size: 6,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l,
                              style: TextStyle(fontSize: 13, color: muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    ],
  );
}

// ---------------------------------------------------------------- QR ----
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool done = false;
  String? cameraError;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Connect your PC'),
      leading: IconButton(
        tooltip: 'Back',
        onPressed: () => Navigator.pop(context),
        icon: AppIcon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              children: [
                Text(
                  'Scan your PC’s code',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.7,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Open Pair phone on your PC and place the code inside the frame',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, height: 1.6),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: cameraError != null
                    ? EmptyState(
                        icon: Icons.no_photography_outlined,
                        title: 'Camera unavailable',
                        message:
                            'Allow camera access in Android settings, or go back and connect manually.',
                      )
                    : ReaderWidget(
                        codeFormat: Format.qrCode,
                        flashOnIcon: AppIcon(
                          Icons.flash_on_rounded,
                          color: Colors.white,
                        ),
                        flashOffIcon: AppIcon(
                          Icons.flash_off_rounded,
                          color: Colors.white,
                        ),
                        showGallery: false,
                        showToggleCamera: false,
                        scanDelay: Duration(milliseconds: 250),
                        scanDelaySuccess: Duration(milliseconds: 500),
                        loading: Center(child: CircularProgressIndicator()),
                        onControllerCreated: (_, error) {
                          if (error != null && mounted) {
                            setState(() => cameraError = error.toString());
                          }
                        },
                        onScan: (code) {
                          final value = code.text;
                          if (code.isValid &&
                              value != null &&
                              value.isNotEmpty &&
                              !done &&
                              mounted) {
                            done = true;
                            Navigator.pop(context, value);
                          }
                        },
                      ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(Icons.wifi_rounded, size: 18, color: accent),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Use the same Wi-Fi or hotspot on both devices.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// --------------------------------------------------------- PC files ----
class PcFilesTab extends StatefulWidget {
  const PcFilesTab({
    super.key,
    required this.getFs,
    required this.connected,
    this.onPair,
  });
  final RemoteFs? Function() getFs;
  final bool connected;
  final VoidCallback? onPair;
  @override
  State<PcFilesTab> createState() => _PcFilesTabState();
}

class _PcFilesTabState extends State<PcFilesTab> {
  String path = '/';
  List<FEntry> items = [];
  bool busy = false;
  bool showHidden = false;
  String status = '';

  @override
  void initState() {
    super.initState();
    if (widget.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(PcFilesTab old) {
    super.didUpdateWidget(old);
    if (widget.connected && !old.connected) _load();
  }

  Future<void> _load([String? to]) async {
    final f = widget.getFs();
    if (f == null) return;
    final target = to ?? path;
    setState(() {
      busy = true;
      status = '';
    });
    try {
      final l = await f.list(target);
      if (!mounted) return;
      setState(() {
        items = l;
        path = target;
        busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        status = 'Cannot reach PC: $e';
      });
    }
  }

  Future<void> _download(FEntry e) async {
    final f = widget.getFs();
    if (f == null) return;
    setState(() {
      busy = true;
      status = 'Downloading ${e.name}...';
    });
    try {
      final dest = File(p.join(kDownloadDir, e.name));
      await f.download(p.posix.join(path, e.name), dest);
      status = 'Saved to Download/PhoneLink/${e.name}';
    } catch (err) {
      status = 'Download failed: $err (allow phone storage first)';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _upload() async {
    final f = widget.getFs();
    if (f == null) return;
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null) return;
    setState(() {
      busy = true;
      status = 'Uploading...';
    });
    try {
      for (final pf in r.files) {
        if (pf.path == null) continue;
        await f.upload(File(pf.path!), p.posix.join(path, pf.name));
      }
      status = 'Uploaded ${r.files.length} file(s) to PC:$path';
    } catch (err) {
      status = 'Upload failed: $err';
    }
    if (!mounted) return;
    setState(() => busy = false);
    _load();
  }

  @override
  Widget build(BuildContext context) => FileBrowser(
    device: 'PC',
    available: widget.getFs() != null,
    busy: busy,
    path: path,
    entries: showHidden
        ? items
        : items.where((entry) => !entry.name.startsWith('.')).toList(),
    showHidden: showHidden,
    onToggleHidden: () => setState(() => showHidden = !showHidden),
    status: status,
    onRefresh: () => _load(),
    onUpload: _upload,
    onUp: () => _load(p.posix.dirname(path)),
    onPair: widget.onPair,
    onOpen: (e) => e.isDir ? _load(p.posix.join(path, e.name)) : _download(e),
  );
}
