// Label Printer test app.
//
// One screen: connect to a NIIMBOT D110_M over Bluetooth, type some text,
// and print it on a 40 x 12 mm label. Status messages are shown on screen
// so problems can be screenshotted.

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:niim_blue_flutter/niim_blue_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

// Label settings that work with the D110_M (confirmed in NiimBlue).
const int labelLengthPx = 320; // 40 mm at 203 dpi (8 dots per mm)
const int labelWidthPx = 96; // 12 mm = the printer's 96-dot print head
const int printDensity = 3;

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
  NiimbotBluetoothClient? _client;
  bool _busy = false;

  bool get _connected => _client?.isConnected() ?? false;

  void _say(String message) {
    setState(() => _log.insert(0, message));
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
      client.setOnDisconnect(() {
        if (mounted) _say('Printer disconnected.');
      });
      await client.connect();
      _client = client;

      final model = client.getModelMetadata()?.model.name ?? 'unknown';
      final task = client.getPrintTaskType()?.name ?? 'unknown';
      final protocol = client.info.protocolVersion?.toString() ?? '?';
      _say('Connected! Model: $model, print task: $task, '
          'protocol: $protocol');
      client.startHeartbeat();
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
    try {
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

      final options = PrintOptions(
        totalPages: 1,
        density: printDensity,
        labelType: LabelType.withGaps,
      );
      // Use the print task the library detects; fall back to D110M_V4,
      // which is the one that worked in NiimBlue.
      final task = client.createPrintTask(options) ??
          D110MV4PrintTask(client.abstraction, options);

      _say('Printing "$text"...');
      client.stopHeartbeat();
      await task.printInit();
      await task.printPage(page.toEncodedImage(), 1);
      await task.waitForFinished();
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
    _client?.disconnect();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Label Printer (test)')),
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
