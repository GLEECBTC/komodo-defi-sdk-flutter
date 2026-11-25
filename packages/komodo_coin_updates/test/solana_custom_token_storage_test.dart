import 'package:komodo_coin_updates/komodo_coin_updates.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';

import 'hive/test_harness.dart';

void main() {
  late HiveTestEnv hive;
  final platform = Asset.fromJson({
    'coin': 'TESTSOL',
    'fname': 'Solana Devnet',
    'type': 'SOLANA',
    'protocol': {'type': 'SOLANA'},
    'nodes': [
      {'url': 'https://api.devnet.solana.com'},
    ],
  });
  Asset token({
    String mint = '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
    String program = SolanaTokenProtocol.classicTokenProgramId,
    int decimals = 6,
  }) => Asset.fromJson(
    {
      'coin': 'CUSTOM-TESTSOL',
      'fname': 'Custom Solana token',
      'type': 'SOLANATOKEN',
      'parent_coin': platform.id.id,
      'protocol': {
        'type': 'SOLANATOKEN',
        'protocol_data': {
          'platform': platform.id.id,
          'mint_address': mint,
          'program_id': program,
          'decimals': decimals,
        },
      },
    },
    knownIds: {platform.id},
  );

  setUp(() async {
    hive = HiveTestEnv();
    await hive.setup();
  });
  tearDown(() async => hive.dispose());

  test('custom Solana metadata and parent survive a storage restart', () async {
    final original = token();
    final storage = CustomTokenStorage(storageNamespace: 'solana-preview');
    await storage.storeCustomToken(original);
    await storage.dispose();
    await hive.restart();
    final reopened = CustomTokenStorage(storageNamespace: 'solana-preview');
    addTearDown(reopened.dispose);
    final restored = (await reopened.getAllCustomTokens({platform.id})).single;
    expect(restored.id, original.id);
    expect(restored.id.parentId, platform.id);
    expect(restored.protocol.isCustomToken, isTrue);
    final protocol = restored.protocol as SolanaTokenProtocol;
    expect(protocol.mintAddress, original.protocol.contractAddress);
    expect(protocol.decimals, 6);
    expect(protocol.programId, SolanaTokenProtocol.classicTokenProgramId);
    expect(
      (await reopened.getCustomToken(original.id))!.protocol.isCustomToken,
      isTrue,
    );
    expect(await reopened.upsertCustomToken(original), isTrue);
  });

  test(
    'Solana collisions preserve mint case, program, and decimal identity',
    () async {
      final storage = CustomTokenStorage(storageNamespace: 'solana-preview');
      addTearDown(storage.dispose);
      final original = token();
      await storage.storeCustomToken(original);
      for (final conflicting in [
        token(mint: original.protocol.contractAddress!.toLowerCase()),
        token(program: SolanaTokenProtocol.token2022ProgramId),
        token(decimals: 9),
      ]) {
        await expectLater(
          storage.upsertCustomToken(conflicting),
          throwsA(isA<CustomTokenConflictException>()),
        );
      }
      expect(await storage.getCustomTokenCount(), 1);
      expect(
        (await storage.getCustomToken(original.id))!.protocol.contractAddress,
        original.protocol.contractAddress,
      );
    },
  );

  test('two runtime namespaces keep custom tokens out of production', () async {
    final first = CustomTokenStorage(storageNamespace: 'preview-a');
    final second = CustomTokenStorage(storageNamespace: 'preview-b');
    final production = CustomTokenStorage(storageNamespace: '');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(production.dispose);
    await first.storeCustomToken(token());
    expect(await first.hasCustomTokens(), isTrue);
    expect(await second.hasCustomTokens(), isFalse);
    expect(await production.hasCustomTokens(), isFalse);
    await second.storeCustomToken(token(decimals: 9));
    expect((await first.getCustomToken(token().id))!.id.chainId.decimals, 6);
    expect((await second.getCustomToken(token().id))!.id.chainId.decimals, 9);
    expect(await production.getCustomTokenCount(), 0);
  });
}
