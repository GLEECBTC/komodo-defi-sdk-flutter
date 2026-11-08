@TestOn('browser')
library;

import 'package:hive_ce/hive.dart';
import 'package:komodo_coin_updates/hive/hive_registrar.g.dart';
import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

void main() {
  test(
    'IndexedDB keeps runtime preview catalogs and custom tokens separate',
    () async {
      Hive.init('same-browser-path');
      Hive.registerAdapters();
      final names = <String>[];
      addTearDown(() async {
        await Hive.close();
        for (final name in names) {
          await Hive.deleteBoxFromDisk(name);
        }
      });
      final token = Asset.fromJson({
        'coin': 'CUSTOM-SOL-DEV',
        'fname': 'Custom SPL',
        'type': 'SOLANATOKEN',
        'parent_coin': 'SOL-DEV',
        'protocol': {
          'type': 'SOLANATOKEN',
          'protocol_data': {
            'platform': 'SOL-DEV',
            'mint_address': '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
            'program_id': SolanaTokenProtocol.classicTokenProgramId,
            'decimals': 6,
          },
        },
      });
      final stores = <CustomTokenStorage>[];
      for (final namespace in ['', 'preview-a', 'preview-b']) {
        final repository =
            DefaultCoinConfigDataFactory(
              storageNamespace: namespace,
            ).createRepository(
              const AssetRuntimeUpdateConfig(),
              const CoinConfigTransformer(),
            );
        final store = CustomTokenStorage(storageNamespace: namespace);
        stores.add(store);
        names.addAll([
          repository.settingsBoxName,
          repository.assetsBoxName,
          store.customTokensBoxName,
        ]);
        final settings = await Hive.openBox<String>(repository.settingsBoxName);
        final assets = await Hive.openLazyBox<Asset>(repository.assetsBoxName);
        expect(settings.get('commit'), isNull);
        expect(await assets.get(token.id.id), isNull);
        await settings.put(
          'commit',
          namespace.isEmpty ? 'production' : namespace,
        );
        await assets.put(token.id.id, token);
        if (namespace == 'preview-a') await store.storeCustomToken(token);
      }
      expect(await stores[0].hasCustomTokens(), isFalse);
      expect(await stores[1].hasCustomTokens(), isTrue);
      expect(await stores[2].hasCustomTokens(), isFalse);
      await Hive.close();
      for (final namespace in ['', 'preview-a', 'preview-b']) {
        final repository =
            DefaultCoinConfigDataFactory(
              storageNamespace: namespace,
            ).createRepository(
              const AssetRuntimeUpdateConfig(),
              const CoinConfigTransformer(),
            );
        final settings = await Hive.openBox<String>(repository.settingsBoxName);
        expect(
          settings.get('commit'),
          namespace.isEmpty ? 'production' : namespace,
        );
      }
      final restored = await CustomTokenStorage(
        storageNamespace: 'preview-a',
      ).getCustomToken(token.id);
      expect(restored!.protocol.isCustomToken, isTrue);
      expect(restored.protocol.contractAddress, token.protocol.contractAddress);
    },
  );
}
