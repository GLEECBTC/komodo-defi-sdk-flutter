import 'package:dragon_charts_flutter/dragon_charts_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart' show RepositoryProvider;
import 'package:kdf_sdk_example/widgets/assets/asset_market_info.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';

class AssetItemWidget extends StatelessWidget {
  const AssetItemWidget({
    required this.asset,
    required this.authOptions,
    super.key,
    this.onTap,
  });

  final Asset asset;
  final AuthOptions authOptions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabledReasons = asset.getUnavailableReasons(authOptions);
    final isCompatible = disabledReasons == null;
    final disabledReason = disabledReasons?.map((r) => r.message).join(', ');

    return ListTile(
      key: Key(asset.id.id),
      title: Text(asset.id.id),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(asset.id.name),
          if (disabledReason != null)
            Text(
              disabledReason,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
        ],
      ),
      tileColor: isCompatible ? null : Colors.grey[200],
      leading: AssetLogo(asset, size: 32),
      trailing: _AssetItemTrailing(asset: asset, isEnabled: isCompatible),
      // ignore: avoid_redundant_argument_values
      enabled: isCompatible,
      onTap: isCompatible ? onTap : null,
    );
  }
}

class _AssetItemTrailing extends StatelessWidget {
  const _AssetItemTrailing({required this.asset, required this.isEnabled});

  final Asset asset;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final isChildAsset = asset.id.isChildAsset;

    // Use the parent coin ticker for child assets so that token logos display
    // the network they belong to (e.g. ETH for ERC20 tokens).
    final protocolTicker = isChildAsset
        ? asset.id.parentId?.id
        : asset.id.subClass.iconTicker;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isEnabled) ...[
          const Icon(Icons.lock, color: Colors.grey),
          const SizedBox(width: 8),
        ],
        if (!asset.protocol.isTestnet) CoinSparkline(assetId: asset.id),
        const SizedBox(width: 8),
        AssetMarketInfo(asset),
        const SizedBox(width: 8),
        if (asset.supportsMultipleAddresses && isEnabled) ...[
          const Tooltip(
            message: 'Supports multiple addresses',
            child: Icon(Icons.account_balance_wallet),
          ),
          const SizedBox(width: 8),
        ],
        if (asset.requiresHdWallet) ...[
          const Tooltip(message: 'Requires HD wallet', child: Icon(Icons.key)),
          const SizedBox(width: 8),
        ],
        const SizedBox(width: 8),
        CircleAvatar(
          radius: 12,
          foregroundImage: NetworkImage(
            'https://gleecbtc.github.io/coins/icons/${protocolTicker?.toLowerCase()}.png',
          ),
          backgroundColor: Colors.white70,
        ),
        SizedBox(
          width: 80,
          child: AssetBalanceText(
            key: Key('balance_${asset.id.id}'),
            asset.id,
            activateIfNeeded: false,
          ),
        ),
        const Icon(Icons.arrow_forward_ios),
      ],
    );
  }
}

class CoinSparkline extends StatefulWidget {
  const CoinSparkline({required this.assetId, super.key});

  final AssetId assetId;

  @override
  State<CoinSparkline> createState() => _CoinSparklineState();
}

class _CoinSparklineState extends State<CoinSparkline> {
  late Future<List<double>?> _sparklineFuture;

  @override
  void initState() {
    super.initState();
    _sparklineFuture = RepositoryProvider.of<SparklineRepository>(
      context,
    ).fetchSparkline(widget.assetId);
  }

  @override
  void didUpdateWidget(covariant CoinSparkline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) {
      setState(() {
        _sparklineFuture = RepositoryProvider.of<SparklineRepository>(
          context,
        ).fetchSparkline(widget.assetId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<double>?>(
      future: _sparklineFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 130,
            height: 35,
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        } else if (snapshot.hasError) {
          return const SizedBox(
            width: 130,
            height: 35,
            child: Icon(Icons.show_chart, color: Colors.grey, size: 16),
          );
        } else if (!snapshot.hasData || (snapshot.data?.isEmpty ?? true)) {
          return const SizedBox.shrink();
        } else {
          return LimitedBox(
            maxWidth: 130,
            child: SizedBox(
              height: 35,
              child: SparklineChart(
                data: snapshot.data!,
                positiveLineColor: Colors.green,
                negativeLineColor: Colors.red,
                lineThickness: 1,
                isCurved: true,
              ),
            ),
          );
        }
      },
    );
  }
}
