// ignore_for_file: cascade_invocations

import 'dart:developer';

import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_coins/komodo_coins.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/_internal_exports.dart';
import 'package:komodo_defi_sdk/src/activation_config/hive_adapters.dart';
import 'package:komodo_defi_sdk/src/fees/fee_manager.dart';
import 'package:komodo_defi_sdk/src/market_data/market_data_manager.dart'
    show CexMarketDataManager, MarketDataManager;
import 'package:komodo_defi_sdk/src/message_signing/message_signing_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_sdk/src/storage/secure_rpc_password_mixin.dart';
import 'package:komodo_defi_sdk/src/streaming/event_streaming_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/legacy_withdrawal_manager.dart';
import 'package:komodo_defi_sdk/src/withdrawals/withdrawal_manager.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

var _activationConfigHiveInitialized = false;

Future<void> _ensureActivationConfigHiveInitialized() async {
  if (_activationConfigHiveInitialized) return;
  await Hive.initFlutter();
  registerActivationConfigAdapters();
  _activationConfigHiveInitialized = true;
}

/// Bootstrap the SDK's dependencies
Future<void> bootstrap({
  required IKdfHostConfig? hostConfig,
  required KomodoDefiSdkConfig config,
  required GetIt container,
  KomodoDefiFramework? kdfFramework,
  void Function(String)? externalLogger,
}) async {
  log('Bootstrap: Starting dependency injection setup...', name: 'Bootstrap');
  final stopwatch = Stopwatch()..start();

  final rpcPassword = await SecureRpcPasswordMixin().ensureRpcPassword();

  // Framework and core dependencies
  container.registerSingletonAsync<KomodoDefiFramework>(() async {
    if (kdfFramework != null) return kdfFramework;

    final resolvedHostConfig =
        hostConfig ?? LocalConfig(https: true, rpcPassword: rpcPassword);

    return KomodoDefiFramework.create(
      hostConfig: resolvedHostConfig,
      externalLogger: externalLogger,
    );
  });

  container.registerSingletonAsync<ApiClient>(() async {
    final framework = await container.getAsync<KomodoDefiFramework>();
    return framework.client;
  }, dependsOn: [KomodoDefiFramework]);

  // Event streaming manager (internal use by managers for real-time updates)
  container.registerSingletonAsync<EventStreamingManager>(() async {
    final framework = await container.getAsync<KomodoDefiFramework>();
    return EventStreamingManager(
      client: framework.client,
      eventService: framework.streaming,
    );
  }, dependsOn: [KomodoDefiFramework]);

  // Auth and storage dependencies
  container.registerSingletonAsync<KomodoDefiLocalAuth>(() async {
    final framework = await container.getAsync<KomodoDefiFramework>();
    final auth = KomodoDefiLocalAuth(
      kdf: framework,
      hostConfig:
          hostConfig ?? LocalConfig(https: true, rpcPassword: rpcPassword),
    );
    await auth.ensureInitialized();
    return auth;
  }, dependsOn: [KomodoDefiFramework]);

  // Asset history storage singletons
  container.registerLazySingleton(AssetHistoryStorage.new);
  container.registerSingletonAsync<KomodoAssetsUpdateManager>(
    () async => KomodoAssetsUpdateManager(),
  );

  // Activation configuration service (must be available before ActivationManager)
  container.registerSingletonAsync<ActivationConfigService>(() async {
    await _ensureActivationConfigHiveInitialized();
    final auth = await container.getAsync<KomodoDefiLocalAuth>();
    final repo = HiveActivationConfigRepository();
    return ActivationConfigService(
      repo,
      walletIdResolver: () async => (await auth.currentUser)?.walletId,
      authStateChanges: auth.authStateChanges,
    );
  }, dependsOn: [KomodoDefiLocalAuth]);

  // Register asset manager first since it's a core dependency
  container.registerSingletonAsync<AssetManager>(() async {
    final auth = await container.getAsync<KomodoDefiLocalAuth>();
    final assetManager = AssetManager(
      auth,
      config,
      () => container<ActivationManager>(),
      container<KomodoAssetsUpdateManager>(),
      () => container<ActivatedAssetsCache>(),
      () => container<SharedActivationCoordinator>(),
    );
    await assetManager.init();
    // Will be removed in near future after KW is fully migrated to KDF
    await assetManager.initTickerIndex();
    return assetManager;
  }, dependsOn: [KomodoDefiLocalAuth]);

  container.registerSingletonAsync<ActivatedAssetsCache>(() async {
    final client = await container.getAsync<ApiClient>();
    final auth = await container.getAsync<KomodoDefiLocalAuth>();
    final assets = await container.getAsync<AssetManager>();
    return ActivatedAssetsCache(
      client: client,
      auth: auth,
      assetLookup: assets,
      ttl: config.activatedAssetsCacheTtl,
    );
  }, dependsOn: [ApiClient, KomodoDefiLocalAuth, AssetManager]);

  // Register BalanceManager BEFORE ActivationManager to avoid circular dependency
  container.registerSingletonAsync<BalanceManager>(() async {
    final assets = await container.getAsync<AssetManager>();
    final auth = await container.getAsync<KomodoDefiLocalAuth>();
    final eventStreamingManager = await container
        .getAsync<EventStreamingManager>();

    // Create BalanceManager without its dependencies on SharedActivationCoordinator and PubkeyManager initially
    return BalanceManager(
      activationCoordinator:
          null, // Will be set after SharedActivationCoordinator is created
      assetLookup: assets,
      pubkeyManager: null, // Will be set after PubkeyManager is created
      auth: auth,
      eventStreamingManager: eventStreamingManager,
      assetHistoryStorage: container<AssetHistoryStorage>(),
    );
  }, dependsOn: [AssetManager, KomodoDefiLocalAuth, EventStreamingManager]);

  // Register activation manager with asset manager dependency
  container.registerSingletonAsync<ActivationManager>(
    () async {
      final client = await container.getAsync<ApiClient>();
      final auth = await container.getAsync<KomodoDefiLocalAuth>();
      final assetManager = await container.getAsync<AssetManager>();
      final balanceManager = await container.getAsync<BalanceManager>();
      final configService = await container.getAsync<ActivationConfigService>();
      final activatedAssetsCache = await container
          .getAsync<ActivatedAssetsCache>();

      final activationManager = ActivationManager(
        client,
        auth,
        container<AssetHistoryStorage>(),
        assetManager,
        balanceManager,
        configService,
        // Needed here to add custom tokens to the same instance
        // as the asset manager
        container<KomodoAssetsUpdateManager>(),
        activatedAssetsCache,
      );

      return activationManager;
    },
    dependsOn: [
      ApiClient,
      KomodoDefiLocalAuth,
      AssetManager,
      BalanceManager,
      ActivationConfigService,
      KomodoAssetsUpdateManager,
      ActivatedAssetsCache,
    ],
  );

  container.registerSingletonAsync<NftActivationService>(() async {
    final client = await container.getAsync<ApiClient>();
    final assetManager = await container.getAsync<AssetManager>();
    final activatedAssetsCache = await container
        .getAsync<ActivatedAssetsCache>();
    return NftActivationService(client, assetManager, activatedAssetsCache);
  }, dependsOn: [ApiClient, AssetManager, ActivatedAssetsCache]);

  // Register shared activation coordinator
  container.registerSingletonAsync<SharedActivationCoordinator>(() async {
    final activationManager = await container.getAsync<ActivationManager>();
    final balanceManager = await container.getAsync<BalanceManager>();

    final coordinator = SharedActivationCoordinator(
      activationManager,
      await container.getAsync<KomodoDefiLocalAuth>(),
    );

    if (balanceManager.activationCoordinator == null) {
      balanceManager.setActivationCoordinator(coordinator);
    }

    return coordinator;
  }, dependsOn: [ActivationManager, BalanceManager, KomodoDefiLocalAuth]);

  // Register remaining managers
  container.registerSingletonAsync<PubkeyManager>(() async {
    final client = await container.getAsync<ApiClient>();
    final auth = await container.getAsync<KomodoDefiLocalAuth>();
    final activationCoordinator = await container
        .getAsync<SharedActivationCoordinator>();
    final pubkeyManager = PubkeyManager(client, auth, activationCoordinator);

    // Set the PubkeyManager on BalanceManager now that it's available
    final balanceManager = await container.getAsync<BalanceManager>();
    if (balanceManager.pubkeyManager == null) {
      balanceManager.setPubkeyManager(pubkeyManager);
    }

    return pubkeyManager;
  }, dependsOn: [ApiClient, KomodoDefiLocalAuth, SharedActivationCoordinator]);

  container.registerSingleton(
    AddressOperations(await container.getAsync<ApiClient>()),
  );

  container.registerSingletonAsync<MnemonicValidator>(() async {
    final validator = MnemonicValidator();
    await validator.init();
    return validator;
  });

  // Register market data dependencies using factory pattern
  await MarketDataBootstrap.register(
    container,
    config: config.marketDataConfig,
  );

  container.registerSingletonAsync<MessageSigningManager>(
    () async => MessageSigningManager(await container.getAsync<ApiClient>()),
    dependsOn: [ApiClient],
  );

  container.registerSingletonAsync<MarketDataManager>(() async {
    final repositories = await MarketDataBootstrap.buildRepositoryList(
      container,
      config.marketDataConfig,
    );
    final manager = CexMarketDataManager(
      priceRepositories: repositories,
      selectionStrategy: container<RepositorySelectionStrategy>(),
    );
    await manager.init();
    return manager;
  }, dependsOn: MarketDataBootstrap.buildDependencies(config.marketDataConfig));

  container.registerSingletonAsync<FeeManager>(() async {
    final client = await container.getAsync<ApiClient>();
    return FeeManager(client);
  }, dependsOn: [ApiClient]);

  container.registerSingletonAsync<LegacyWithdrawalManager>(() async {
    final client = await container.getAsync<ApiClient>();
    return LegacyWithdrawalManager(client);
  }, dependsOn: [ApiClient]);

  container.registerSingletonAsync<TransactionHistoryManager>(
    () async {
      final client = await container.getAsync<ApiClient>();
      final auth = await container.getAsync<KomodoDefiLocalAuth>();
      final assetProvider = await container.getAsync<AssetManager>();
      final pubkeys = await container.getAsync<PubkeyManager>();
      final activationCoordinator = await container
          .getAsync<SharedActivationCoordinator>();
      final eventStreamingManager = await container
          .getAsync<EventStreamingManager>();
      return TransactionHistoryManager(
        client,
        auth,
        assetProvider,
        activationCoordinator,
        pubkeyManager: pubkeys,
        eventStreamingManager: eventStreamingManager,
        assetHistoryStorage: container<AssetHistoryStorage>(),
      );
    },
    dependsOn: [
      ApiClient,
      KomodoDefiLocalAuth,
      AssetManager,
      PubkeyManager,
      SharedActivationCoordinator,
      EventStreamingManager,
    ],
  );

  container.registerSingletonAsync<WithdrawalManager>(
    () async {
      final client = await container.getAsync<ApiClient>();
      final assetProvider = await container.getAsync<AssetManager>();
      final feeManager = await container.getAsync<FeeManager>();
      final legacyManager = await container.getAsync<LegacyWithdrawalManager>();

      final activationCoordinator = await container
          .getAsync<SharedActivationCoordinator>();
      return WithdrawalManager(
        client,
        assetProvider,
        feeManager,
        activationCoordinator,
        legacyManager,
      );
    },
    dependsOn: [
      ApiClient,
      AssetManager,
      SharedActivationCoordinator,
      FeeManager,
      LegacyWithdrawalManager,
    ],
  );

  container.registerSingletonAsync<SecurityManager>(
    () async {
      final client = await container.getAsync<ApiClient>();
      final auth = await container.getAsync<KomodoDefiLocalAuth>();
      final assetProvider = await container.getAsync<AssetManager>();
      final activationCoordinator = await container
          .getAsync<SharedActivationCoordinator>();
      return SecurityManager(
        client,
        auth,
        assetProvider,
        activationCoordinator,
      );
    },
    dependsOn: [
      ApiClient,
      KomodoDefiLocalAuth,
      AssetManager,
      SharedActivationCoordinator,
    ],
  );

  // Wait for all async singletons to initialize
  await container.allReady();

  stopwatch.stop();
  log(
    'Bootstrap: Dependency injection setup completed in ${stopwatch.elapsedMilliseconds}ms',
    name: 'Bootstrap',
  );
}
