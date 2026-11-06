import '../client/abstract_client.dart';
import '../packets/abstraction.dart';
import '../packets/payloads.dart';
import '../print_page.dart';

/// Print options for print tasks
class PrintOptions {
  /// Printer label type
  final LabelType? labelType;

  /// Print density (default: 2)
  final int? density;

  /// How many pages will be printed (default: 1)
  final int? totalPages;

  /// Used in waitForFinished where status is received by polling (default: 300ms)
  final int? statusPollIntervalMs;

  /// Used in waitForFinished (default: 5000ms)
  final int? statusTimeoutMs;

  /// Used in printPage (default: 10000ms)
  final int? pageTimeoutMs;

  const PrintOptions({
    this.labelType,
    this.density,
    this.totalPages,
    this.statusPollIntervalMs,
    this.statusTimeoutMs,
    this.pageTimeoutMs,
  });
}

/// Default print options
/// Same as React Native: PrintOptionsDefaults
class PrintOptionsDefaults {
  static const labelType = LabelType.withGaps;
  static const density = 2;
  static const totalPages = 1;
  static const statusPollIntervalMs = 300;
  static const statusTimeoutMs = 5000; // Match React Native: 5_000ms
  static const pageTimeoutMs = 10000; // Match React Native: 10_000ms
}

/// Abstract base class for device-specific print tasks
/// Different printer models have different print algorithms
abstract class AbstractPrintTask {
  final Abstraction abstraction;
  final PrintOptions printOptions;
  int _pagesPrinted = 0;

  AbstractPrintTask(this.abstraction, [PrintOptions? options])
      : printOptions = options ?? const PrintOptions();

  /// Get client
  NiimbotAbstractClient get client => abstraction.getClient();

  /// Get printer's printhead resolution in pixels
  int printheadPixels() {
    return client.getModelMetadata()?.printheadPixels ?? 384;
  }

  /// Check and increment page counter
  void checkAddPage(int pages) {
    _pagesPrinted += pages;
    if (_pagesPrinted >
        (printOptions.totalPages ?? PrintOptionsDefaults.totalPages)) {
      throw Exception(
          'Trying to add more pages ($_pagesPrinted) than totalPages (${printOptions.totalPages ?? PrintOptionsDefaults.totalPages})');
    }
  }

  /// Initialize print job
  Future<void> printInit();

  /// Print a page with encoded image
  Future<void> printPage(EncodedImage image, [int quantity = 1]);

  /// Wait for print to finish
  Future<void> waitForFinished();

  /// End print, cleanup
  Future<bool> printEnd() {
    return abstraction.printEnd();
  }
}
