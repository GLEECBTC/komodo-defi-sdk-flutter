// TODO: This may be better suited to be moved to the UI package.

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;

final Set<String> _validMnemonicWords = {};
final Map<String, int> _wordToIndex = {};

const _validLengths = [12, 15, 18, 21, 24];

enum MnemonicFailedReason {
  empty,
  customNotSupportedForHd,
  customNotAllowed,
  invalidLength,
  invalidWord,
  invalidChecksum,
}

class MnemonicValidator {
  Future<void> init() async {
    if (_validMnemonicWords.isEmpty) {
      final wordlist = await rootBundle.loadString(
        'packages/komodo_defi_types/assets/bip-0039/english-wordlist.txt',
      );
      final words = wordlist.split('\n').map((w) => w.trim()).toList();
      _validMnemonicWords.addAll(words);

      // Build word-to-index mapping for BIP39 validation
      for (int i = 0; i < words.length; i++) {
        _wordToIndex[words[i]] = i;
      }
    }
  }

  MnemonicFailedReason? validateMnemonic(
    String input, {
    required bool isHd,
    int? minWordCount,
    int? maxWordCount,
    bool allowCustomSeed = false,
  }) {
    assert(
      _validMnemonicWords.isNotEmpty,
      'Mnemonic wordlist is not initialized. '
      'Call MnemonicValidator.init() first.',
    );

    final words = input.trim().split(' ');

    if (words.isEmpty) {
      return MnemonicFailedReason.empty;
    }

    if (minWordCount != null && words.length < minWordCount) {
      return MnemonicFailedReason.invalidLength;
    }

    if (maxWordCount != null && words.length > maxWordCount) {
      return MnemonicFailedReason.invalidLength;
    }

    // Get detailed validation error if any
    final detailedError = _getDetailedValidationError(input);

    // If no error, it's a valid BIP39 mnemonic
    if (detailedError == null) {
      return null;
    }

    // For specific errors, return them directly
    if (detailedError == MnemonicFailedReason.empty ||
        detailedError == MnemonicFailedReason.invalidLength) {
      return detailedError;
    }

    // For HD wallets, any BIP39 error means it's not supported
    if (isHd) {
      return MnemonicFailedReason.customNotSupportedForHd;
    }

    // For non-HD wallets, check if custom seeds are allowed
    if (!allowCustomSeed) {
      return MnemonicFailedReason.customNotAllowed;
    }

    // Custom seed is allowed, so return null (valid)
    return null;
  }

  bool validateBip39(String input) {
    assert(
      _validMnemonicWords.isNotEmpty,
      'Mnemonic wordlist is not initialized. '
      'Call MnemonicValidator.init() first.',
    );

    final inputWordsList = input.trim().split(' ');

    if (!_validLengths.contains(inputWordsList.length)) {
      return false;
    }

    if (inputWordsList.any(
      (element) => !_validMnemonicWords.contains(element),
    )) {
      return false;
    }

    // Validate checksum
    return _validateChecksum(inputWordsList);
  }

  /// Validates the BIP39 checksum for a given mnemonic
  bool _validateChecksum(List<String> words) {
    try {
      // Convert words to indices
      final indices = <int>[];
      for (final word in words) {
        final index = _wordToIndex[word];
        if (index == null) return false;
        indices.add(index);
      }

      // Convert indices to binary string (11 bits per word)
      final binaryString = indices
          .map((i) => i.toRadixString(2).padLeft(11, '0'))
          .join();

      // Calculate entropy and checksum lengths
      final totalBits = binaryString.length;
      final checksumBits = totalBits ~/ 33; // Checksum is 1 bit per 3 words
      final entropyBits = totalBits - checksumBits;

      // Extract entropy and checksum
      final entropyBinary = binaryString.substring(0, entropyBits);
      final checksumBinary = binaryString.substring(entropyBits);

      // Convert entropy to bytes
      final entropyBytes = _binaryToBytes(entropyBinary);

      // Calculate SHA256 hash of entropy
      final hash = sha256.convert(entropyBytes);
      final hashBits = _bytesToBinary(hash.bytes);

      // Extract first checksumBits from hash
      final calculatedChecksum = hashBits.substring(0, checksumBits);

      // Compare checksums
      return checksumBinary == calculatedChecksum;
    } catch (e) {
      return false;
    }
  }

  /// Converts a binary string to bytes
  Uint8List _binaryToBytes(String binary) {
    final bytes = <int>[];
    for (int i = 0; i < binary.length; i += 8) {
      final byte = binary.substring(i, i + 8);
      bytes.add(int.parse(byte, radix: 2));
    }
    return Uint8List.fromList(bytes);
  }

  /// Converts bytes to binary string
  String _bytesToBinary(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(2).padLeft(8, '0')).join();
  }

  /// Gets detailed validation error for a mnemonic
  MnemonicFailedReason? _getDetailedValidationError(String input) {
    final words = input.trim().split(' ');

    if (words.isEmpty || words.every((w) => w.isEmpty)) {
      return MnemonicFailedReason.empty;
    }

    if (!_validLengths.contains(words.length)) {
      return MnemonicFailedReason.invalidLength;
    }

    // Check for invalid words
    for (final word in words) {
      if (!_validMnemonicWords.contains(word)) {
        return MnemonicFailedReason.invalidWord;
      }
    }

    // Check checksum
    if (!_validateChecksum(words)) {
      return MnemonicFailedReason.invalidChecksum;
    }

    return null;
  }

  /// Checks if the wordlist has been initialized
  bool get isInitialized => _validMnemonicWords.isNotEmpty;

  /// Returns a set of BIP39 words that start with the given prefix.
  ///
  /// This method is useful for implementing autocomplete functionality
  /// when users are entering their seed phrase word by word.
  ///
  /// [prefix] - The prefix to search for (case-insensitive)
  /// [maxResults] - Maximum number of results to return (default: 10)
  ///
  /// Returns an empty set if the wordlist is not initialized or if no matches
  /// are found.
  ///
  /// Example:
  /// ```dart
  /// final validator = MnemonicValidator();
  /// await validator.init();
  /// final matches = validator.getAutocompleteMatches('aba');
  /// // Returns: {'abandon', 'ability', 'about'}
  /// ```
  Set<String> getAutocompleteMatches(String prefix, {int maxResults = 10}) {
    assert(
      _validMnemonicWords.isNotEmpty,
      'Mnemonic wordlist is not initialized. '
      'Call MnemonicValidator.init() first.',
    );

    if (prefix.isEmpty) {
      return {};
    }

    final lowerPrefix = prefix.toLowerCase().trim();
    final matches = <String>{};

    for (final word in _validMnemonicWords) {
      if (word.startsWith(lowerPrefix)) {
        matches.add(word);
        if (matches.length >= maxResults) {
          break;
        }
      }
    }

    return matches;
  }

  /// Returns all valid BIP39 words for reference.
  ///
  /// This can be useful for implementing custom autocomplete UIs.
  Set<String> getAllWords() {
    assert(
      _validMnemonicWords.isNotEmpty,
      'Mnemonic wordlist is not initialized. '
      'Call MnemonicValidator.init() first.',
    );

    return Set<String>.from(_validMnemonicWords);
  }
}
