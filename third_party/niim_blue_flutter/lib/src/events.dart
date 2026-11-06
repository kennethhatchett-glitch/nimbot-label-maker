import 'dart:async';

/// Event types emitted by the Bluetooth client
class ClientEvents {
  /// Fired after successful connection and negotiation
  static const String connected = 'connected';

  /// Fired on disconnect
  static const String disconnected = 'disconnected';

  /// Fired after packet sent (with packet object)
  static const String packetSent = 'packetSent';

  /// Fired after packet received and validated
  static const String packetReceived = 'packetReceived';

  /// Fired when raw bytes are sent
  static const String rawDataSent = 'rawDataSent';

  /// Fired when raw bytes are received
  static const String rawDataReceived = 'rawDataReceived';

  /// Fired when heartbeat data is parsed
  static const String heartbeat = 'heartbeat';

  /// Fired on heartbeat timeout/failure
  static const String heartbeatFailed = 'heartbeatFailed';

  /// Fired when printer info is retrieved
  static const String printerInfo = 'printerInfo';

  /// Fired on print status updates
  static const String printStatus = 'printStatus';

  /// Fired during firmware upload progress
  static const String firmwareProgress = 'firmwareProgress';
}

/// Firmware progress event
class FirmwareProgressEvent {
  final int current;
  final int total;

  FirmwareProgressEvent({
    required this.current,
    required this.total,
  });

  @override
  String toString() =>
      'FirmwareProgressEvent(current: $current, total: $total)';
}

/// Base class for event emitters using Dart Streams
class EventEmitter {
  final Map<String, StreamController<dynamic>> _controllers = {};
  final Map<String, Stream<dynamic>> _streams = {};

  /// Get stream for a specific event
  Stream<T> on<T>(String event) {
    if (!_streams.containsKey(event)) {
      _controllers[event] = StreamController<T>.broadcast();
      _streams[event] = _controllers[event]!.stream;
    }
    return _streams[event] as Stream<T>;
  }

  /// Emit an event with data
  void emit(String event, [dynamic data]) {
    if (_controllers.containsKey(event)) {
      _controllers[event]!.add(data);
    }
  }

  /// Check if there are listeners for an event
  bool hasListeners(String event) {
    return _controllers.containsKey(event) && _controllers[event]!.hasListener;
  }

  /// Dispose all stream controllers
  void dispose() {
    for (var controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
    _streams.clear();
  }
}
