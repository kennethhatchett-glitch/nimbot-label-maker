import 'package:niim_blue_flutter/src/packets/dto.dart';
import 'package:niim_blue_flutter/src/packets/payloads.dart';

import '../printer_models.dart';
import 'abstract_print_task.dart';
import 'b1_print_task.dart';
import 'b21v1_print_task.dart';
import 'd110_print_task.dart';
import 'd110mv4_print_task.dart';
import 'old_d11_print_task.dart';

/// Model with protocol version
class ModelWithProtocol {
  final PrinterModel model;
  final int protocolVersion;

  const ModelWithProtocol(this.model, this.protocolVersion);
}

/// Print task name type
enum PrintTaskName {
  d11V1,
  d110,
  b1,
  b21V1,
  d110mV4,
}

/// Map print task names to models
final Map<PrintTaskName, List<dynamic>> modelPrintTasks = {
  PrintTaskName.d11V1: [PrinterModel.d11, PrinterModel.d11s],
  PrintTaskName.b21V1: [PrinterModel.b21, PrinterModel.b21L2b],
  PrintTaskName.d110: [
    PrinterModel.b21s,
    PrinterModel.b21sC2b,
    PrinterModel.d110,
    const ModelWithProtocol(PrinterModel.d11, 1),
    const ModelWithProtocol(PrinterModel.d11, 2),
  ],
  PrintTaskName.b1: [
    PrinterModel.d110M,
    PrinterModel.b1,
    PrinterModel.b21C2b,
    PrinterModel.m2H,
    PrinterModel.n1,
    PrinterModel.d101,
  ],
  PrintTaskName.d110mV4: [
    const ModelWithProtocol(PrinterModel.d110M, 4),
    PrinterModel.d11H,
    PrinterModel.b21Pro,
  ],
};

/// Search for appropriate print task based on model and protocol version
PrintTaskName? findPrintTask(PrinterModel model, [int? protocolVersion]) {
  // First, try to find exact match with protocol version
  if (protocolVersion != null) {
    for (final entry in modelPrintTasks.entries) {
      final taskName = entry.key;
      final models = entry.value;

      for (final item in models) {
        if (item is ModelWithProtocol &&
            item.model == model &&
            item.protocolVersion == protocolVersion) {
          return taskName;
        }
      }
    }
  }

  // If no exact match, try to find just by model
  for (final entry in modelPrintTasks.entries) {
    final taskName = entry.key;
    final models = entry.value;

    for (final item in models) {
      if (item is PrinterModel && item == model) {
        return taskName;
      } else if (item is ModelWithProtocol && item.model == model) {
        return taskName;
      }
    }
  }

  return null;
}

/// Create print task instance from name
AbstractPrintTask? newPrintTask(
  PrintTaskName taskName,
  dynamic abstraction, {
  int totalPages = 1,
  PrintDensity? density,
  LabelType? labelType,
}) {
  final options = PrintOptions(
    totalPages: totalPages,
    density: density?.value,
    labelType: labelType,
  );

  switch (taskName) {
    case PrintTaskName.d11V1:
      return OldD11PrintTask(abstraction, options);
    case PrintTaskName.d110:
      return D110PrintTask(abstraction, options);
    case PrintTaskName.b1:
      return B1PrintTask(abstraction, options);
    case PrintTaskName.b21V1:
      return B21V1PrintTask(abstraction, options);
    case PrintTaskName.d110mV4:
      return D110MV4PrintTask(abstraction, options);
  }
}
