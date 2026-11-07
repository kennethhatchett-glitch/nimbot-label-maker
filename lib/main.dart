// Label Printer app.
//
// Prints labels on a NIIMBOT D110_M over Bluetooth (40 x 12 mm labels).
// Labels can be typed in the app, or sent by Claude through the
// "label-printer-bridge" connector: with "Listen for print jobs" on, the
// app checks the bridge every few seconds and prints whatever arrives.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:niim_blue_flutter/niim_blue_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Label settings that work with the D110_M (confirmed in NiimBlue).
const int labelLengthPx = 320; // 40 mm at 203 dpi (8 dots per mm)
const int labelWidthPx = 96; // 12 mm = the printer's 96-dot print head
const int printDensity = 3;

// Space to leave around the text, in dots.
const int marginPx = 8;
const int maxFontSize = 40;
const int minFontSize = 10;

// How long to wait for the printer to answer each message.
const int replyTimeoutMs = 3000;

// The Cloudflare bridge (connector) and how often to check it.
const String bridgeUrl = 'https://label-printer-bridge.kennethhatchett.workers.dev';
const Duration pollEvery = Duration(seconds: 3);
const String prefsKeyName = 'printer_key';

const List<String> monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// D110_M print steps, matching the order NiimBlue uses:
/// label type, then density, then "start printing".
/// Page sending and finishing are the same as the library's D110M_V4 task.
class NiimBlueStylePrintTask extends D110MV4PrintTask {
  NiimBlueStylePrintTask(super.abstraction, [super.options]);

  @override
  Future<void> printInit() async {
    await abstraction.send(
      PacketGenerator.setLabelType(LabelType.withGaps.value),
      replyTimeoutMs,
    );
    await abstraction.send(
      PacketGenerator.setDensity(printDensity),
      replyTimeoutMs,
    );
    await abstraction.send(
      PacketGenerator.printStart9b(
        printOptions.totalPages ?? 1,
        pageColor: 0,
        quality: 1,
      ),
      replyTimeoutMs,
    );
  }
}

/// Today's date, e.g. "Nov 7, 2026".
String todayText() {
  final now = DateTime.now();
  return '${monthNames[now.month - 1]} ${now.day}, ${now.year}';
}

/// Biggest bold font size at which [text] fits on the label.
int fitFontSize(String text) {
  const maxWidth = labelLengthPx - 2 * marginPx;
  const maxHeight = labelWidthPx - marginPx;
  for (var size = maxFontSize; size > minFontSize; size -= 2) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size.toDouble(), fontWeight: FontWeight.bold),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final fits = painter.width <= maxWidth && painter.height <= maxHeight;
    painter.dispose();
    if (fits) return size;
  }
  return minFontSize;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const LabelPrinterApp());
}

class LabelPrinterApp extends StatelessWidget {
  const LabelPrinterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'Label Printer',
        theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _text = TextEditingController(text: 'Hello');
  final TextEditingController _key = TextEditingController();
  final List<String> _log = [];
  final List<String> _details = [];
  final List<StreamSubscription> _packetLogSubs = [];
  NiimbotBluetoothClient? _client;
  String _printerName = '';
  bool _busy = false; // connecting or printing
  bool _showDetails = false;
  bool _hideKey = true;

  bool _listening = false;
  bool _checking = false;
  Timer? _pollTimer;

  bool get _connected => _client?.isConnected() ?? false;

  @override
  void initState() {
    super.initState();
    _loadKey();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'label_printer_listening',
        channelName: 'Listening for print jobs',
        channelDescription:
            'Shown while Label Printer is waiting for labels from Claude.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: true,
      ),
    );
  }

  Future<void> _loadKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefsKeyName);
      if (saved != null && mounted) setState(() => _key.text = saved);
    } catch (e) {
      _detail('Could not load saved password: $e');
    }
  }

  Future<void> _saveKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKeyName, _key.text.trim());
    } catch (e) {
      _detail('Could not save password: $e');
    }
  }

  /// A plain-English status message (always shown).
  void _say(String message) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, message);
      _details.insert(0, message);
      if (_log.length > 200) _log.removeLast();
      if (_details.length > 500) _details.removeLast();
    });
  }

  /// A technical message (only shown under "Show details").
  void _detail(String message) {
    if (!mounted) return;
    setState(() {
      _details.insert(0, message);
      if (_details.length > 500) _details.removeLast();
    });
  }

  /// Short description of a printer message, e.g. "setDensity 03".
  String _describe(NiimbotPacket p) {
    final cmd = p.command;
    final name = cmd is Enum ? cmd.name : cmd.toString();
    final data = p.data.isEmpty ? '' : ' ${Utils.bytesToHex(p.data)}';
    final shown = data.length > 40 ? '${data.substring(0, 40)}...' : data;
    return '$name$shown';
  }

  bool _isHeartbeat(NiimbotPacket p) {
    final cmd = p.command;
    final name = cmd is Enum ? cmd.name : cmd.toString();
    return name.toLowerCase().contains('heartbeat');
  }

  /// Record every message sent to / received from the printer
  /// (except the regular "are you still there?" heartbeat messages).
  void _startPacketLog(NiimbotBluetoothClient client) {
    _packetLogSubs.add(client.onPacketSent.listen((p) {
      if (!_isHeartbeat(p)) _detail('  → sent: ${_describe(p)}');
    }));
    _packetLogSubs.add(client.onPacketReceived.listen((p) {
      if (!_isHeartbeat(p)) _detail('  ← reply: ${_describe(p)}');
    }));
  }

  Future<void> _closeOldConnection() async {
    for (final sub in _packetLogSubs) {
      await sub.cancel();
    }
    _packetLogSubs.clear();
    final old = _client;
    _client = null;
    if (old != null) {
      _detail('Closing the old connection...');
      try {
        old.stopHeartbeat();
        await old.disconnect();
      } catch (e) {
        _detail('(Old connection close error, ignored: $e)');
      }
      // Give the printer a moment to notice.
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<bool> _askBluetoothPermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return results.values.every((s) => s.isGranted);
  }

  /// Connect button.
  Future<void> _connectPressed() async {
    setState(() => _busy = true);
    try {
      await _connect();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Connects to the printer. Returns true if connected.
  Future<bool> _connect() async {
    try {
      if (!await _askBluetoothPermissions()) {
        _say('Bluetooth permission was not allowed. '
            'Allow "Nearby devices" for this app in Android settings.');
        return false;
      }
      await _closeOldConnection();

      _say('Looking for the printer (about 5 seconds)...');
      final found = await NiimbotBluetoothClient.listDevices(
        timeout: const Duration(seconds: 5),
      );
      final printers =
          found.where((d) => d.platformName.startsWith('D110')).toList();
      if (printers.isEmpty) {
        _say('No D110 printer found. Is it turned on? '
            'Close the Niimbot app and NiimBlue, then try again.');
        return false;
      }
      final BluetoothDevice device = printers.first;
      _say('Found ${device.platformName}. Connecting...');

      final client = NiimbotBluetoothClient();
      client.setDevice(device);
      client.setOnDisconnect(() => _say('Printer disconnected.'));
      _printerName = device.platformName;
      _startPacketLog(client);
      await client.connect();
      client.abstraction.setPacketTimeout(replyTimeoutMs);
      _client = client;

      // If the printer didn't tell us what it is, ask again (up to 2 times).
      for (var attempt = 1;
          attempt <= 2 && client.getModelMetadata() == null;
          attempt++) {
        _detail('Printer details missing, asking again (try $attempt of 2)...');
        await Future.delayed(const Duration(seconds: 1));
        try {
          await client.initialNegotiate();
          await client.fetchPrinterInfo();
        } catch (e) {
          _detail('Asking again failed: $e');
        }
      }

      final model = client.getModelMetadata()?.model.name ?? 'unknown';
      final task = client.getPrintTaskType()?.name ?? 'unknown';
      final protocol = client.info.protocolVersion?.toString() ?? '?';
      _detail('Model: $model, print task: $task, protocol: $protocol');
      _say('Connected. Ready to print.');
      if (mounted) setState(() {});
      return true;
    } catch (e) {
      _say('Connect error: $e');
      return false;
    }
  }

  /// Print button.
  Future<void> _printPressed() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      _say('Type some text first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _printLabel(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prints [text] (connecting first if needed).
  /// Returns null if it worked, or an error message.
  Future<String?> _printLabel(String text, {int copies = 1}) async {
    if (!_connected) {
      _say('Not connected. Connecting first...');
      if (!await _connect()) return 'could not connect to the printer';
    }
    final client = _client!;

    client.stopHeartbeat();
    try {
      // Let any last heartbeat reply arrive before we start.
      await Future.delayed(const Duration(milliseconds: 500));

      // The D110_M's paper runs lengthwise, so draw the label sideways
      // (landscape) and let the library rotate it for the print head.
      final page = PrintPage(
        labelWidthPx,
        labelLengthPx,
        PageOrientation.landscape,
      );
      await page.addText(
        text,
        TextOptions(
          x: labelLengthPx ~/ 2,
          y: labelWidthPx ~/ 2,
          fontSize: fitFontSize(text),
          fontWeight: FontWeight.bold,
          align: HAlignment.center,
          vAlign: VAlignment.middle,
        ),
      );

      final task = NiimBlueStylePrintTask(
        client.abstraction,
        PrintOptions(
          totalPages: copies,
          density: printDensity,
          labelType: LabelType.withGaps,
          statusTimeoutMs: 10000,
          pageTimeoutMs: 10000,
        ),
      );

      final shown = text.replaceAll('\n', ' / ');
      _say(copies > 1
          ? 'Printing "$shown" ($copies copies)...'
          : 'Printing "$shown"...');
      _detail('Step 1: start');
      await task.printInit();
      _detail('Step 2: send label picture');
      await task.printPage(page.toEncodedImage(), copies);
      _detail('Step 3: wait for printer to finish');
      await task.waitForFinished();
      _detail('Step 4: end');
      await task.printEnd();
      _say('Done printing.');
      return null;
    } catch (e) {
      _say('Print error: $e');
      return e.toString();
    } finally {
      client.startHeartbeat();
    }
  }

  // ---------------------------------------------------------------------
  // Listening for print jobs from Claude (via the bridge)
  // ---------------------------------------------------------------------

  Future<void> _setListening(bool on) async {
    if (on) {
      final key = _key.text.trim();
      if (key.isEmpty) {
        _say('Type your printer password first.');
        return;
      }
      await _saveKey();

      // Android needs notification permission to show the
      // "Listening for print jobs" notification that keeps the app running.
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }

      try {
        if (!await FlutterForegroundTask.isRunningService) {
          final result = await FlutterForegroundTask.startService(
            serviceId: 110,
            notificationTitle: 'Label Printer',
            notificationText: 'Listening for print jobs',
          );
          if (result is ServiceRequestFailure) {
            _say('Could not start background listening (will still listen '
                'while the app is open): ${result.error}');
          }
        }
      } catch (e) {
        _say('Could not start background listening (will still listen '
            'while the app is open): $e');
      }

      setState(() => _listening = true);
      _say('Listening for print jobs from Claude.');
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(pollEvery, (_) => _checkForJobs());
      _checkForJobs();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      try {
        await FlutterForegroundTask.stopService();
      } catch (e) {
        _detail('Stop service error (ignored): $e');
      }
      setState(() => _listening = false);
      _say('Stopped listening for print jobs.');
    }
  }

  Future<void> _checkForJobs() async {
    if (!_listening || _checking || _busy) return;
    _checking = true;
    try {
      final key = Uri.encodeComponent(_key.text.trim());
      final res = await http
          .post(Uri.parse('$bridgeUrl/jobs/$key/claim'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 403) {
        _say('The printer password was not accepted. '
            'Check it and turn listening on again.');
        await _setListening(false);
        return;
      }
      if (res.statusCode != 200) {
        _detail('Bridge check failed: HTTP ${res.statusCode}');
        return;
      }
      final jobs = (jsonDecode(res.body)['jobs'] as List?) ?? [];
      for (final job in jobs) {
        await _runJob(job as Map<String, dynamic>, key);
      }
    } catch (e) {
      _detail('Bridge check error (will retry): $e');
    } finally {
      _checking = false;
    }
  }

  Future<void> _runJob(Map<String, dynamic> job, String key) async {
    var text = (job['text'] as String? ?? '').trim();
    if (job['addDate'] == true) {
      text = text.isEmpty ? todayText() : '$text\n${todayText()}';
    }
    final copies = ((job['copies'] as num?) ?? 1).toInt().clamp(1, 10);
    _say('📨 Label from Claude: "${text.replaceAll('\n', ' / ')}"');

    if (mounted) setState(() => _busy = true);
    String? error;
    try {
      error = text.isEmpty ? 'empty label text' : await _printLabel(text, copies: copies);
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    try {
      await http
          .post(
            Uri.parse('$bridgeUrl/jobs/$key/result'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': job['id'],
              'ok': error == null,
              'message': error ?? (copies > 1 ? '$copies copies' : ''),
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      _detail('Could not report result to bridge: $e');
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final sub in _packetLogSubs) {
      sub.cancel();
    }
    _client?.disconnect();
    _text.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Label Printer (test 5)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Big, clear connection status.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _connected
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _connected ? Icons.check_circle : Icons.bluetooth_disabled,
                    color: _connected ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connected
                          ? 'Connected to $_printerName'
                          : 'Not connected',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _connected
                ? OutlinedButton.icon(
                    onPressed: _busy ? null : _connectPressed,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reconnect'),
                  )
                : FilledButton.icon(
                    onPressed: _busy ? null : _connectPressed,
                    icon: const Icon(Icons.bluetooth),
                    label: const Text('Connect to printer'),
                  ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    decoration: const InputDecoration(
                      labelText: 'Label text',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _printPressed,
                  icon: const Icon(Icons.print),
                  label: const Text('Print'),
                ),
              ],
            ),
            const Divider(height: 28),
            // Print jobs from Claude.
            TextField(
              controller: _key,
              obscureText: _hideKey,
              enabled: !_listening,
              decoration: InputDecoration(
                labelText: 'Printer password (PRINTER_KEY)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_hideKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hideKey = !_hideKey),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Listen for print jobs from Claude'),
              subtitle: Text(_listening
                  ? 'On: labels from Claude print automatically'
                  : 'Off'),
              value: _listening,
              onChanged: (on) => _setListening(on),
            ),
            Row(
              children: [
                const Expanded(child: Text('Messages (newest first):')),
                TextButton(
                  onPressed: () =>
                      setState(() => _showDetails = !_showDetails),
                  child: Text(_showDetails ? 'Hide details' : 'Show details'),
                ),
              ],
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  children: [
                    for (final line in _showDetails ? _details : _log)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(line),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
