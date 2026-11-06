// Label Printer test app.
//
// One screen: connect to a NIIMBOT D110_M over Bluetooth, type some text,
// and print it on a 40 x 12 mm label. Status messages (including the
// messages sent to and received from the printer) are shown on screen so
// problems can be screenshotted.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:niim_blue_flutter/niim_blue_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

// Label settings that work with the D110_M (confirmed in NiimBlue).
const int labelLengthPx = 320; // 40 mm at 203 dpi (8 dots per mm)
const int labelWidthPx = 96; // 12 mm = the printer's 96-dot print head
const int printDensity = 3;

// How long to wait for the printer to answer each message.
const int replyTimeoutMs = 3000;

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
      PacketGenerator.printStart9b(1, pageColor: 0, quality: 1),
      replyTimeoutMs,
    );
  }
}

void main() {
  runApp(const LabelPrinterApp());
}

class LabelPrinterApp extends StatelessWidget {
  const LabelPrinterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Label Printer',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const HomeScreen(),
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
  final List<String> _log = [];
  final List<StreamSubscription> _packetLogSubs = [];
  NiimbotBluetoothClient? _client;
  bool _busy = false;

  bool get _connected => _client?.isConnected() ?? false;

  void _say(String message) {
    if (!mounted) return;
    setState(() => _log.insert(0, message));
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

  /// Show every message sent to / received from the printer
  /// (except the regular "are you still there?" heartbeat messages).
  void _startPacketLog(NiimbotBluetoothClient client) {
    _packetLogSubs.add(client.onPacketSent.listen((p) {
      if (!_isHeartbeat(p)) _say('  → sent: ${_describe(p)}');
    }));
    _packetLogSubs.add(client.onPacketReceived.listen((p) {
      if (!_isHeartbeat(p)) _say('  ← reply: ${_describe(p)}');
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
      _say('Closing the old connection...');
      try {
        old.stopHeartbeat();
        await old.disconnect();
      } catch (e) {
        _say('(Old connection close error, ignored: $e)');
      }
      // Give the printer a moment to notice.
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<bool> _askPermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return results.values.every((s) => s.isGranted);
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      if (!await _askPermissions()) {
        _say('Bluetooth permission was not allowed. '
            'Allow "Nearby devices" for this app in Android settings.');
        return;
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
        return;
      }
      final BluetoothDevice device = printers.first;
      _say('Found ${device.platformName}. Connecting...');

      final client = NiimbotBluetoothClient();
      client.setDevice(device);
      client.setOnDisconnect(() => _say('Printer disconnected.'));
      _startPacketLog(client);
      await client.connect();
      client.abstraction.setPacketTimeout(replyTimeoutMs);
      _client = client;

      // If the printer didn't tell us what it is, ask again (up to 2 times).
      for (var attempt = 1;
          attempt <= 2 && client.getModelMetadata() == null;
          attempt++) {
        _say('Printer details missing, asking again (try $attempt of 2)...');
        await Future.delayed(const Duration(seconds: 1));
        try {
          await client.initialNegotiate();
          await client.fetchPrinterInfo();
        } catch (e) {
          _say('Asking again failed: $e');
        }
      }

      final model = client.getModelMetadata()?.model.name ?? 'unknown';
      final task = client.getPrintTaskType()?.name ?? 'unknown';
      final protocol = client.info.protocolVersion?.toString() ?? '?';
      _say('Connected! Model: $model, print task: $task, '
          'protocol: $protocol');
    } catch (e) {
      _say('Connect error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final client = _client;
    if (client == null || !client.isConnected()) {
      _say('Not connected. Tap Connect first.');
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty) {
      _say('Type some text first.');
      return;
    }

    setState(() => _busy = true);
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
        const TextOptions(
          x: labelLengthPx ~/ 2,
          y: labelWidthPx ~/ 2,
          fontSize: 40,
          fontWeight: FontWeight.bold,
          align: HAlignment.center,
          vAlign: VAlignment.middle,
        ),
      );

      final task = NiimBlueStylePrintTask(
        client.abstraction,
        const PrintOptions(
          totalPages: 1,
          density: printDensity,
          labelType: LabelType.withGaps,
          statusTimeoutMs: 10000,
          pageTimeoutMs: 10000,
        ),
      );

      _say('Printing "$text"...');
      _say('Step 1: start');
      await task.printInit();
      _say('Step 2: send label picture');
      await task.printPage(page.toEncodedImage(), 1);
      _say('Step 3: wait for printer to finish');
      await task.waitForFinished();
      _say('Step 4: end');
      await task.printEnd();
      _say('Done printing.');
    } catch (e) {
      _say('Print error: $e');
    } finally {
      client.startHeartbeat();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final sub in _packetLogSubs) {
      sub.cancel();
    }
    _client?.disconnect();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Label Printer (test 3)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.bluetooth),
              label: Text(_connected ? 'Reconnect' : 'Connect to printer'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              decoration: const InputDecoration(
                labelText: 'Label text',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || !_connected ? null : _print,
              icon: const Icon(Icons.print),
              label: const Text('Print'),
            ),
            const SizedBox(height: 16),
            const Text('Status (newest first):'),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  children: [
                    for (final line in _log)
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
