import 'dart:ui';

// TODO? Add a getter for the ticker of the coin subclass if needed. But this
// may overlap with the protocol class, in which case it's not needed.
enum CoinSubClass {
  moonbeam,
  ftm20,
  arbitrum,
  base,
  @Deprecated('No longer active. Will be removed in the future.')
  slp,
  sia,
  qrc20,
  avx20,
  smartChain,
  moonriver,
  ethereumClassic,
  ubiq,
  bep20,
  matic,
  utxo,
  smartBch,
  erc20,
  tendermint,
  tendermintToken,
  krc20,
  ewt,
  hrc20,
  hecoChain,
  rskSmartBitcoin,
  grc20,
  zhtlc,
  unknown;

  static String _enumNameLower(CoinSubClass e) {
    // Normalize enum value to its lowercased name without the enum prefix
    return e.toString().split('.').last.toLowerCase();
  }

  // TODO: verify all the tickers.
  String get ticker {
    switch (this) {
      case CoinSubClass.moonbeam:
        return 'MOON';
      case CoinSubClass.ftm20:
        return 'FTM';
      case CoinSubClass.arbitrum:
        return 'ARB';
      case CoinSubClass.base:
        return 'BASE';
      // ignore: deprecated_member_use_from_same_package
      case CoinSubClass.slp:
        return 'SLP';
      case CoinSubClass.sia:
        return 'SIA';
      case CoinSubClass.qrc20:
        return 'QTUM';
      case CoinSubClass.avx20:
        return 'AVAX';
      case CoinSubClass.utxo:
        return 'UTXO';
      case CoinSubClass.smartChain:
        return 'SMART_CHAIN';
      case CoinSubClass.moonriver:
        return 'MOVR';
      case CoinSubClass.ethereumClassic:
        return 'ETC';
      case CoinSubClass.tendermintToken:
        return 'ATOM';
      case CoinSubClass.ubiq:
        return 'UBQ';
      case CoinSubClass.bep20:
        return 'BNB';
      case CoinSubClass.matic:
        return 'MATIC';
      case CoinSubClass.smartBch:
        return 'BCH';
      case CoinSubClass.erc20:
        return 'ETH';
      case CoinSubClass.tendermint:
        return 'TKN';
      case CoinSubClass.krc20:
        return 'KCS';
      case CoinSubClass.ewt:
        return 'EWT';
      case CoinSubClass.hrc20:
        return 'HT';
      case CoinSubClass.hecoChain:
        return 'HT';
      case CoinSubClass.rskSmartBitcoin:
        return 'RBTC';
      case CoinSubClass.grc20:
        return 'GLEEC';
      case CoinSubClass.zhtlc:
        return 'ARRR';
      case CoinSubClass.unknown:
        return 'UNKNOWN';
    }
  }

  String get iconTicker {
    switch (this) {
      case CoinSubClass.moonbeam:
        return 'GLMR';
      case CoinSubClass.ftm20:
        return 'FTM';
      case CoinSubClass.arbitrum:
        return 'ARB';
      case CoinSubClass.base:
        return 'BASE';
      // ignore: deprecated_member_use_from_same_package
      case CoinSubClass.slp:
        return 'SLP';
      case CoinSubClass.sia:
        return 'TSIA';
      case CoinSubClass.qrc20:
        return 'QTUM';
      case CoinSubClass.avx20:
        return 'AVAX';
      case CoinSubClass.utxo:
        return 'KMD';
      case CoinSubClass.smartChain: // Same icon as KMD
        return 'SMART_CHAIN';
      case CoinSubClass.moonriver:
        return 'MOVR';
      case CoinSubClass.ethereumClassic:
        return 'ETC';
      case CoinSubClass.tendermintToken:
        return 'ATOM';
      case CoinSubClass.ubiq:
        return 'UBQ';
      case CoinSubClass.bep20:
        return 'BNB';
      case CoinSubClass.matic:
        return 'MATIC';
      case CoinSubClass.smartBch:
        return 'BCH';
      case CoinSubClass.erc20:
        return 'ERC';
      case CoinSubClass.tendermint:
        return 'ATOM';
      case CoinSubClass.krc20:
        return 'KCS';
      case CoinSubClass.ewt:
        return 'EWT';
      case CoinSubClass.hrc20:
        return 'HT';
      case CoinSubClass.hecoChain:
        return 'HT';
      case CoinSubClass.rskSmartBitcoin:
        return 'RBTC';
      case CoinSubClass.grc20:
        return 'GLEEC';
      case CoinSubClass.zhtlc:
        return 'ARRR';
      case CoinSubClass.unknown:
        return '';
    }
  }

  /// Parse a string to a coin subclass.
  ///
  /// Attempts to match the string to a coin subclass with the following
  /// precedence:
  /// - Exact enum name match (highest priority)
  /// - Exact ticker match (with tie-breakers, e.g. 'UTXO' -> utxo)
  /// - Partial match to the subclass name
  /// - Partial match to the subclass ticker
  /// - Partial match to the subclass token standard suffix
  /// - Partial match to the subclass formatted name
  ///
  /// Throws [StateError] if no match is found.
  static CoinSubClass parse(String value) {
    const filteredChars = ['_', '-', ' '];
    final regex = RegExp('(${filteredChars.join('|')})');

    final sanitizedValue = value.toLowerCase().replaceAll(regex, '');

    // First, try to find exact enum name match (highest priority)
    try {
      return CoinSubClass.values.firstWhere(
        (e) => _enumNameLower(e) == sanitizedValue,
      );
      // ignore: avoid_catching_errors
    } on StateError {
      // If no exact match, continue with other matching strategies
    }

    // Second, try to find exact ticker match (sanitized)
    final exactTickerMatches = CoinSubClass.values
        .where(
          (e) => e.ticker.toLowerCase().replaceAll(regex, '') == sanitizedValue,
        )
        .toList();
    if (exactTickerMatches.isNotEmpty) {
      // Tie-breaker for duplicated tickers. Both smartChain and utxo return
      // 'UTXO' as ticker; prefer utxo to avoid mislabeling.
      if (sanitizedValue == 'utxo') {
        return CoinSubClass.utxo;
      }

      return exactTickerMatches.first;
    }

    return CoinSubClass.values.firstWhere((e) {
      // Check if enum name contains the value
      final enumName = _enumNameLower(e);
      final matchesValue = enumName.contains(sanitizedValue);
      if (matchesValue) {
        return true;
      }

      // Check if ticker contains the value (partial ticker match, sanitized)
      final matchesTicker = e.ticker
          .toLowerCase()
          .replaceAll(regex, '')
          .contains(sanitizedValue);
      if (matchesTicker) {
        return true;
      }

      final matchesTokenStandardSuffix =
          e.tokenStandardSuffix?.toLowerCase().contains(sanitizedValue) ??
          false;
      if (matchesTokenStandardSuffix) {
        return true;
      }

      return e.formatted.toLowerCase().contains(sanitizedValue);
    });
  }

  static CoinSubClass? tryParse(String value) {
    try {
      return parse(value);
    } on StateError {
      return null;
    }
  }

  /// Checks if this subclass can be a parent of the given child subclass
  bool canBeParentOf(CoinSubClass child) {
    // Tendermint tokens can be a child of Tendermint, but not the
    // other way around. This allows Tendermint to be a parent
    // while keeping the existing parent subclass check intact.
    if (this == CoinSubClass.tendermint &&
        child == CoinSubClass.tendermintToken) {
      return true;
    }

    // For most cases, parent and child should have the same subclass
    return this == child;
  }

  /// Checks if this subclass can be a child of the given parent subclass
  bool canBeChildOf(CoinSubClass parent) {
    return parent.canBeParentOf(this);
  }

  // TODO: Consider if null or an empty string should be returned for
  // subclasses where they don't have a symbol used in coin IDs.
  String get formatted {
    switch (this) {
      case CoinSubClass.moonbeam:
        return 'Moonbeam';
      case CoinSubClass.ftm20:
        return 'Fantom';
      case CoinSubClass.arbitrum:
        return 'Arbitrum';
      case CoinSubClass.base:
        return 'Base';
      case CoinSubClass.slp:
        return 'Simple Ledger Protocol';
      case CoinSubClass.sia:
        return 'Sia';
      case CoinSubClass.qrc20:
        return 'Qtum';
      case CoinSubClass.avx20:
        return 'Avalanche C-Chain';
      case CoinSubClass.smartChain:
        return 'Komodo Smart Chain';
      case CoinSubClass.moonriver:
        return 'Moonriver';
      case CoinSubClass.ethereumClassic:
        return 'Ethereum Classic';
      case CoinSubClass.ubiq:
        return 'Ubiq';
      case CoinSubClass.bep20:
        return 'Binance Smart Chain';
      case CoinSubClass.matic:
        return 'Polygon';
      case CoinSubClass.utxo:
        return 'Native';
      case CoinSubClass.smartBch:
        return 'SmartBCH';
      case CoinSubClass.erc20:
        return 'Ethereum';
      case CoinSubClass.tendermintToken:
        return 'Tendermint Token';
      case CoinSubClass.tendermint:
        return 'Tendermint';
      case CoinSubClass.krc20:
        return 'KuCoin Chain';
      case CoinSubClass.ewt:
        return 'Energy Web Token';
      case CoinSubClass.hrc20:
        return 'Huobi Token';
      case CoinSubClass.hecoChain:
        return 'Huobi ECO Chain';
      case CoinSubClass.rskSmartBitcoin:
        return 'RSK Smart Bitcoin';
      case CoinSubClass.grc20:
        return 'Gleec';
      case CoinSubClass.zhtlc:
        return 'Pirate Network';
      case CoinSubClass.unknown:
        return 'Unknown';
    }
  }

  Color? get color {
    switch (this) {
      case CoinSubClass.moonbeam:
        return const Color(0xFFE4147C); // glmr: "#e4147c"
      case CoinSubClass.ftm20:
        return const Color(0xFF14B4EC); // ftm: "#14b4ec"
      case CoinSubClass.arbitrum:
        return const Color(0xFF28A0F0); // arb: "#28a0f0"
      case CoinSubClass.base:
        return const Color(0xFF0052FF); // base: "#0052ff"
      // ignore: deprecated_member_use_from_same_package
      case CoinSubClass.slp:
        return const Color(0xFF0CC38C); // slp: "#0cc38c"
      case CoinSubClass.sia:
        return const Color(0xFF29F06F); // sia: "#29f06f"
      case CoinSubClass.qrc20:
        return const Color(0xFF2E98CE); // qrc20: "#2e98ce"
      case CoinSubClass.avx20:
        return const Color(0xFFE74041); // avax: "#e74041"
      case CoinSubClass.smartChain:
        return const Color(0xFF276580); // smart_chain: "#276580"
      case CoinSubClass.moonriver:
        return const Color(0xFFF4B406); // movr: "#f4b406"
      case CoinSubClass.ethereumClassic:
        return const Color(0xFF328132); // etc: "#328132"
      case CoinSubClass.tendermintToken:
        return const Color(0xFF2E3147); // atom: "#2e3147"
      case CoinSubClass.ubiq:
        return const Color(0xFF04E88E); // ubq: "#04e88e"
      case CoinSubClass.bep20:
        return const Color(0xFFF1B82E); // bnb: "#f1b82e"
      case CoinSubClass.matic:
        return const Color(0xFF6E40D7); // matic: "#6e40d7"
      case CoinSubClass.utxo:
        return const Color(0xFF58C0AB); // kmd: "#58C0AB"
      case CoinSubClass.smartBch:
        return const Color(0xFF8CC250); // bch: "#8cc250"
      case CoinSubClass.erc20:
        return const Color(0xFF627DE8); // erc: "#627de8"
      case CoinSubClass.tendermint:
        return const Color(0xFF2E3147); // atom: "#2e3147"
      case CoinSubClass.krc20:
        return const Color(0xFF0491DB); // kcs: "#0491db"
      case CoinSubClass.ewt:
        return const Color(0xFFA464FC); // ewt: "#a464fc"
      case CoinSubClass.hrc20:
        return const Color(0xFF2A3069); // ht: "#2a3069"
      case CoinSubClass.hecoChain:
        return const Color(0xFF2A3069); // ht: "#2a3069"
      case CoinSubClass.rskSmartBitcoin:
        return const Color(0xFFFC9D37); // rbtc: "#fc9d37"
      case CoinSubClass.grc20:
        return const Color(0xFF8C41FF); // gleec: "#8c41ff"
      case CoinSubClass.zhtlc:
        return const Color(0xFFC29F47); // arrr: "#c29f47"
      case CoinSubClass.unknown:
        return null;
    }
  }
}

extension CoinSubClassTokenStandard on CoinSubClass {
  /// Canonical short token/network standard suffix used for parent asset
  /// disambiguation in display names. Returns null when no suffix should
  /// be appended for the given subclass.
  String? get tokenStandardSuffix {
    switch (this) {
      case CoinSubClass.erc20:
        return 'ERC20';
      case CoinSubClass.bep20:
        return 'BEP20';
      case CoinSubClass.qrc20:
        return 'QRC20';
      case CoinSubClass.ftm20:
        return 'FTM20';
      case CoinSubClass.arbitrum:
        return 'ARB20';
      case CoinSubClass.base:
        return 'BASE';
      case CoinSubClass.avx20:
        return 'AVX20';
      case CoinSubClass.matic:
        return 'PLG20';
      case CoinSubClass.moonriver:
        return 'MVR20';
      case CoinSubClass.krc20:
        return 'KRC20';
      case CoinSubClass.hrc20:
        return 'HRC20';
      case CoinSubClass.hecoChain:
        return 'HCO20';
      case CoinSubClass.grc20:
        return 'GRC20';
      // Subclasses without a canonical short token/network standard suffix
      case CoinSubClass.moonbeam:
      case CoinSubClass.slp: // ignore: deprecated_member_use_from_same_package
      case CoinSubClass.sia:
      case CoinSubClass.smartChain:
      case CoinSubClass.ethereumClassic:
      case CoinSubClass.ubiq:
      case CoinSubClass.utxo:
      case CoinSubClass.smartBch:
      case CoinSubClass.tendermint:
      case CoinSubClass.tendermintToken:
      case CoinSubClass.ewt:
      case CoinSubClass.rskSmartBitcoin:
      case CoinSubClass.zhtlc:
      case CoinSubClass.unknown:
        return null;
    }
  }
}

const Set<CoinSubClass> evmCoinSubClasses = {
  CoinSubClass.avx20,
  CoinSubClass.bep20,
  CoinSubClass.ftm20,
  CoinSubClass.matic,
  CoinSubClass.hrc20,
  CoinSubClass.arbitrum,
  CoinSubClass.base,
  CoinSubClass.moonriver,
  CoinSubClass.moonbeam,
  CoinSubClass.ethereumClassic,
  CoinSubClass.ubiq,
  CoinSubClass.krc20,
  CoinSubClass.ewt,
  CoinSubClass.hecoChain,
  CoinSubClass.rskSmartBitcoin,
  CoinSubClass.grc20,
  CoinSubClass.erc20,
};
