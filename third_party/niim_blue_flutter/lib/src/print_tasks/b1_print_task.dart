import 'abstract_print_task.dart';
import '../packets/packet_generator.dart';
import '../print_page.dart';

/// Print task for B1 printer model
class B1PrintTask extends AbstractPrintTask {
  B1PrintTask(super.abstraction, [super.options]);

  @override
  Future<void> printInit() {
    return abstraction.sendAll([
      PacketGenerator.setDensity(
        printOptions.density ?? PrintOptionsDefaults.density,
      ),
      PacketGenerator.setLabelType(
        (printOptions.labelType ?? PrintOptionsDefaults.labelType).value,
      ),
      PacketGenerator.printStart7b(
        printOptions.totalPages ?? PrintOptionsDefaults.totalPages,
      ),
    ]);
  }

  @override
  Future<void> printPage(EncodedImage image, [int quantity = 1]) {
    checkAddPage(quantity);

    return abstraction.sendAll(
      [
        PacketGenerator.pageStart(),
        PacketGenerator.setPageSize6b(image.rows, image.cols, quantity),
        ...PacketGenerator.writeImageData(
          image,
          options: ImagePacketsGenerateOptions(
            printheadPixels: printheadPixels(),
          ),
        ),
        PacketGenerator.pageEnd(),
      ],
      printOptions.pageTimeoutMs,
    );
  }

  @override
  Future<void> waitForFinished() {
    abstraction.setPacketTimeout(
      printOptions.statusTimeoutMs ?? PrintOptionsDefaults.statusTimeoutMs,
    );

    return abstraction
        .waitUntilPrintFinishedByStatusPoll(
          printOptions.totalPages ?? PrintOptionsDefaults.totalPages,
          printOptions.statusPollIntervalMs ??
              PrintOptionsDefaults.statusPollIntervalMs,
        )
        .whenComplete(() => abstraction.setDefaultPacketTimeout());
  }
}
