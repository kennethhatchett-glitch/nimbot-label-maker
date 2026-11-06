import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'abstract_client.dart';
import '../packets/payloads.dart';
import '../events.dart';
import '../printer_models.dart';

/// Default BLE configuration for NIIMBOT printers
class BleDefaultConfiguration {
  static const List<String> services = ['e7810a71-73ae-499d-8c15-faa9aef0c3f2'];
  static final List<String> nameFilters = getAllModelPrefixes();
}

/// BLE client implementation for NIIMBOT printers
class NiimbotBluetoothClient extends NiimbotAbstractClient {
  static const int bluetoothStateCheckInterval = 100;
  static const int autoScanTimeout = 10000;
  static const int connectTimeout = 15000;
  static const int streamStabilizeDelay = 1000;
  static const int defaultScanTimeout = 5000;
  static const int defaultPacketInterval = 10;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  bool _isConnected = false;
  final Completer<void> _connectCompleter = Completer<void>();
  void Function()? _onDisconnectCallback;
  List<String> _serviceUuidFilter = BleDefaultConfiguration.services;

  @override
  Future<ConnectionInfo> connect() async {
    if (_device == null) {
      if (debug) print('No device set, starting auto-scan...');

      var state = await FlutterBluePlus.adapterState.first;
      while (state == BluetoothAdapterState.unknown) {
        await Future.delayed(
            const Duration(milliseconds: bluetoothStateCheckInterval));
        state = await FlutterBluePlus.adapterState.first;
      }

      if (debug) print('Bluetooth state: $state');
      if (state != BluetoothAdapterState.on) {
        throw Exception('Bluetooth is not powered on');
      }

      final devices = await listDevices(
          timeout: const Duration(milliseconds: autoScanTimeout));
      if (devices.isEmpty) {
        throw Exception('Device scan timeout or no device found');
      }

      if (debug) print('Found device: ${devices.first.platformName}');
      _device = devices.first;
    }

    if (_isConnected) {
      return ConnectionInfo(
        deviceName: _device!.platformName,
        result: ConnectResult.connected,
      );
    }

    try {
      await _device!.connect(
        timeout: const Duration(milliseconds: connectTimeout),
        autoConnect: false,
      );

      _connectionSubscription =
          _device!.connectionState.listen(_handleConnectionStateChange);

      final services = await _device!.discoverServices();

      final niimbotService = services.firstWhere(
        (s) =>
            s.uuid.toString().toLowerCase() ==
            BleDefaultConfiguration.services[0].toLowerCase(),
        orElse: () => throw Exception('NIIMBOT service not found'),
      );

      for (var char in niimbotService.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          _writeCharacteristic = char;
        }
        if (char.properties.notify) {
          _notifyCharacteristic = char;
        }
      }

      if (_writeCharacteristic == null) {
        throw Exception('Write characteristic not found');
      }
      if (_notifyCharacteristic == null) {
        throw Exception('Notify characteristic not found');
      }

      await _notifyCharacteristic!.setNotifyValue(true);
      if (debug) print('Notifications enabled');

      _notifySubscription =
          _notifyCharacteristic!.onValueReceived.listen(_handleNotification);
      if (debug) print('Notification listener attached');

      _isConnected = true;

      if (debug) print('Waiting for stream to stabilize...');
      await Future.delayed(const Duration(milliseconds: streamStabilizeDelay));

      if (!_connectCompleter.isCompleted) {
        _connectCompleter.complete();
      }

      if (debug) print('Monitoring started, negotiating...');

      try {
        await initialNegotiate();
        if (debug) print('Initial negotiate complete');

        await fetchPrinterInfo();
        if (debug) print('Printer info fetched successfully');
      } catch (e) {
        print('Warning: Failed to fetch printer info: $e');
      }

      final connectionInfo = ConnectionInfo(
        deviceName: _device!.platformName,
        result: info.connectResult ?? ConnectResult.disconnect,
      );
      emit(ClientEvents.connected, connectionInfo);
      return connectionInfo;
    } catch (e) {
      if (!_connectCompleter.isCompleted) {
        _connectCompleter.completeError(e);
      }
      final connectionInfo = ConnectionInfo(
        deviceName: _device?.platformName,
        result: ConnectResult.disconnect,
      );
      emit(ClientEvents.connected, connectionInfo);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected || _device == null) {
      return;
    }

    try {
      stopHeartbeat();

      await _notifySubscription?.cancel();
      _notifySubscription = null;

      await _connectionSubscription?.cancel();
      _connectionSubscription = null;

      await _device!.disconnect();

      _isConnected = false;
      _device = null;
      _writeCharacteristic = null;
      _notifyCharacteristic = null;

      emit(ClientEvents.disconnected, null);
    } catch (e) {
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('cancel') ||
          errorMsg.contains('disconnect') ||
          errorMsg.contains('not connected')) {
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> sendRaw(Uint8List data, {bool force = false}) async {
    if (!_isConnected || _writeCharacteristic == null) {
      throw Exception('Not connected');
    }

    try {
      if (_writeCharacteristic!.properties.write) {
        await _writeCharacteristic!.write(data, withoutResponse: false);
      } else {
        await _writeCharacteristic!.write(data, withoutResponse: true);
      }

      if (!force) {
        await Future.delayed(
            const Duration(milliseconds: defaultPacketInterval));
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get the service UUID filter
  List<String> getServiceUuidFilter() {
    return _serviceUuidFilter;
  }

  /// Set the service UUID filter
  void setServiceUuidFilter(List<String> ids) {
    _serviceUuidFilter = ids;
  }

  /// Set a callback to be invoked when disconnected
  void setOnDisconnect(void Function() callback) {
    _onDisconnectCallback = callback;
  }

  /// Set the Bluetooth device to connect to
  void setDevice(BluetoothDevice device) {
    _device = device;
  }

  /// Get the current device
  BluetoothDevice? getDevice() {
    return _device;
  }

  /// Check if currently connected
  @override
  bool isConnected() => _isConnected;

  /// Handle connection state changes
  void _handleConnectionStateChange(BluetoothConnectionState state) {
    if (state == BluetoothConnectionState.disconnected) {
      if (_isConnected) {
        _isConnected = false;
        emit(ClientEvents.disconnected, null);
        _onDisconnectCallback?.call();
      }
    }
  }

  /// Handle incoming notifications
  void _handleNotification(List<int> data) {
    if (data.isEmpty) return;

    // if (debug) {
    //   print('BLE notification received: ${data.length} bytes');
    // }

    try {
      final bytes = Uint8List.fromList(data);
      processRawPacket(bytes);
    } catch (e) {
      print('Notification error: $e');
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    super.dispose();
  }

  /// List available NIIMBOT printers
  static Future<List<BluetoothDevice>> listDevices({
    Duration timeout = const Duration(milliseconds: defaultScanTimeout),
  }) async {
    var state = await FlutterBluePlus.adapterState.first;
    while (state == BluetoothAdapterState.unknown) {
      await Future.delayed(
          const Duration(milliseconds: bluetoothStateCheckInterval));
      state = await FlutterBluePlus.adapterState.first;
    }

    if (state != BluetoothAdapterState.on) {
      throw Exception('Bluetooth is not powered on');
    }

    final List<BluetoothDevice> printers = [];
    final modelPrefixes = getAllModelPrefixes();

    final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (var result in results) {
        final name = result.device.platformName;
        if (name.isNotEmpty &&
            modelPrefixes.any((prefix) => name.startsWith(prefix))) {
          if (!printers.any((d) => d.remoteId == result.device.remoteId)) {
            printers.add(result.device);
          }
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: timeout);
    await Future.delayed(timeout);
    await scanSubscription.cancel();

    return printers;
  }

  /// List already connected NIIMBOT devices
  static Future<List<BluetoothDevice>> listConnectedDevices({
    List<String>? serviceUuidFilter,
  }) async {
    final connectedDevices = FlutterBluePlus.connectedDevices;
    final modelPrefixes = getAllModelPrefixes();

    return connectedDevices
        .where((device) => modelPrefixes
            .any((prefix) => device.platformName.startsWith(prefix)))
        .toList();
  }

  /// Check if Bluetooth is available and enabled
  static Future<bool> isBluetoothAvailable() async {
    try {
      final isAvailable = await FlutterBluePlus.isSupported;
      if (!isAvailable) return false;

      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      return false;
    }
  }
}
