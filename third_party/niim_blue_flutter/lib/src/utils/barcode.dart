/// Barcode generation utilities for thermal printers
library;

class _EAN13BitPattern {
  final String a;
  final String b;
  final String c;

  const _EAN13BitPattern(this.a, this.b, this.c);
}

const Map<String, _EAN13BitPattern> _ean13BP = {
  '0': _EAN13BitPattern('0001101', '0100111', '1110010'),
  '1': _EAN13BitPattern('0011001', '0110011', '1100110'),
  '2': _EAN13BitPattern('0010011', '0011011', '1101100'),
  '3': _EAN13BitPattern('0111101', '0100001', '1000010'),
  '4': _EAN13BitPattern('0100011', '0011101', '1011100'),
  '5': _EAN13BitPattern('0110001', '0111001', '1001110'),
  '6': _EAN13BitPattern('0101111', '0000101', '1010000'),
  '7': _EAN13BitPattern('0111011', '0010001', '1000100'),
  '8': _EAN13BitPattern('0110111', '0001001', '1001000'),
  '9': _EAN13BitPattern('0001011', '0010111', '1110100'),
};

const Map<String, String> _ean13TableSwitchMask = {
  '0': 'AAAAAA',
  '1': 'AABABB',
  '2': 'AABBAB',
  '3': 'AABBBA',
  '4': 'ABAABB',
  '5': 'ABBAAB',
  '6': 'ABBBAA',
  '7': 'ABABAB',
  '8': 'ABABBA',
  '9': 'ABBABA',
};

/// Result of EAN13 barcode generation
class EAN13Result {
  final String text;
  final String bandcode;

  const EAN13Result(this.text, this.bandcode);
}

/// Convert 12 or 13 digit numbers to EAN13 barcode
///
/// Returns an EAN13 barcode as a string of 95 characters,
/// each character is either 0 or 1, representing a white or black stripe
EAN13Result ean13(String data) {
  if (data.length > 13) {
    throw ArgumentError('Data too long for EAN13');
  }
  if (data.length < 12) {
    data = data.padRight(12, '0');
  }
  // ignore: deprecated_member_use
  if (!RegExp(r'^\d+$').hasMatch(data)) {
    throw ArgumentError('Invalid character in EAN13');
  }

  // Calculate checksum
  int checksum = 0;
  for (int i = 0; i < 12; i++) {
    final digit = int.parse(data[i]);
    checksum += (i % 2 == 0 ? 1 : 3) * digit;
  }
  checksum = (10 - (checksum % 10)) % 10;

  if (data.length == 12) {
    data += checksum.toString();
  } else if (data.length == 13 && data[12] != checksum.toString()) {
    throw ArgumentError('Invalid checksum in EAN13');
  }

  final result = <String>[];

  result.add('101'); // Start
  // Left Side
  final tableSwitch = _ean13TableSwitchMask[data[0]]!;
  for (int i = 1; i < 7; i++) {
    final digit = data[i];
    final tab = tableSwitch[i - 1];
    final pattern = _ean13BP[digit]!;
    final coding = tab == 'A' ? pattern.a : pattern.b;
    result.add(coding);
  }
  result.add('01010'); // Center Guard
  // Right Side
  for (int i = 7; i < 13; i++) {
    final digit = data[i];
    final coding = _ean13BP[digit]!.c;
    result.add(coding);
  }
  result.add('101'); // Stop

  return EAN13Result(data, result.join());
}

// Code128 barcode

class _Code128BitPattern {
  final int ascii;
  final String code;

  const _Code128BitPattern(this.ascii, this.code);
}

const List<_Code128BitPattern> _code128BP = [
  _Code128BitPattern(32, '11011001100'),
  _Code128BitPattern(33, '11001101100'),
  _Code128BitPattern(34, '11001100110'),
  _Code128BitPattern(35, '10010011000'),
  _Code128BitPattern(36, '10001011100'),
  _Code128BitPattern(37, '10001001100'),
  _Code128BitPattern(38, '10011001000'),
  _Code128BitPattern(39, '10011000100'),
  _Code128BitPattern(40, '10001100100'),
  _Code128BitPattern(41, '11001001000'),
  _Code128BitPattern(42, '11001000100'),
  _Code128BitPattern(43, '11000100100'),
  _Code128BitPattern(44, '10110011100'),
  _Code128BitPattern(45, '10011011100'),
  _Code128BitPattern(46, '10011001110'),
  _Code128BitPattern(47, '10111001100'),
  _Code128BitPattern(48, '10011101100'),
  _Code128BitPattern(49, '10011100110'),
  _Code128BitPattern(50, '11001110010'),
  _Code128BitPattern(51, '11001011100'),
  _Code128BitPattern(52, '11001001110'),
  _Code128BitPattern(53, '11011100100'),
  _Code128BitPattern(54, '11001110100'),
  _Code128BitPattern(55, '11101101110'),
  _Code128BitPattern(56, '11101001100'),
  _Code128BitPattern(57, '11100101100'),
  _Code128BitPattern(58, '11100100110'),
  _Code128BitPattern(59, '11101100100'),
  _Code128BitPattern(60, '11100110100'),
  _Code128BitPattern(61, '11100110010'),
  _Code128BitPattern(62, '11011011000'),
  _Code128BitPattern(63, '11011000110'),
  _Code128BitPattern(64, '11000110110'),
  _Code128BitPattern(65, '10100011000'),
  _Code128BitPattern(66, '10001011000'),
  _Code128BitPattern(67, '10001000110'),
  _Code128BitPattern(68, '10110001000'),
  _Code128BitPattern(69, '10001101000'),
  _Code128BitPattern(70, '10001100010'),
  _Code128BitPattern(71, '11010001000'),
  _Code128BitPattern(72, '11000101000'),
  _Code128BitPattern(73, '11000100010'),
  _Code128BitPattern(74, '10110111000'),
  _Code128BitPattern(75, '10110001110'),
  _Code128BitPattern(76, '10001101110'),
  _Code128BitPattern(77, '10111011000'),
  _Code128BitPattern(78, '10111000110'),
  _Code128BitPattern(79, '10001110110'),
  _Code128BitPattern(80, '11101110110'),
  _Code128BitPattern(81, '11010001110'),
  _Code128BitPattern(82, '11000101110'),
  _Code128BitPattern(83, '11011101000'),
  _Code128BitPattern(84, '11011100010'),
  _Code128BitPattern(85, '11011101110'),
  _Code128BitPattern(86, '11101011000'),
  _Code128BitPattern(87, '11101000110'),
  _Code128BitPattern(88, '11100010110'),
  _Code128BitPattern(89, '11101101000'),
  _Code128BitPattern(90, '11101100010'),
  _Code128BitPattern(91, '11100011010'),
  _Code128BitPattern(92, '11101111010'),
  _Code128BitPattern(93, '11001000010'),
  _Code128BitPattern(94, '11110001010'),
  _Code128BitPattern(95, '10100110000'),
  _Code128BitPattern(96, '10100001100'),
  _Code128BitPattern(97, '10010110000'),
  _Code128BitPattern(98, '10010000110'),
  _Code128BitPattern(99, '10000101100'),
  _Code128BitPattern(100, '10000100110'),
  _Code128BitPattern(101, '10110010000'),
  _Code128BitPattern(102, '10110000100'),
  _Code128BitPattern(103, '10011010000'),
  _Code128BitPattern(104, '10011000010'),
  _Code128BitPattern(105, '10000110100'),
  _Code128BitPattern(106, '10000110010'),
  _Code128BitPattern(107, '11000010010'),
  _Code128BitPattern(108, '11001010000'),
  _Code128BitPattern(109, '11110111010'),
  _Code128BitPattern(110, '11000010100'),
  _Code128BitPattern(111, '10001111010'),
  _Code128BitPattern(112, '10100111100'),
  _Code128BitPattern(113, '10010111100'),
  _Code128BitPattern(114, '10010011110'),
  _Code128BitPattern(115, '10111100100'),
  _Code128BitPattern(116, '10011110100'),
  _Code128BitPattern(117, '10011110010'),
  _Code128BitPattern(118, '11110100100'),
  _Code128BitPattern(119, '11110010100'),
  _Code128BitPattern(120, '11110010010'),
  _Code128BitPattern(121, '11011011110'),
  _Code128BitPattern(122, '11011110110'),
  _Code128BitPattern(123, '11110110110'),
  _Code128BitPattern(124, '10101111000'),
  _Code128BitPattern(125, '10100011110'),
  _Code128BitPattern(126, '10001011110'),
  _Code128BitPattern(200, '10111101000'),
  _Code128BitPattern(201, '10111100010'),
  _Code128BitPattern(202, '11110101000'),
  _Code128BitPattern(203, '11110100010'),
  _Code128BitPattern(204, '10111011110'),
  _Code128BitPattern(205, '10111101110'),
  _Code128BitPattern(206, '11101011110'),
  _Code128BitPattern(207, '11110101110'),
  _Code128BitPattern(208, '11010000100'),
  _Code128BitPattern(209, '11010010000'),
  _Code128BitPattern(210, '11010011100'),
  _Code128BitPattern(211, '1100011101011'),
];

final Map<int, int> _code128AsciiToId = {
  for (var i = 0; i < _code128BP.length; i++) _code128BP[i].ascii: i,
};

/// Converts a string to Code128B barcode
///
/// Returns a string of Code128B barcode as a sequence of 0 and 1,
/// representing white and black stripes
String code128b(String data) {
  if (data.length > 229) {
    throw ArgumentError('Data too long for Code128B');
  }

  final result = <String>[];

  result.add(_code128BP[104].code); // Start Code B

  // Convert each character to Code128B
  int checksum = 104;
  for (int i = 0; i < data.length; i++) {
    final id = _code128AsciiToId[data.codeUnitAt(i)];
    if (id == null) {
      throw ArgumentError('Invalid character in Code128B');
    }
    result.add(_code128BP[id].code);
    checksum += (i + 1) * id;
  }

  result.add(_code128BP[checksum % 103].code); // Checksum
  result.add(_code128BP[106].code); // Stop

  return result.join();
}
