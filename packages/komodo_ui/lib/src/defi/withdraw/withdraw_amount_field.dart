import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// A text input field for entering the withdrawal amount
class WithdrawAmountField extends StatefulWidget {
  /// Creates a [WithdrawAmountField].
  const WithdrawAmountField({
    required this.asset,
    required this.amount,
    required this.isMaxAmount,
    required this.onChanged,
    required this.onMaxToggled,
    this.amountError,
    this.hasInsufficientBalance = false,
    this.availableBalance,
    this.maxAmountLabel,
    this.symbol,
    this.availableBalanceLabel,
    super.key,
  });

  /// The asset for which the withdrawal amount is being entered.
  final Asset asset;

  /// The current amount entered in the field.
  final String amount;

  /// Whether the maximum amount is selected.
  final bool isMaxAmount;

  /// Callback for when the amount changes.
  final ValueChanged<String> onChanged;

  /// Callback for when the maximum amount is toggled.
  final ValueChanged<bool> onMaxToggled;

  /// Error message for the amount field.
  final String? amountError;

  /// Whether the user has insufficient balance.
  final bool hasInsufficientBalance;

  /// The available balance for the asset.
  final String? availableBalance;

  /// Label shown in the disabled field while max is selected but the concrete
  /// amount is unknown (e.g. gas-free TRC20). Defaults to `'Maximum'`;
  /// pass a localized string to override.
  final String? maxAmountLabel;

  /// Ticker shown in the suffix and available-balance line. Defaults to the
  /// raw [AssetId.id] (e.g. `USDT-TRC20`); pass a clean symbol to override.
  final String? symbol;

  /// Label prefix for the available-balance line. Defaults to `'Available:'`;
  /// pass a localized string to override.
  final String? availableBalanceLabel;

  @override
  State<WithdrawAmountField> createState() => _WithdrawAmountFieldState();
}

class _WithdrawAmountFieldState extends State<WithdrawAmountField> {
  late TextEditingController _controller;

  /// The text shown in the (disabled) field while "max" is selected.
  ///
  /// Some rails (e.g. gas-free TRC20, where the fee is deducted from the token
  /// itself) cannot pre-compute the exact sendable amount, so they request max
  /// with an amount of `'0'`. Showing a literal `'0'` reads as "send nothing";
  /// display `Maximum` instead. Rails that do know the amount (native max
  /// passes the spendable balance) keep showing the concrete value.
  String get _displayAmount {
    if (widget.isMaxAmount && (double.tryParse(widget.amount) ?? 0) <= 0) {
      return widget.maxAmountLabel ?? 'Maximum';
    }
    return widget.amount;
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _displayAmount);
  }

  @override
  void didUpdateWidget(WithdrawAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final displayAmount = _displayAmount;
    if (_controller.text != displayAmount) {
      // Save current cursor position
      final selection = _controller.selection;

      // Update text
      _controller.text = displayAmount;

      // Restore cursor position, but handle potential out-of-bounds
      if (displayAmount.length >= selection.baseOffset) {
        _controller.selection = selection;
      } else {
        // If new text is shorter, move cursor to end
        _controller.selection = TextSelection.collapsed(
          offset: displayAmount.length,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Amount',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (widget.availableBalance != null)
              Text(
                '${widget.availableBalanceLabel ?? 'Available:'} '
                '${widget.availableBalance} '
                '${widget.symbol ?? widget.asset.id.id}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _controller,
          enabled: !widget.isMaxAmount,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            errorText: widget.amountError,
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.symbol ?? widget.asset.id.id,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            prefixIcon: widget.hasInsufficientBalance
                ? Tooltip(
                    message: 'Insufficient balance',
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: theme.colorScheme.error,
                    ),
                  )
                : null,
            helperText: widget.hasInsufficientBalance
                ? 'Insufficient balance'
                : 'Enter the amount to send',
            helperStyle: widget.hasInsufficientBalance
                ? TextStyle(color: theme.colorScheme.error)
                : null,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Checkbox(
                  value: widget.isMaxAmount,
                  onChanged: (value) => widget.onMaxToggled(value ?? false),
                ),
                const Text('Send maximum available'),
              ],
            ),
            if (!widget.isMaxAmount)
              TextButton(
                onPressed: () {
                  widget.onMaxToggled(true);
                },
                child: const Text('MAX'),
              ),
          ],
        ),
      ],
    );
  }
}
