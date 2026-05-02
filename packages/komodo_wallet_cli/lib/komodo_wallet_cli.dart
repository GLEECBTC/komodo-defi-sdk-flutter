import 'dart:io';

void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln('Usage: dart komodo_wallet_cli.dart <file_path>');
    exit(1);
  }

  String filePath = arguments[0];
  File file = File(filePath);

  if (!file.existsSync()) {
    stderr.writeln('Error: File not found.');
    exit(1);
  }

  String fileType = classifyFile(file);
  stdout.writeln('File type: $fileType');
}

String classifyFile(File file) {
  final List<int> bytes = file.readAsBytesSync();

  if (bytes.length < 4) {
    return 'Unknown file type';
  }

  final magicBytes = bytes.sublist(0, 4);

  if (_matchesMagicNumber(magicBytes, [0x7f, 0x45, 0x4c, 0x46])) {
    // ELF Header: Executable and Linkable Format for Unix-based systems
    return _classifyElf(bytes);
  } else if (_matchesMagicNumber(magicBytes, [0xca, 0xfe, 0xba, 0xbe]) ||
      _matchesMagicNumber(magicBytes, [0xcf, 0xfa, 0xed, 0xfe])) {
    // Mach-O Header: Used in macOS
    return 'Executable or Dynamic library (Mach-O)';
  } else if (_matchesMagicNumber(magicBytes, [0x4d, 0x5a])) {
    // PE Header: Portable Executable for Windows
    return 'Executable (PE)';
  }

  return 'Unknown file type';
}

String _classifyElf(List<int> bytes) {
  if (bytes.length < 18) {
    return 'Unknown ELF file type';
  }

  // e_type is located at byte 16 and 17 (little endian)
  int eType = bytes[16] + (bytes[17] << 8);

  switch (eType) {
    case 1:
      return 'Static library (ELF)';
    case 2:
      return 'Executable (ELF)';
    case 3:
      return 'Dynamic library (ELF)';
    default:
      return 'Unknown ELF file type';
  }
}

bool _matchesMagicNumber(List<int> bytes, List<int> magicNumber) {
  for (int i = 0; i < magicNumber.length; i++) {
    if (bytes[i] != magicNumber[i]) {
      return false;
    }
  }
  return true;
}
