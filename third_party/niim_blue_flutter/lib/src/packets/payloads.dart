/// Payload enums and types for NIIMBOT printer communication
library;

/// Printer information types
enum PrinterInfoType {
  density(1),
  speed(2),
  labelType(3),
  language(6),
  autoShutdownTime(7),
  printerModelId(8),
  softwareVersion(9),
  batteryChargeLevel(10),
  serialNumber(11),
  hardwareVersion(12),
  bluetoothAddress(13),
  printMode(14),
  area(15);

  const PrinterInfoType(this.value);
  final int value;

  static PrinterInfoType? fromValue(int value) {
    try {
      return PrinterInfoType.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return null;
    }
  }
}

/// Sound settings type
enum SoundSettingsType {
  setSound(0x01),
  getSoundState(0x02);

  const SoundSettingsType(this.value);
  final int value;
}

/// Sound settings item type
enum SoundSettingsItemType {
  bluetoothConnectionSound(0x01),
  powerSound(0x02);

  const SoundSettingsItemType(this.value);
  final int value;
}

/// Label types for printer
enum LabelType {
  invalid(0),
  withGaps(1),
  black(2),
  continuous(3),
  perforated(4),
  transparent(5),
  pvcTag(6),
  blackMarkGap(10),
  heatShrinkTube(11);

  const LabelType(this.value);
  final int value;

  static LabelType fromValue(int value) {
    return LabelType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => LabelType.invalid,
    );
  }
}

/// Heartbeat types
enum HeartbeatType {
  advanced1(1),
  basic(2),
  unknown(3),
  advanced2(4);

  const HeartbeatType(this.value);
  final int value;
}

/// Auto shutdown time
enum AutoShutdownTime {
  shutdownTime1(1), // Usually 15 minutes
  shutdownTime2(2), // Usually 30 minutes
  shutdownTime3(3), // May be 45 or 60 minutes
  shutdownTime4(4); // May be 60 minutes or never

  const AutoShutdownTime(this.value);
  final int value;

  static AutoShutdownTime fromValue(int value) {
    return AutoShutdownTime.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AutoShutdownTime.shutdownTime1,
    );
  }
}

/// Battery charge level
enum BatteryChargeLevel {
  charge0(0),
  charge25(1),
  charge50(2),
  charge75(3),
  charge100(4);

  const BatteryChargeLevel(this.value);
  final int value;

  static BatteryChargeLevel fromValue(int value) {
    return BatteryChargeLevel.values.firstWhere(
      (e) => e.value == value,
      orElse: () => BatteryChargeLevel.charge0,
    );
  }
}

/// Connection result codes
enum ConnectResult {
  disconnect(0),
  connected(1),
  connectedNew(2),
  connectedV3(3),
  firmwareErrors(90);

  const ConnectResult(this.value);
  final int value;

  static ConnectResult fromValue(int value) {
    return ConnectResult.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ConnectResult.disconnect,
    );
  }
}

/// Printer error codes
enum PrinterErrorCode {
  coverOpen(0x01),
  lackPaper(0x02),
  lowBattery(0x03),
  batteryException(0x04),
  userCancel(0x05),
  dataError(0x06),
  overheat(0x07),
  paperOutException(0x08),
  printerBusy(0x09),
  noPrinterHead(0x0a),
  temperatureLow(0x0b),
  printerHeadLoose(0x0c),
  noRibbon(0x0d),
  wrongRibbon(0x0e),
  usedRibbon(0x0f),
  wrongPaper(0x10),
  setPaperFail(0x11),
  setPrintModeFail(0x12),
  setPrintDensityFail(0x13),
  writeRfidFail(0x14),
  setMarginFail(0x15),
  communicationException(0x16),
  disconnect(0x17),
  canvasParameterError(0x18),
  rotationParameterException(0x19),
  jsonParameterException(0x1a),
  b3sAbnormalPaperOutput(0x1b),
  eCheckPaper(0x1c),
  rfidTagNotWritten(0x1d),
  setPrintDensityNoSupport(0x1e),
  setPrintModeNoSupport(0x1f),
  setPrintLabelMaterialError(0x20),
  setPrintLabelMaterialNoSupport(0x21),
  notSupportWrittenRfid(0x22),
  illegalPage(0x32),
  illegalRibbonPage(0x33),
  receiveDataTimeout(0x34),
  nonDedicatedRibbon(0x35);

  const PrinterErrorCode(this.value);
  final int value;

  static PrinterErrorCode? fromValue(int value) {
    try {
      return PrinterErrorCode.values.firstWhere((e) => e.value == value);
    } catch (e) {
      return null;
    }
  }

  String get description {
    switch (this) {
      case PrinterErrorCode.coverOpen:
        return 'Cover is open';
      case PrinterErrorCode.lackPaper:
        return 'No paper';
      case PrinterErrorCode.lowBattery:
        return 'Low battery';
      case PrinterErrorCode.batteryException:
        return 'Battery exception';
      case PrinterErrorCode.userCancel:
        return 'User cancelled';
      case PrinterErrorCode.dataError:
        return 'Data error';
      case PrinterErrorCode.overheat:
        return 'Printer overheated';
      case PrinterErrorCode.paperOutException:
        return 'Paper out exception';
      case PrinterErrorCode.printerBusy:
        return 'Printer is busy';
      case PrinterErrorCode.noPrinterHead:
        return 'No printer head detected';
      case PrinterErrorCode.temperatureLow:
        return 'Temperature too low';
      case PrinterErrorCode.printerHeadLoose:
        return 'Printer head is loose';
      case PrinterErrorCode.noRibbon:
        return 'No ribbon';
      case PrinterErrorCode.wrongRibbon:
        return 'Wrong ribbon';
      case PrinterErrorCode.usedRibbon:
        return 'Ribbon already used';
      case PrinterErrorCode.wrongPaper:
        return 'Wrong paper type';
      case PrinterErrorCode.disconnect:
        return 'Printer disconnected';
      default:
        return 'Printer error: ${value.toRadixString(16)}';
    }
  }
}
