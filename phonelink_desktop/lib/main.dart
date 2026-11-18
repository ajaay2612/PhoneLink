import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';

import 'fs_api.dart';
import 'secure_transport.dart';
import 'local_identity.dart';
import 'app_icon.dart';
import 'design.dart';
import 'local_file_picker.dart';
import 'recent_images.dart';
import 'otp.dart';
import 'desktop_clipboard.dart';

const int kPort = 8766; // websocket + PC file server
const int kFilePort = 8767; // phone file server
String get _home => Platform.environment['HOME'] ?? '.';
String get allDownloadsDir => '$_home/Downloads';
String get downloadDir => '$allDownloadsDir/PhoneLink';
File get _configurationFile => File('$_home/.config/phonelink/config.json');

Future<Map<String, dynamic>> _readConfiguration() async {
  try {
    return Map<String, dynamic>.from(
      jsonDecode(await _configurationFile.readAsString()),
    );
  } catch (_) {
    return {};
  }
}

Future<void> openPath(String path) async {
  try {
    await Process.start('xdg-open', [path]);
  } catch (_) {}
}

class Sms {
  Sms(this.date, this.from, this.code, this.body);
  final DateTime date;
  final String from, code, body;
  String get time {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${date.day}/${date.month} ${two(date.hour)}:${two(date.minute)}';
  }
}

class PhoneNotice {
  PhoneNotice(this.key, this.app, this.title, this.text, this.time);
  final String key, app, title, text;
  final int time;
  static PhoneNotice? parse(dynamic value) {
    if (value is! Map ||
        value['key'] is! String ||
        (value['key'] as String).isEmpty) {
      return null;
    }
    return PhoneNotice(
      value['key'] as String,
      '${value['app'] ?? value['package'] ?? 'App'}',
      '${value['title'] ?? ''}',
      '${value['text'] ?? ''}',
      value['time'] is int ? value['time'] as int : 0,
    );
  }
}

class Hub extends ChangeNotifier {
  Hub({Map<String, dynamic>? initialConfiguration})
    : _initialConfiguration = initialConfiguration;
  final Map<String, dynamic>? _initialConfiguration;
  Map<String, dynamic> cfg = {};
  String token = '';
  LocalIdentity? serverIdentity, phoneIdentity;
  String get serverPin => serverIdentity?.pin ?? '';
  String get phonePin => phoneIdentity?.pin ?? '';
  String phoneIp = '';
  String phoneName = 'Android phone';
  Map<String, dynamic> phoneStatus = {};
  final Map<String, PhoneNotice> notifications = {};
  List<PhoneNotice> get notificationItems =>
      notifications.values.toList()..sort((a, b) => b.time.compareTo(a.time));
  PhoneNotice displayNotification(PhoneNotice notice) {
    final hidden = '${notice.title} ${notice.text}'.toLowerCase();
    final isSms =
        notice.app.toLowerCase() == 'messages' ||
        notice.key.contains('com.google.android.apps.messaging') ||
        notice.key.contains('com.android.mms');
    if (!isSms ||
        notice.time <= 0 ||
        !hidden.contains('sensitive') ||
        !hidden.contains('hidden')) {
      return notice;
    }
    final time = DateTime.fromMillisecondsSinceEpoch(notice.time);
    final candidates = messages
        .where((sms) => sms.date.difference(time).inMilliseconds.abs() <= 30000)
        .toList();
    // A redacted notification has no sender to disambiguate nearby SMS.
    if (candidates.length != 1) return notice;
    final sms = candidates.single;
    return PhoneNotice(notice.key, notice.app, sms.from, sms.body, notice.time);
  }

  void clearNotifications() {
    notifications.clear();
    notifyListeners();
  }

  final List<PhoneNotice> activity = [];
  void recordActivity(String label, String text) {
    activity.insert(
      0,
      PhoneNotice('', label, '', text, DateTime.now().millisecondsSinceEpoch),
    );
    if (activity.length > 100) activity.removeLast();
    notifyListeners();
  }

  bool refreshingConnection = false;
  int refreshVersion = 0;
  Timer? _connectionRefreshTimer;
  HttpServer? _server;
  String shareRoot = _home;
  List<String> addresses = [];
  final Set<WebSocket> sockets = {};
  final List<Sms> messages = [];
  bool autoCopy = true;
  bool clipSync = true;
  String lastClip = '';
  int clipboardRevision = 0;
  int clipboardWrites = 0;
  final _clipboard = DesktopClipboard();
  String? error;
  Timer? _clipTimer;

  bool get connected => sockets.isNotEmpty;
  int? get listeningPort => _server?.port;
  File get _cfgFile => _configurationFile;

  void toggleTheme() {
    desktopDarkMode.value = !desktopDarkMode.value;
    cfg['darkMode'] = desktopDarkMode.value;
    _saveCfg();
    notifyListeners();
  }

  int unreadMessages = 0;
  bool messagesVisible = true;
  void viewMessages(bool visible) {
    messagesVisible = visible;
    if (visible) unreadMessages = 0;
  }

  void setAutoCopy(bool v) {
    autoCopy = v;
    cfg['autoCopy'] = v;
    _saveCfg();
    notifyListeners();
  }

  void setClipSync(bool v) {
    clipSync = v;
    cfg['clipSync'] = v;
    _saveCfg();
    notifyListeners();
  }

  Future<void> _loadCfg() async {
    cfg = _initialConfiguration == null
        ? await _readConfiguration()
        : Map<String, dynamic>.from(_initialConfiguration);
    final saved = cfg['token'];
    if (saved is String && strongPairingToken(saved)) {
      token = saved;
    } else {
      token = newSecret();
      cfg['token'] = token;
    }
    desktopDarkMode.value = cfg['darkMode'] == true;
    autoCopy = cfg['autoCopy'] != false;
    clipSync = cfg['clipSync'] != false;
    phoneIp = (cfg['phoneIp'] as String?) ?? '';
    phoneName = (cfg['phoneName'] as String?) ?? 'Android phone';
    shareRoot = (cfg['shareRoot'] as String?) ?? _home;
    await _saveCfg();
  }

  Future<bool> _saveCfg() async {
    File? temporary;
    try {
      await _cfgFile.parent.create(recursive: true);
      if ((await Process.run('chmod', [
            '700',
            _cfgFile.parent.path,
          ])).exitCode !=
          0) {
        throw StateError('Private directory unavailable');
      }
      temporary = File('${_cfgFile.path}.${newSecret()}.tmp');
      await temporary.create();
      if ((await Process.run('chmod', ['600', temporary.path])).exitCode != 0) {
        throw StateError('Private file unavailable');
      }
      await temporary.writeAsString(jsonEncode(cfg), flush: true);
      await temporary.rename(_cfgFile.path);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  bool resettingPairing = false;
  Future<void> resetPairing() async {
    if (resettingPairing) return;
    resettingPairing = true;
    notifyListeners();
    final previousConfig = Map<String, dynamic>.from(cfg);
    final previousToken = token;
    final previousIdentity = phoneIdentity;
    try {
      final name = 'phone-${newSecret().substring(0, 16)}';
      final replacement = await LocalIdentity.load(_cfgFile.parent, name);
      token = newSecret();
      phoneIdentity = replacement;
      cfg['token'] = token;
      cfg['phoneIdentityName'] = name;
      if (!await _saveCfg()) {
        cfg = previousConfig;
        token = previousToken;
        phoneIdentity = previousIdentity;
        throw StateError('Could not save new pairing credentials');
      }
      _broadcast({'type': 'unpair'});
      final active = sockets.toList();
      sockets.clear();
      for (final socket in active) {
        await socket.close(1000, 'Pairing reset');
      }
      phoneStatus = {};
      // Revoke in-flight authenticated HTTP transfers as well as event sockets.
      await _server?.close(force: true);
      _server = null;
      await _listenSecure();
      _connectionRefreshTimer?.cancel();
      refreshingConnection = false;
    } finally {
      resettingPairing = false;
      notifyListeners();
    }
  }

  Future<void> _listenSecure() async {
    final server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      kPort,
      serverIdentity!.context,
    );
    _server = server;
    server.idleTimeout = const Duration(seconds: 15);
    server.listen(_onRequest);
  }

  Future<void> start() async {
    await _loadCfg();
    try {
      serverIdentity = await LocalIdentity.load(_cfgFile.parent, 'desktop');
      final name = cfg['phoneIdentityName'];
      phoneIdentity = await LocalIdentity.load(
        _cfgFile.parent,
        name is String && RegExp(r'^phone(?:-[a-f0-9]{16})?$').hasMatch(name)
            ? name
            : 'phone',
      );
    } catch (_) {
      error = 'Secure setup failed. Install OpenSSL and restart Fonelink.';
      notifyListeners();
      return;
    }
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    addresses =
        [
          for (final i in ifaces)
            for (final a in i.addresses)
              if (!a.isLoopback && localAddress(a)) '${a.address}:$kPort',
        ]..sort((a, b) {
          int rank(String s) =>
              (s.startsWith('192.168.') || s.startsWith('10.')) ? 0 : 1;
          return rank(a).compareTo(rank(b));
        });
    try {
      await _listenSecure();
    } catch (e) {
      error = 'Could not listen on port $kPort: $e';
    }
    _clipTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _pollClip(),
    );
    notifyListeners();
  }

  // ---------------------------------------------------------- server ----
  Future<void> _onRequest(HttpRequest req) async {
    if (!authorizedRequest(req, token)) {
      req.response.statusCode = HttpStatus.unauthorized;
      req.response.persistentConnection = false;
      await req.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      await serveFs(
        req,
        shareRoot,
        token,
        blocked: [_cfgFile.parent.path],
        onTransfer: (sent, name) {
          recordActivity(sent ? 'File sent' : 'File received', name);
        },
      ); // PC files for the phone
      return;
    }
    final ws = await WebSocketTransformer.upgrade(
      req,
      compression: CompressionOptions.compressionOff,
    );
    ws.pingInterval = Duration(seconds: 15);
    final ip = req.connectionInfo?.remoteAddress.address ?? '';
    var authed = false;
    String? sessionToken;
    var persistent = false;

    Timer(Duration(seconds: 5), () {
      if (!authed) ws.close(1008, 'timeout');
    });

    ws.listen(
      (dynamic raw) {
        if (raw is! String || raw.length > 1024 * 1024) {
          ws.close(1009, 'Message too large');
          return;
        }
        Map? m;
        try {
          final d = jsonDecode(raw);
          if (d is Map) m = d;
        } catch (_) {}
        if (m == null) return;

        if (!authed) {
          if (m['type'] == 'hello' &&
              m['v'] == secureProtocolVersion &&
              tokenMatches(
                token,
                m['token'] is String ? m['token'] as String : null,
              )) {
            authed = true;
            sessionToken = token;
            persistent = m['persistent'] == true;
            if (persistent) {
              sockets.add(ws);
              if (m['name'] is String &&
                  (m['name'] as String).trim().isNotEmpty) {
                phoneName = (m['name'] as String).trim();
                cfg['phoneName'] = phoneName;
              }
              _updatePhoneStatus(m['device']);
              phoneIp = ip;
              cfg['phoneIp'] = ip;
              _saveCfg();
              ws.add(
                jsonEncode({
                  'type': 'secure_identity',
                  'certificate': phoneIdentity!.certificate,
                  'key': phoneIdentity!.privateKey,
                  'pin': phonePin,
                }),
              );
              ws.add(jsonEncode({'type': 'req_sms'}));
              notifyListeners();
            }
          } else {
            ws.close(1008, 'bad token');
          }
          return;
        }

        if (!tokenMatches(token, sessionToken)) {
          ws.close(1008, 'Pairing revoked');
          return;
        }
        switch (m['type']) {
          case 'notification':
            _acceptNotification(m['item']);
            notifyListeners();
            break;
          case 'notification_snapshot':
            if (m['items'] is List) {
              notifications.clear();
              for (final item in m['items'] as List) {
                _acceptNotification(item);
              }
              notifyListeners();
            }
            break;
          case 'notification_removed':
            if (notifications.remove(m['key']) != null) notifyListeners();
            break;
          case 'device_status':
            _updatePhoneStatus(m['device']);
            notifyListeners();
            break;
          case 'sms':
            _onLiveSms('${m['from'] ?? '?'}', '${m['body'] ?? ''}');
            break;
          case 'sms_history':
            final items = m['items'];
            if (items is List) {
              for (final e in items) {
                if (e is Map) {
                  final ms = e['date'];
                  final d = (ms is int && ms > 0)
                      ? DateTime.fromMillisecondsSinceEpoch(ms)
                      : DateTime.now();
                  _addSms('${e['from'] ?? '?'}', '${e['body'] ?? ''}', d);
                }
              }
              notifyListeners();
            }
            break;
          case 'clip':
            if (clipSync) {
              final text = '${m['text'] ?? ''}';
              setClip(text);
              if (text.isNotEmpty) recordActivity('Clipboard received', text);
            }
            break;
        }
      },
      onDone: () {
        if (persistent && sockets.remove(ws)) {
          notifyListeners();
        }
      },
      onError: (_) {
        if (persistent && sockets.remove(ws)) {
          notifyListeners();
        }
      },
    );
  }

  void _broadcast(Map<String, dynamic> msg) {
    final data = jsonEncode(msg);
    for (final s in sockets.toList()) {
      try {
        s.add(data);
      } catch (_) {
        sockets.remove(s);
      }
    }
  }

  void _acceptNotification(dynamic value) {
    final notice = PhoneNotice.parse(value);
    if (notice == null) return;
    notifications[notice.key] = notice;
    while (notifications.length > 50) {
      notifications.remove(notificationItems.last.key);
    }
  }

  void _updatePhoneStatus(dynamic value) {
    if (value is! Map) return;
    if (value['notificationAccess'] == false) notifications.clear();
    phoneStatus = {
      for (final key in [
        'name',
        'battery',
        'charging',
        'network',
        'wifi',
        'notificationAccess',
        'statusSupported',
        'fileReady',
      ])
        key: value[key],
    };
    if (value['name'] is String &&
        (value['name'] as String).trim().isNotEmpty) {
      phoneName = (value['name'] as String).trim();
      cfg['phoneName'] = phoneName;
      _saveCfg();
    }
    _connectionRefreshTimer?.cancel();
    refreshingConnection = false;
  }

  void refreshConnection() {
    if (!connected || refreshingConnection) return;
    refreshingConnection = true;
    refreshVersion++;
    _broadcast({'type': 'req_status'});
    _broadcast({'type': 'req_notifications'});
    requestSms();
    notifyListeners();
    _connectionRefreshTimer = Timer(Duration(seconds: 10), () {
      if (!refreshingConnection) return;
      refreshingConnection = false;
      final staleSockets = sockets.toList();
      sockets.clear();
      for (final socket in staleSockets) {
        socket.close(1001, 'Connection refresh timed out');
      }
      notifyListeners();
    });
  }

  void requestSms() => _broadcast({'type': 'req_sms'});

  // ------------------------------------------------------------- sms ----
  bool _addSms(String from, String body, DateTime date) {
    final dup = messages.any(
      (m) =>
          m.from == from &&
          m.body == body &&
          m.date.difference(date).inSeconds.abs() < 60,
    );
    if (dup) return false;
    final code = extractOtp(body);
    messages.add(Sms(date, from, code, body));
    messages.sort((a, b) => b.date.compareTo(a.date));
    if (messages.length > 300) messages.removeRange(300, messages.length);
    return true;
  }

  void _onLiveSms(String from, String body) {
    if (!_addSms(from, body, DateTime.now())) return;
    if (!messagesVisible) unreadMessages++;
    final code = extractOtp(body);
    if (code.isNotEmpty && autoCopy) setClip(code);
    Process.run('notify-send', [
      'SMS from $from',
      code.isNotEmpty ? code : body,
    ]).catchError((_) => ProcessResult(0, 1, '', ''));
    notifyListeners();
  }

  // ------------------------------------------------------- clipboard ----
  Future<void> setClip(String text, {bool syncToPhone = false}) async {
    clipboardRevision++;
    clipboardWrites++;
    lastClip = text;
    try {
      await _clipboard.writeText(text);
    } finally {
      clipboardWrites--;
    }
    if (syncToPhone && clipSync && connected && text.isNotEmpty) {
      _broadcast({'type': 'clip', 'text': text});
      recordActivity('Clipboard sent', text);
    }
    notifyListeners();
  }

  Future<void> _pollClip() async {
    if (!clipSync || !connected) return;
    await sendClip(force: false);
  }

  Future<void> sendClip({required bool force}) async {
    if (!connected || clipboardWrites > 0) return;
    final revision = clipboardRevision;
    final copiedText = await _clipboard.readText();
    if (!connected || clipboardWrites > 0 || revision != clipboardRevision) {
      return;
    }
    final text = copiedText ?? '';
    if (text.isNotEmpty && (force || text != lastClip)) {
      lastClip = text;
      _broadcast({'type': 'clip', 'text': text});
      recordActivity('Clipboard sent', text);
      notifyListeners();
    }
  }

  // ------------------------------------------------------ usb (mtp) ----
  Future<String> mountUsb() async {
    try {
      final out = (await Process.run('gio', ['mount', '-l'])).stdout.toString();
      final m = RegExp(r'(mtp://\S+)').firstMatch(out);
      if (m == null) {
        return 'Phone not found over USB. Set USB mode to "File transfer" '
            'and install gvfs-backends.';
      }
      await Process.run('gio', ['mount', m.group(1)!]);
      await Process.start('xdg-open', [m.group(1)!]);
      return 'Opened ${m.group(1)}';
    } on ProcessException {
      return 'gio not found. Run: sudo apt install gvfs-backends';
    }
  }

  @override
  void dispose() {
    _clipTimer?.cancel();
    _connectionRefreshTimer?.cancel();
    _server?.close(force: true);
    final activeSockets = sockets.toList();
    sockets.clear();
    for (final socket in activeSockets) {
      socket.close();
    }
    super.dispose();
  }
}

// ================================================================= UI ====
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = await _readConfiguration();
  desktopDarkMode.value = configuration['darkMode'] == true;
  runApp(PhoneLinkApp(initialConfiguration: configuration));
}

class PhoneLinkApp extends StatelessWidget {
  const PhoneLinkApp({super.key, this.hub, this.initialConfiguration});
  final Hub? hub;
  final Map<String, dynamic>? initialConfiguration;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: desktopDarkMode,
    builder: (context, dark, _) => MaterialApp(
      title: 'Fonelink',
      debugShowCheckedModeBanner: false,
      theme: phoneLinkTheme(),
      home: HomePage(hub: hub, initialConfiguration: initialConfiguration),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.hub, this.initialConfiguration});
  final Hub? hub;
  final Map<String, dynamic>? initialConfiguration;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Hub hub;
  int page = 0;
  String query = '';
  String? selectedSender;
  final search = TextEditingController();
  static const labels = ['Messages', 'Clipboard', 'Files'];
  @override
  void initState() {
    super.initState();
    hub = widget.hub ?? Hub(initialConfiguration: widget.initialConfiguration);
    if (widget.hub == null) hub.start();
  }

  @override
  void dispose() {
    search.dispose();
    if (widget.hub == null) hub.dispose();
    super.dispose();
  }

  Future<void> _copy(String value) async {
    await hub.setClip(value, syncToPhone: true);
    if (mounted) showFeedback(context, 'Copied to PC clipboard');
  }

  Future<void> _resetPairing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('Reset pairing?'),
        content: const Text(
          'The old credentials will stop working. Scan the new code on your phone to reconnect. Your home folder stays shared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset pairing'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await hub.resetPairing();
    } catch (_) {
      if (mounted) showFeedback(context, 'Could not reset pairing');
    }
  }

  Future<void> _showPairDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 820,
          height: 640,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 12, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pair phone',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Connect your Android phone to this PC',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close pairing',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: AppIcon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: ListenableBuilder(
                    listenable: hub,
                    builder: (context, _) => _pair(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: hub,
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final sidebar = bounds.maxWidth >= 900;
        final body = IndexedStack(
          index: page,
          children: [
            _messages(),
            _clipboard(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeading(
                  title: 'Files',
                  trailing: OutlinedButton.icon(
                    onPressed: () => openPath(downloadDir),
                    icon: AppIcon(Icons.download_rounded, size: 18),
                    label: Text('All downloads'),
                  ),
                ),
                Expanded(
                  child: FilesTab(hub: hub, onPair: _showPairDialog),
                ),
              ],
            ),
          ],
        );
        return Scaffold(
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sidebar)
                  Container(
                    width: 320,
                    decoration: BoxDecoration(
                      color: desktopDarkMode.value
                          ? const Color(0xFF1B1E20)
                          : const Color(0xFFE5E7E2),
                      border: Border(right: BorderSide(color: line)),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: _devicePanel(),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!sidebar)
                        Padding(
                          padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
                          child: Row(
                            children: [
                              const Spacer(),
                              ConnectionBadge(connected: hub.connected),
                            ],
                          ),
                        ),
                      Material(
                        color: desktopDarkMode.value
                            ? const Color(0xFF161819)
                            : const Color(0xFFFDFEFC),
                        child: Row(
                          children: [
                            Expanded(child: _navigation()),
                            if (!sidebar && !hub.connected)
                              IconButton(
                                tooltip: 'Pair phone',
                                onPressed: _showPairDialog,
                                icon: AppIcon(
                                  Icons.qr_code_scanner_rounded,
                                  size: 20,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Divider(height: 1, thickness: 1, color: line),
                      if (hub.error != null)
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: Surface(
                            child: Row(
                              children: [
                                AppIcon(
                                  Icons.error_outline_rounded,
                                  size: 18,
                                  color: accent,
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Text(hub.error!)),
                                TextButton(
                                  onPressed: _showPairDialog,
                                  child: Text('Details'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: Container(
                          key: ValueKey('content-panel'),
                          padding: const EdgeInsets.all(16),
                          child: body,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _navigation() => Row(
    key: const ValueKey('workspace-tabs'),
    children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Semantics(
                  selected: page == i,
                  button: true,
                  child: Tooltip(
                    message: labels[i],
                    child: Material(
                      color: Colors.transparent,
                      clipBehavior: Clip.hardEdge,
                      child: InkWell(
                        onTap: () => setState(() {
                          page = i;
                          hub.viewMessages(i == 0);
                        }),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 11),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: page == i ? accent : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(
                                [
                                  Icons.chat_bubble_outline_rounded,
                                  Icons.content_paste_rounded,
                                  Icons.folder_outlined,
                                ][i],
                                size: 19,
                                color: page == i ? accent : muted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: page == i
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: page == i ? ink : muted,
                                ),
                              ),
                              if (i == 0 && hub.unreadMessages > 0) ...[
                                const SizedBox(width: 7),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    hub.unreadMessages > 99
                                        ? '99+'
                                        : '${hub.unreadMessages}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: onAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(right: 16),
        child: IconButton(
          tooltip: desktopDarkMode.value
              ? 'Switch to light mode'
              : 'Switch to dark mode',
          onPressed: hub.toggleTheme,
          icon: AppIcon(Icons.brightness_6_outlined, size: 20, color: muted),
        ),
      ),
    ],
  );

  Widget _devicePanel() => LayoutBuilder(
    builder: (context, constraints) {
      final summary = _deviceSummary();
      final notices = _recentsPanel();
      if (constraints.maxHeight < 460) {
        return ListView(
          children: [
            summary,
            const SizedBox(height: 16),
            SizedBox(height: 280, child: notices),
          ],
        );
      }
      return Column(
        children: [
          summary,
          const SizedBox(height: 16),
          Expanded(child: notices),
        ],
      );
    },
  );

  Widget _deviceSummary() {
    final battery = hub.connected && hub.phoneStatus['battery'] is int
        ? hub.phoneStatus['battery'] as int
        : null;
    final pcPort = hub.listeningPort;
    final phoneFilesActive =
        hub.connected && hub.phoneStatus['fileReady'] == true;
    return Surface(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 60,
                height: 108,
                child: FittedBox(
                  child: PhoneMockup(
                    connected: hub.connected,
                    battery: battery,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hub.phoneName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hub.connected) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Tooltip(
                            message: hub.phoneStatus['charging'] == true
                                ? 'Charging'
                                : 'Battery',
                            child: PhoneBatteryIcon(level: battery),
                          ),
                          Text(
                            battery == null ? '—' : '$battery%',
                            style: TextStyle(fontSize: 13, color: muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      children: [
                        AppIcon(
                          Icons.circle,
                          size: 6,
                          color: hub.connected ? accent : muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hub.connected ? 'Connected' : 'Disconnected',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh connection',
                          onPressed: hub.connected && !hub.refreshingConnection
                              ? hub.refreshConnection
                              : null,
                          constraints: BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          padding: EdgeInsets.zero,
                          icon: hub.refreshingConnection
                              ? SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                  ),
                                )
                              : AppIcon(Icons.refresh_rounded, size: 19),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!hub.connected) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: Tooltip(
                message: 'Pair phone',
                child: OutlinedButton.icon(
                  onPressed: _showPairDialog,
                  icon: AppIcon(Icons.qr_code_scanner_rounded, size: 18),
                  label: Text('Pair phone'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              children: [
                _portStatus(
                  'This PC',
                  pcPort ?? kPort,
                  pcPort != null ? 'Listening' : 'Not listening',
                  'Encrypted messages, clipboard and PC files',
                ),
                const SizedBox(height: 6),
                _portStatus(
                  'Phone files',
                  kFilePort,
                  phoneFilesActive ? 'Listening' : 'Unavailable',
                  'On your phone; this port is not reserved on your PC',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _quickAction(
            Icons.content_paste_rounded,
            'Send PC clipboard',
            !hub.connected
                ? null
                : () async {
                    await hub.sendClip(force: true);
                    if (mounted) {
                      showFeedback(
                        context,
                        'Current PC clipboard sent to phone',
                      );
                    }
                  },
          ),
          _quickAction(
            Icons.download_rounded,
            'All downloads',
            () => openPath(downloadDir),
          ),
        ],
      ),
    );
  }

  Widget _portStatus(String device, int port, String status, String detail) =>
      Tooltip(
        message: detail,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$device · TCP $port',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ),
            Text(status, style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      );

  Widget _recentsPanel() {
    final recent = [
      ...hub.activity,
      ...hub.messages.map(
        (sms) => PhoneNotice(
          '',
          'Message · ${sms.from}',
          '',
          sms.body,
          sms.date.millisecondsSinceEpoch,
        ),
      ),
    ]..sort((a, b) => b.time.compareTo(a.time));
    final items = recent.take(30).toList();
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recents',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'No recent activity',
                    message: hub.connected
                        ? 'Messages and transfers will appear here.'
                        : 'Connect your phone to see recent activity.',
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final notice = items[index];
                      final date = DateTime.fromMillisecondsSinceEpoch(
                        notice.time,
                      );
                      final time = notice.time > 0
                          ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                          : '';
                      return InkWell(
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (dialogContext) => AppDialog(
                            title: Text(notice.app),
                            content: SingleChildScrollView(
                              child: SelectableText(
                                '${notice.title}\n\n${notice.text}',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text('Close'),
                              ),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: (desktopDarkMode.value
                                          ? Color(0xFF303334)
                                          : Color(0xFFEAF0E5)),
                                      shape: BoxShape.circle,
                                    ),
                                    child: AppIcon(
                                      notice.app.startsWith('Message')
                                          ? Icons.chat_bubble_outline_rounded
                                          : notice.app.startsWith('Clipboard')
                                          ? Icons.content_paste_rounded
                                          : Icons.insert_drive_file_outlined,
                                      size: 15,
                                      color: muted,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      notice.app,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    time,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                              if (notice.title.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  notice.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (notice.text.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  notice.text,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback? onTap) =>
      ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 4),
        minTileHeight: 40,
        minVerticalPadding: 0,
        dense: true,
        leading: AppIcon(icon, size: 20, color: muted),
        horizontalTitleGap: 12,
        title: Text(label, style: TextStyle(fontSize: 13)),
        trailing: AppIcon(Icons.arrow_outward_rounded, size: 14, color: muted),
        onTap: onTap,
        enabled: onTap != null,
      );

  Widget _messages() => LayoutBuilder(
    builder: (context, constraints) {
      final split = constraints.maxWidth >= 620;
      Sms? latestOtp;
      for (final message in hub.messages) {
        if (message.code.isNotEmpty &&
            (latestOtp == null || message.date.isAfter(latestOtp.date))) {
          latestOtp = message;
        }
      }
      final otp = latestOtp;
      final matches = hub.messages
          .where(
            (m) => '${m.from} ${m.body}'.toLowerCase().contains(
              query.toLowerCase(),
            ),
          )
          .toList();
      final latestBySender = <String, Sms>{};
      for (final message in matches) {
        latestBySender.putIfAbsent(message.from, () => message);
      }
      final senders = latestBySender.keys.toList();
      final selected = senders.contains(selectedSender)
          ? selectedSender
          : senders.firstOrNull;
      final list = Surface(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            PanelHeader(
              horizontalPadding: 16,
              child: TextField(
                controller: search,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(fontSize: 14, height: 1.4, color: ink),
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 40,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  hintText: 'Search messages',
                  prefixIcon: AppIcon(Icons.search_rounded, size: 18),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            search.clear();
                            setState(() => query = '');
                          },
                          icon: AppIcon(Icons.close_rounded, size: 18),
                        ),
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: senders.isEmpty
                  ? EmptyState(
                      icon: query.isEmpty
                          ? Icons.chat_bubble_outline_rounded
                          : Icons.search_off_rounded,
                      title: query.isEmpty
                          ? 'No messages yet'
                          : 'No matching messages',
                      message: query.isEmpty
                          ? 'Messages from your phone will appear here.'
                          : 'Try another sender, word or code.',
                      action: !hub.connected && query.isEmpty
                          ? TextButton(
                              onPressed: _showPairDialog,
                              child: Text('Pair your phone'),
                            )
                          : null,
                    )
                  : ListView.separated(
                      itemCount: senders.length,
                      separatorBuilder: (_, _) =>
                          const Divider(indent: 12, endIndent: 12),
                      itemBuilder: (context, index) {
                        final sender = senders[index];
                        final message = latestBySender[sender]!;
                        return Material(
                          color: split && selected == sender
                              ? selection
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() => selectedSender = sender);
                              if (!split) {
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => Dialog(
                                    insetPadding: EdgeInsets.all(20),
                                    child: SizedBox(
                                      width: 560,
                                      height: 600,
                                      child: ListenableBuilder(
                                        listenable: hub,
                                        builder: (context, _) => _conversation(
                                          sender,
                                          closeable: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: (desktopDarkMode.value
                                          ? Color(0xFF303334)
                                          : Color(0xFFEAF0E5)),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      sender.isEmpty
                                          ? '?'
                                          : sender.characters.first
                                                .toUpperCase(),
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sender,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          message.body,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          message.time,
                                          style: TextStyle(
                                            color: muted,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeading(
            title: 'Messages',
            trailing: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  'Auto-copy codes',
                  style: TextStyle(fontSize: 11, color: muted),
                ),
                AppSwitch(
                  value: hub.autoCopy,
                  onChanged: hub.setAutoCopy,
                  label: 'Auto-copy codes',
                ),
              ],
            ),
          ),
          if (otp != null) ...[
            Surface(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          otp.code,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${otp.from} · ${otp.time}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: muted.withValues(alpha: .8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _copy(otp.code),
                    icon: AppIcon(Icons.copy_rounded, size: 16),
                    label: Text('Copy code'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: split
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth * .36).clamp(280.0, 360.0),
                        child: list,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: selected == null
                            ? Surface(
                                child: EmptyState(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  title: 'Select a conversation',
                                  message:
                                      'Choose a sender to read their messages.',
                                ),
                              )
                            : _conversation(selected),
                      ),
                    ],
                  )
                : list,
          ),
        ],
      );
    },
  );

  Widget _conversation(String sender, {bool closeable = false}) {
    final messages = hub.messages
        .where((message) => message.from == sender)
        .toList();
    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelHeader(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    sender,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (closeable)
                  IconButton(
                    tooltip: 'Close conversation',
                    onPressed: () => Navigator.pop(context),
                    icon: AppIcon(Icons.close_rounded, size: 18),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                return Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: canvas,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            message.body,
                            style: TextStyle(fontSize: 13, height: 1.6),
                          ),
                          if (message.code.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  message.code,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => _copy(message.code),
                                  icon: AppIcon(Icons.copy_rounded, size: 16),
                                  label: Text('Copy code'),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                message.time,
                                style: TextStyle(color: muted, fontSize: 10),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                tooltip: 'Copy message',
                                onPressed: () => _copy(message.body),
                                constraints: BoxConstraints.tightFor(
                                  width: 28,
                                  height: 28,
                                ),
                                padding: EdgeInsets.zero,
                                icon: AppIcon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _clipboard() => ListView(
    children: [
      const PageHeading(title: 'Clipboard'),
      Surface(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: AppIcon(Icons.sync_rounded, size: 20),
          title: Text('Sync between devices'),
          subtitle: Text(
            'Automatically send new PC clipboard text to your phone.',
            style: TextStyle(fontSize: 12),
          ),
          trailing: AppSwitch(
            value: hub.clipSync,
            onChanged: hub.setClipSync,
            label: 'Sync between devices',
          ),
          onTap: () => hub.setClipSync(!hub.clipSync),
        ),
      ),
      const SizedBox(height: 20),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppIcon(Icons.content_paste_rounded, size: 18, color: accent),
                SizedBox(width: 10),
                Text(
                  'Last clipboard text',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    color: muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: 80),
              child: SelectableText(
                hub.lastClip.isEmpty
                    ? 'Copy some text to get started.'
                    : hub.lastClip,
                style: TextStyle(
                  fontSize: 18,
                  height: 1.7,
                  color: hub.lastClip.isEmpty ? muted : ink,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: !hub.connected
                    ? null
                    : () async {
                        await hub.sendClip(force: true);
                        if (mounted) {
                          showFeedback(
                            context,
                            'Current PC clipboard sent to phone',
                          );
                        }
                      },
                icon: AppIcon(Icons.arrow_forward_rounded, size: 18),
                label: Text('Send PC clipboard'),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _pair() => ListView(
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final qr = Surface(
            child: Column(
              children: [
                const SizedBox(height: 8),
                if (hub.token.isEmpty || hub.addresses.isEmpty)
                  const SizedBox(
                    height: 240,
                    width: 240,
                    child: EmptyState(
                      icon: Icons.wifi_off_rounded,
                      title: 'No network address',
                      message: 'Connect this PC to Wi-Fi or a hotspot to pair.',
                    ),
                  )
                else
                  QrImageView(
                    data: jsonEncode({
                      'v': secureProtocolVersion,
                      'a': hub.addresses,
                      't': hub.token,
                      'p': hub.serverPin,
                    }),
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                const SizedBox(height: 18),
                ConnectionBadge(
                  connected: hub.connected,
                  label: hub.connected
                      ? 'Device connected'
                      : 'Ready when you are',
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
          final instructions = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connect in three steps',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              _step(
                '01',
                'Join the same network',
                'Connect your phone and PC to the same Wi-Fi or hotspot.',
              ),
              _step(
                '02',
                'Open Fonelink on Android',
                'Tap “Scan PC code” on the My devices screen.',
              ),
              _step(
                '03',
                'Point, pair, done',
                'Scan this code. Your phone remembers this PC for next time.',
              ),
            ],
          );
          return constraints.maxWidth >= 680
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 320, child: qr),
                    const SizedBox(width: 40),
                    Expanded(child: instructions),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [qr, SizedBox(height: 28), instructions],
                );
        },
      ),
      const SizedBox(height: 28),
      Surface(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: ExpansionTile(
          trailing: AppIcon(Icons.expand_more_rounded, size: 20, color: muted),
          shape: Border(),
          collapsedShape: Border(),
          title: Text(
            'Manual connection',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Use these details if the camera is unavailable.',
            style: TextStyle(fontSize: 12),
          ),
          childrenPadding: EdgeInsets.fromLTRB(16, 4, 16, 20),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PC addresses',
              style: TextStyle(fontSize: 10, color: muted, letterSpacing: 0),
            ),
            const SizedBox(height: 6),
            SelectableText(
              hub.addresses.isEmpty
                  ? 'No address found'
                  : hub.addresses.join('\n'),
            ),
            const SizedBox(height: 16),
            Text(
              'Pairing token',
              style: TextStyle(fontSize: 10, color: muted, letterSpacing: 0),
            ),
            const SizedBox(height: 6),
            SelectableText(
              hub.token,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 16),
            Text(
              'PC certificate fingerprint',
              style: TextStyle(fontSize: 12, color: muted),
            ),
            const SizedBox(height: 6),
            SelectableText(
              hub.serverPin,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: hub.resettingPairing ? null : _resetPairing,
              child: Text(
                hub.resettingPairing ? 'Resetting…' : 'Reset pairing',
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _step(String number, String title, String body) => Padding(
    padding: EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: (desktopDarkMode.value
                ? Color(0xFF303334)
                : Color(0xFFE6EDE2)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            number,
            style: TextStyle(
              color: accent,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 5),
              Text(
                body,
                style: TextStyle(color: muted, fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------- files ----
class FilesTab extends StatefulWidget {
  const FilesTab({super.key, required this.hub, this.onPair});
  final VoidCallback? onPair;
  final Hub hub;
  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  String path = '/';
  List<FEntry> items = [];
  bool busy = false, _tried = false;
  bool showHidden = false;
  bool pickingFiles = false, sendingFiles = false;
  String status = '';
  List<RemoteImage> recentImages = [];
  bool loadingImages = false;
  String? imagesError;
  String? imageHost;
  int imageRequest = 0;
  int imagesRevision = 0;
  bool hasMoreImages = false;
  int nextImageOffset = 0;
  int seenRefreshVersion = 0;

  @override
  void initState() {
    super.initState();
    seenRefreshVersion = widget.hub.refreshVersion;
  }

  @override
  void didUpdateWidget(covariant FilesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (seenRefreshVersion != widget.hub.refreshVersion) {
      seenRefreshVersion = widget.hub.refreshVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && fs != null) _refreshFiles();
      });
    }
  }

  RemoteFs? get fs =>
      !widget.hub.connected ||
          widget.hub.phoneIp.isEmpty ||
          widget.hub.phoneStatus['fileReady'] != true
      ? null
      : RemoteFs(
          '${widget.hub.phoneIp}:$kFilePort',
          widget.hub.token,
          pin: widget.hub.phonePin,
          onTransfer: (sent, name) => widget.hub.recordActivity(
            sent ? 'File sent' : 'File received',
            name,
          ),
        );

  Future<void> _loadRecentImages({bool append = false}) async {
    final remote = fs;
    if (remote == null) return;
    if (append && (loadingImages || !hasMoreImages)) return;
    final request = ++imageRequest;
    final offset = append ? nextImageOffset : 0;
    if (!append) imagesRevision++;
    setState(() {
      loadingImages = true;
      imagesError = null;
    });
    try {
      final images = await remote.recentImages(offset: offset);
      if (mounted &&
          request == imageRequest &&
          fs?.hostPort == remote.hostPort) {
        setState(() {
          recentImages = append
              ? {
                  for (final image in recentImages) image.path: image,
                  for (final image in images) image.path: image,
                }.values.toList()
              : images;
          hasMoreImages = images.length == 64;
          nextImageOffset = offset + images.length;
        });
      }
    } catch (error) {
      if (mounted && request == imageRequest) {
        setState(() => imagesError = '$error');
      }
    } finally {
      if (mounted && request == imageRequest) {
        setState(() => loadingImages = false);
      }
    }
  }

  void _refreshFiles() {
    _load();
    _loadRecentImages();
  }

  Future<void> _downloadImage(RemoteImage image) async {
    final remote = fs;
    if (remote == null || busy) return;
    setState(() {
      busy = true;
      status = 'Saving ${image.name}…';
    });
    try {
      final destination = File(
        p.join(downloadDir, p.posix.basename(image.path)),
      );
      await remote.download(image.path, destination);
      if (mounted) setState(() => status = 'Saved to ${destination.path}');
    } catch (error) {
      if (mounted) setState(() => status = 'Download failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _load([String? to]) async {
    final f = fs;
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
        status =
            'Cannot reach phone storage: $e\n'
            'Open Fonelink on the phone and allow "All files access".';
      });
    }
  }

  Future<void> _download(FEntry e) async {
    final f = fs;
    if (f == null) return;
    setState(() {
      busy = true;
      status = 'Downloading ${e.name}...';
    });
    try {
      final dest = File(p.join(downloadDir, e.name));
      await f.download(p.posix.join(path, e.name), dest);
      if (!mounted) return;
      setState(() {
        busy = false;
        status = 'Saved to ${dest.path}';
      });
      openPath(dest.path);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        busy = false;
        status = 'Download failed: $err';
      });
    }
  }

  Future<void> _upload() async {
    if (pickingFiles || sendingFiles) {
      showFeedback(
        context,
        pickingFiles
            ? 'The file chooser is already open'
            : 'A file transfer is already in progress',
      );
      return;
    }
    final destination = path;
    pickingFiles = true;
    try {
      // Opening the chooser must not depend on a pending phone directory request.
      final List<File>? files;
      if (Platform.isLinux) {
        files = await pickLocalFiles(context, _home);
      } else {
        final result = await FilePicker.platform.pickFiles(allowMultiple: true);
        files = result?.files
            .where((file) => file.path != null)
            .map((file) => File(file.path!))
            .toList();
      }
      pickingFiles = false;
      if (!mounted || files == null || files.isEmpty) return;
      final remote = fs;
      if (remote == null) {
        showFeedback(context, 'Connect your phone before sending files');
        setState(() => status = 'Connect your phone before sending files');
        return;
      }
      final total = files.length;
      sendingFiles = true;
      setState(() {
        busy = true;
        status = 'Preparing $total file(s)…';
      });
      var sent = 0;
      for (final file in files) {
        if (!mounted) return;
        setState(
          () =>
              status = 'Sending ${p.basename(file.path)} (${sent + 1}/$total)…',
        );
        await remote.upload(
          file,
          p.posix.join(destination, p.basename(file.path)),
        );
        sent++;
      }
      if (!mounted) return;
      setState(() => status = 'Sent $sent file(s) to phone:$destination');
      try {
        final refreshed = await remote.list(destination);
        if (!mounted) return;
        setState(() {
          items = refreshed;
          path = destination;
        });
      } catch (error) {
        if (mounted) {
          setState(
            () => status = 'Sent $sent file(s). Folder refresh failed: $error',
          );
        }
      }
      _loadRecentImages();
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Could not send files: $error');
        showFeedback(context, 'Could not send files: $error');
      }
    } finally {
      pickingFiles = false;
      if (sendingFiles) {
        sendingFiles = false;
        if (mounted) setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = fs;
    if (remote == null) {
      if (imageHost != null) {
        imageRequest++;
        recentImages = [];
        imagesError = null;
        loadingImages = false;
      }
      _tried = false;
      imageHost = null;
    } else if (!_tried || imageHost != remote.hostPort) {
      imageRequest++;
      recentImages = [];
      imagesError = null;
      _tried = true;
      imageHost = remote.hostPort;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && fs?.hostPort == remote.hostPort) _refreshFiles();
      });
    }
    final browser = FileBrowser(
      device: 'phone',
      available: remote != null,
      busy: busy,
      path: path,
      entries: showHidden
          ? items
          : items.where((e) => !e.name.startsWith('.')).toList(),
      showHidden: showHidden,
      onToggleHidden: () => setState(() => showHidden = !showHidden),
      status: status,
      onRefresh: _refreshFiles,
      onUpload: _upload,
      onUp: () => _load(p.posix.dirname(path)),
      onPair: widget.onPair,
      onOpen: (entry) => entry.isDir
          ? _load(p.posix.join(path, entry.name))
          : _download(entry),
    );
    final gallery = RecentImagesPanel(
      fs: remote,
      images: recentImages,
      revision: imagesRevision,
      hasMore: hasMoreImages,
      onLoadMore: () => _loadRecentImages(append: true),
      loading: loadingImages,
      error: imagesError,
      onDownload: remote == null || busy ? null : _downloadImage,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: browser),
              const SizedBox(width: 16),
              Expanded(child: gallery),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: browser),
            const SizedBox(height: 16),
            Expanded(child: gallery),
          ],
        );
      },
    );
  }
}
