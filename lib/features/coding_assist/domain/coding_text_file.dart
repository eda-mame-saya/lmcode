import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// ワークスペース内テキストの読み取り（UTF-8 不正・BOM を許容）。
abstract final class CodingTextFile {
  static Future<String> read(File file) async {
    final bytes = await file.readAsBytes();
    return decode(bytes);
  }

  static String readSync(File file) => decode(file.readAsBytesSync());

  static String decode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    var offset = 0;
    // UTF-8 BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      offset = 3;
    } else if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _utf16(bytes, offset: 2, littleEndian: true);
    } else if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16(bytes, offset: 2, littleEndian: false);
    }
    return utf8.decode(
      offset == 0 ? bytes : bytes.sublist(offset),
      allowMalformed: true,
    );
  }

  static String _utf16(List<int> bytes, {required int offset, required bool littleEndian}) {
    final view = ByteData.sublistView(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      offset,
    );
    final codeUnits = <int>[];
    for (var i = 0; i + 1 < view.lengthInBytes; i += 2) {
      codeUnits.add(
        littleEndian ? view.getUint16(i, Endian.little) : view.getUint16(i, Endian.big),
      );
    }
    return String.fromCharCodes(codeUnits);
  }
}
