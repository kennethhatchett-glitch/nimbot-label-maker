import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;

/// Print direction for thermal printers
enum PrintDirection {
  left,
  top;

  @override
  String toString() => name;
}

/// Image processing and encoding for thermal printers
class ImageEncoder {
  /// Convert image to monochrome bitmap with dithering
  static Uint8List toMonochrome(
    img.Image image, {
    int threshold = 128,
    bool dither = true,
  }) {
    final grayscale = img.grayscale(image);

    if (dither) {
      // Floyd-Steinberg dithering
      return _floydSteinbergDither(grayscale, threshold);
    } else {
      // Simple thresholding
      return _simpleThreshold(grayscale, threshold);
    }
  }

  /// Simple threshold conversion
  static Uint8List _simpleThreshold(img.Image image, int threshold) {
    final width = image.width;
    final height = image.height;
    final bytesPerRow = (width + 7) ~/ 8;
    final result = Uint8List(bytesPerRow * height);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final luminance = pixel.r.toInt();

        if (luminance < threshold) {
          final byteIndex = y * bytesPerRow + (x ~/ 8);
          final bitIndex = 7 - (x % 8);
          result[byteIndex] |= (1 << bitIndex);
        }
      }
    }

    return result;
  }

  /// Floyd-Steinberg dithering
  static Uint8List _floydSteinbergDither(img.Image image, int threshold) {
    final width = image.width;
    final height = image.height;
    final bytesPerRow = (width + 7) ~/ 8;
    final result = Uint8List(bytesPerRow * height);

    // Create working copy for error diffusion
    final pixels = List<List<int>>.generate(
      height,
      (y) => List<int>.generate(
        width,
        (x) => image.getPixel(x, y).r.toInt(),
      ),
    );

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final oldPixel = pixels[y][x];
        final newPixel = oldPixel < threshold ? 0 : 255;
        pixels[y][x] = newPixel;

        if (newPixel == 0) {
          final byteIndex = y * bytesPerRow + (x ~/ 8);
          final bitIndex = 7 - (x % 8);
          result[byteIndex] |= (1 << bitIndex);
        }

        // Distribute error
        final error = oldPixel - newPixel;
        if (x + 1 < width) {
          pixels[y][x + 1] = _clamp(pixels[y][x + 1] + (error * 7 ~/ 16));
        }
        if (y + 1 < height) {
          if (x > 0) {
            pixels[y + 1][x - 1] =
                _clamp(pixels[y + 1][x - 1] + (error * 3 ~/ 16));
          }
          pixels[y + 1][x] = _clamp(pixels[y + 1][x] + (error * 5 ~/ 16));
          if (x + 1 < width) {
            pixels[y + 1][x + 1] =
                _clamp(pixels[y + 1][x + 1] + (error * 1 ~/ 16));
          }
        }
      }
    }

    return result;
  }

  /// Clamp value to 0-255 range
  static int _clamp(int value) {
    if (value < 0) return 0;
    if (value > 255) return 255;
    return value;
  }

  /// RLE (Run-Length Encoding) compression for thermal printer
  static Uint8List compressRLE(Uint8List data) {
    if (data.isEmpty) return Uint8List(0);

    final result = <int>[];
    var i = 0;

    while (i < data.length) {
      final currentByte = data[i];
      var count = 1;

      // Count consecutive identical bytes (max 255)
      while (i + count < data.length &&
          data[i + count] == currentByte &&
          count < 255) {
        count++;
      }

      if (count > 2 || currentByte == 0xFF) {
        // Use RLE encoding: 0xFF + count + byte
        result.add(0xFF);
        result.add(count);
        result.add(currentByte);
      } else {
        // Direct copy
        for (var j = 0; j < count; j++) {
          result.add(currentByte);
        }
      }

      i += count;
    }

    return Uint8List.fromList(result);
  }

  /// Decompress RLE data
  static Uint8List decompressRLE(Uint8List data) {
    final result = <int>[];
    var i = 0;

    while (i < data.length) {
      if (data[i] == 0xFF && i + 2 < data.length) {
        final count = data[i + 1];
        final value = data[i + 2];
        for (var j = 0; j < count; j++) {
          result.add(value);
        }
        i += 3;
      } else {
        result.add(data[i]);
        i++;
      }
    }

    return Uint8List.fromList(result);
  }

  /// Rotate image 90 degrees clockwise
  static img.Image rotateImage(img.Image image, int degrees) {
    switch (degrees % 360) {
      case 90:
        return img.copyRotate(image, angle: 90);
      case 180:
        return img.copyRotate(image, angle: 180);
      case 270:
        return img.copyRotate(image, angle: 270);
      default:
        return image;
    }
  }

  /// Resize image to fit printer width while maintaining aspect ratio
  static img.Image resizeToFit(
    img.Image image, {
    required int maxWidth,
    int? maxHeight,
  }) {
    if (image.width <= maxWidth &&
        (maxHeight == null || image.height <= maxHeight)) {
      return image;
    }

    if (maxHeight == null) {
      return img.copyResize(image, width: maxWidth);
    }

    final widthRatio = maxWidth / image.width;
    final heightRatio = maxHeight / image.height;
    final ratio = widthRatio < heightRatio ? widthRatio : heightRatio;

    return img.copyResize(
      image,
      width: (image.width * ratio).round(),
      height: (image.height * ratio).round(),
    );
  }

  /// Convert Flutter Image to img.Image
  static Future<img.Image> fromFlutterImage(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw Exception('Failed to convert image to byte data');
    }

    final buffer = byteData.buffer.asUint8List();
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: buffer.buffer,
      order: img.ChannelOrder.rgba,
    );
  }

  /// Decode image from bytes
  static img.Image? decodeImage(Uint8List bytes) {
    return img.decodeImage(bytes);
  }

  /// Encode image to PNG
  static Uint8List encodePng(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Create empty bitmap of given size
  static Uint8List createEmptyBitmap(int width, int height) {
    final bytesPerRow = (width + 7) ~/ 8;
    return Uint8List(bytesPerRow * height);
  }

  /// Invert bitmap colors (black <-> white)
  static Uint8List invertBitmap(Uint8List bitmap) {
    final result = Uint8List(bitmap.length);
    for (var i = 0; i < bitmap.length; i++) {
      result[i] = ~bitmap[i] & 0xFF;
    }
    return result;
  }

  /// Crop image to specified rectangle
  static img.Image cropImage(
    img.Image image, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    return img.copyCrop(image, x: x, y: y, width: width, height: height);
  }

  /// Mirror image horizontally
  static img.Image mirrorImage(img.Image image) {
    return img.flipHorizontal(image);
  }

  /// Calculate bitmap size in bytes for given dimensions
  static int calculateBitmapSize(int width, int height) {
    final bytesPerRow = (width + 7) ~/ 8;
    return bytesPerRow * height;
  }

  /// Pack multiple images horizontally
  static img.Image packImagesHorizontal(List<img.Image> images) {
    if (images.isEmpty) {
      throw ArgumentError('Images list cannot be empty');
    }

    final totalWidth = images.fold<int>(0, (sum, img) => sum + img.width);
    final maxHeight =
        images.fold<int>(0, (max, img) => img.height > max ? img.height : max);

    final result = img.Image(width: totalWidth, height: maxHeight);
    var xOffset = 0;

    for (var image in images) {
      img.compositeImage(result, image, dstX: xOffset);
      xOffset += image.width;
    }

    return result;
  }

  /// Pack multiple images vertically
  static img.Image packImagesVertical(List<img.Image> images) {
    if (images.isEmpty) {
      throw ArgumentError('Images list cannot be empty');
    }

    final maxWidth =
        images.fold<int>(0, (max, img) => img.width > max ? img.width : max);
    final totalHeight = images.fold<int>(0, (sum, img) => sum + img.height);

    final result = img.Image(width: maxWidth, height: totalHeight);
    var yOffset = 0;

    for (var image in images) {
      img.compositeImage(result, image, dstY: yOffset);
      yOffset += image.height;
    }

    return result;
  }
}
