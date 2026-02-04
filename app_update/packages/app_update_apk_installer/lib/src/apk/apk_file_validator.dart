import 'dart:io';

import 'package:crypto/crypto.dart';

class ApkFileValidator {
  const ApkFileValidator();

  /// APK is a ZIP archive, so it must start with ZIP signatures "PK"
  Future<void> validateFormat(File file) async {
    final raf = await file.open();
    final header = await raf.read(16);
    await raf.close();

    if (header.length < 4) {
      throw const FormatException('Downloaded file is too small to be an APK');
    }

    final b0 = header[0];
    final b1 = header[1];
    final isZip = b0 == 0x50 && b1 == 0x4B; // PK
    if (!isZip) {
      throw const FormatException(
        'Downloaded file is not an APK (ZIP magic mismatch)',
      );
    }
  }

  Future<void> validateSha256(File file, String expectedHex) async {
    final normalized = expectedHex.toLowerCase();
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString().toLowerCase() != normalized) {
      throw const FormatException('SHA-256 checksum validation failed');
    }
  }
}
