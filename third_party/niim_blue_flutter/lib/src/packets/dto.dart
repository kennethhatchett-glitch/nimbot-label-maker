/// Data transfer objects for NIIMBOT printer communication
library;

import 'payloads.dart';

/// Print error with reason ID
class PrintError implements Exception {
  final String message;
  final int reasonId;

  PrintError(this.message, this.reasonId);

  @override
  String toString() => 'PrintError: $message (reasonId: $reasonId)';
}

/// Print density levels
enum PrintDensity {
  light(1),
  medium(2),
  dark(3);

  const PrintDensity(this.value);
  final int value;

  static PrintDensity fromValue(int value) {
    return PrintDensity.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PrintDensity.medium,
    );
  }
}

/// Print speed levels
enum PrintSpeed {
  slow(1),
  medium(2),
  fast(3);

  const PrintSpeed(this.value);
  final int value;

  static PrintSpeed fromValue(int value) {
    return PrintSpeed.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PrintSpeed.medium,
    );
  }
}

/// Printer information
class PrinterInfo {
  ConnectResult? connectResult;
  int? protocolVersion;
  int? modelId;
  String? serial;
  String? mac;
  BatteryChargeLevel? charge;
  AutoShutdownTime? autoShutdownTime;
  LabelType? labelType;
  String? softwareVersion;
  String? hardwareVersion;

  PrinterInfo({
    this.connectResult,
    this.protocolVersion,
    this.modelId,
    this.serial,
    this.mac,
    this.charge,
    this.autoShutdownTime,
    this.labelType,
    this.softwareVersion,
    this.hardwareVersion,
  });

  @override
  String toString() {
    return 'PrinterInfo(model: $modelId, serial: $serial, battery: $charge, version: $softwareVersion)';
  }
}

/// Print status
class PrintStatus {
  /// Page number (0 – n)
  final int page;

  /// Page print progress (0 – 100)
  final int pagePrintProgress;

  /// Page feed progress (0 – 100)
  final int pageFeedProgress;

  PrintStatus({
    required this.page,
    required this.pagePrintProgress,
    required this.pageFeedProgress,
  });

  @override
  String toString() {
    return 'PrintStatus(page: $page, print: $pagePrintProgress%, feed: $pageFeedProgress%)';
  }
}

/// RFID tag information
class RfidInfo {
  final bool tagPresent;
  final String uuid;
  final String barCode;
  final String serialNumber;
  final int allPaper;
  final int usedPaper;
  final LabelType consumablesType;
  final int? capacity;

  RfidInfo({
    required this.tagPresent,
    required this.uuid,
    required this.barCode,
    required this.serialNumber,
    required this.allPaper,
    required this.usedPaper,
    required this.consumablesType,
    this.capacity,
  });

  @override
  String toString() {
    return 'RfidInfo(present: $tagPresent, used: $usedPaper/$allPaper)';
  }
}

/// Heartbeat data from printer
class HeartbeatData {
  int paperState;
  int rfidReadState;
  bool lidClosed;
  BatteryChargeLevel powerLevel;

  HeartbeatData({
    required this.paperState,
    required this.rfidReadState,
    required this.lidClosed,
    required this.powerLevel,
  });

  @override
  String toString() {
    return 'HeartbeatData(paper: $paperState, battery: $powerLevel, lidClosed: $lidClosed)';
  }
}

/// Sound settings
class SoundSettings {
  final SoundSettingsType category;
  final SoundSettingsItemType item;
  final bool value;

  SoundSettings({
    required this.category,
    required this.item,
    required this.value,
  });
}

/// Printer status data
class PrinterStatusData {
  final int supportColor;
  final int protocolVersion;

  PrinterStatusData({
    required this.supportColor,
    required this.protocolVersion,
  });
}
