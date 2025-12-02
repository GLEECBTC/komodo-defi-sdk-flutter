import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';

class WithdrawalScreen extends StatefulWidget {
  const WithdrawalScreen({
    required this.asset,
    required this.pubkeys,
    super.key,
  });

  final Asset asset;
  final AssetPubkeys pubkeys;

  @override
  State<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends State<WithdrawalScreen> {
  final _formKey = GlobalKey<FormState>();
  final _toAddressController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  final _ibcChannelController = TextEditingController();

  late final _sdk = context.read<KomodoDefiSdk>();

  PubkeyInfo? _selectedFromAddress;
  bool _isMaxAmount = false;
  FeeInfo? _selectedFee;
  WithdrawalPreview? _preview;
  String? _error;
  final bool _isIbcTransfer = false;
  WithdrawalFeeOptions? _feeOptions;
  WithdrawalFeeLevel? _selectedPriority;

  AddressValidation? _addressValidation;
  final _validationDebouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    _toAddressController.addListener(_onAddressChanged);
    if (widget.asset.supportsMultipleAddresses) {
      _selectedFromAddress = widget.pubkeys.keys.first;
    }
    _loadFeeOptions();
  }

  Future<void> _loadFeeOptions() async {
    try {
      final feeOptions = await _sdk.withdrawals.getFeeOptions(
        widget.asset.id.id,
      );
      if (mounted) {
        setState(() {
          _feeOptions = feeOptions;
          // Default to medium priority
          if (feeOptions != null && _selectedPriority == null) {
            _selectedPriority = WithdrawalFeeLevel.medium;
            _selectedFee = feeOptions.medium.feeInfo;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Failed to load fee options: $e');
      }
    }
  }

  void _onAddressChanged() {
    // Clear validation when input changes
    setState(() => _addressValidation = null);

    final address = _toAddressController.text;
    if (address.isEmpty) return;

    // Start new validation after debounce
    _validationDebouncer.run(() {
      _validateAddress(address);
    });
  }

  Future<void> _validateAddress(String address) async {
    try {
      final validation = await _sdk.addresses.validateAddress(
        asset: widget.asset,
        address: address,
      );

      if (mounted) {
        setState(() => _addressValidation = validation);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Address validation failed: $e');
      }
    }
  }

  String? _addressValidator(String? value) {
    if (value?.isEmpty ?? true) return 'Please enter recipient address';

    // If validation is in progress, consider it invalid
    if (_addressValidation == null) {
      return 'Validating address...';
    }

    // Return validation error if invalid
    if (!_addressValidation!.isValid) {
      return _addressValidation!.invalidReason ?? 'Invalid address format';
    }

    return null;
  }

  Future<void> _previewWithdrawal() async {
    if (_addressValidation == null) {
      setState(() => _error = 'Please wait for address validation to complete');
      return;
    }

    if (!_addressValidation!.isValid) {
      setState(
        () => _error =
            _addressValidation!.invalidReason ?? 'Invalid address format',
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() => _error = null);

      final params = WithdrawParameters(
        asset: widget.asset.id.id,
        toAddress: _toAddressController.text,
        amount: _isMaxAmount ? null : Decimal.parse(_amountController.text),
        fee: _selectedFee,
        feePriority: _selectedPriority,
        from: _selectedFromAddress?.derivationPath != null
            ? WithdrawalSource.hdDerivationPath(
                _selectedFromAddress!.derivationPath!,
              )
            : null,
        memo: _memoController.text.isEmpty ? null : _memoController.text,
        isMax: _isMaxAmount,
        ibcTransfer: _isIbcTransfer ? true : null,
        ibcSourceChannel: _isIbcTransfer
            ? int.tryParse(_ibcChannelController.text)
            : null,
      );

      final preview = await _sdk.withdrawals.previewWithdrawal(params);

      if (!mounted) return;

      setState(() {
        _preview = preview;
        _selectedFee = preview.fee;
      });

      await _showPreviewDialog(params);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _showPreviewDialog(WithdrawParameters params) async {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdrawal Preview'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Asset: ${params.asset}'),
            Text('To: ${params.toAddress}'),
            if (params.amount != null)
              Text('Amount: ${params.amount} ${params.asset}'),
            if (_selectedFee != null) ...[
              const SizedBox(height: 8),
              FeeInfoDisplay(feeInfo: _selectedFee!),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 8),
              Text('Estimated fee: ${_preview!.fee.formatTotal()}'),
              Text('Balance change: ${_preview!.balanceChanges.netChange}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _executeWithdrawal(params);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeWithdrawal(WithdrawParameters params) async {
    try {
      // Execute the previewed withdrawal (transaction already signed)
      final progressStream = _preview != null
          ? _sdk.withdrawals.executeWithdrawal(_preview!, params.asset)
          : _sdk.withdrawals.withdraw(params);

      await for (final progress in progressStream) {
        if (!mounted) return;

        switch (progress.status) {
          case WithdrawalStatus.complete:
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Withdrawal complete! TX: ${progress.withdrawalResult?.txHash}',
                ),
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            );
            Navigator.of(context).pop();
            return;
          case WithdrawalStatus.error:
            setState(
              () => _error = progress.errorMessage ?? 'Withdrawal failed',
            );
            return;
          default:
            // Show progress
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(progress.message)));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _onCopyAddress(PubkeyInfo? address) {
    if (address == null) return;

    Clipboard.setData(ClipboardData(text: address.address));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Address copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              // Replace the dropdown with SourceAddressField
              if (widget.asset.supportsMultipleAddresses) ...[
                AddressSelectInput(
                  addresses: widget.pubkeys.keys,
                  onAddressSelected: (address) {
                    setState(() => _selectedFromAddress = address);
                  },
                  assetName: widget.asset.id.id,
                  selectedAddress: _selectedFromAddress,
                  hint: 'Select Source Address',
                  verified: (address) => address.derivationPath != null,
                  onCopied: _onCopyAddress,
                ),

                const SizedBox(height: 16),
              ],

              // Recipient address field
              TextFormField(
                controller: _toAddressController,
                decoration: InputDecoration(
                  labelText: 'Recipient Address',
                  hintText: 'Enter recipient address',
                  suffixIcon: _buildValidationStatus(),
                ),
                validator: _addressValidator,
              ),
              const SizedBox(height: 16),

              // Amount field
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  hintText: 'Enter amount to send',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: !_isMaxAmount,
                validator: (value) {
                  if (_isMaxAmount) return null;
                  if (value?.isEmpty == true) return 'Please enter an amount';
                  final amount = Decimal.tryParse(value!);
                  if (amount == null) return 'Please enter a valid number';
                  if (amount <= Decimal.zero) {
                    return 'Amount must be greater than 0';
                  }
                  return null;
                },
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(
                      r'^\d*\.?\d{0,' +
                          (widget.asset.id.chainId.decimals ?? 8).toString() +
                          r'}$',
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                value: _isMaxAmount,
                onChanged: (value) => setState(() {
                  _isMaxAmount = value == true;
                  if (_isMaxAmount) {
                    _amountController.clear();
                  }
                }),
                title: const Text('Send maximum amount'),
              ),
              const SizedBox(height: 16),

              // Fee priority selector
              WithdrawalPrioritySelector(
                feeOptions: _feeOptions,
                selectedPriority: _selectedPriority,
                onPriorityChanged: (priority) {
                  setState(() {
                    _selectedPriority = priority;
                    if (_feeOptions != null) {
                      _selectedFee = _feeOptions!
                          .getByPriority(priority)
                          .feeInfo;
                    }
                  });
                },
                onCustomFeeSelected: () {
                  setState(() {
                    _selectedPriority = null;
                    _selectedFee = null;
                  });
                },
              ),

              // Custom fee input (only show if no priority is selected)
              if (_selectedPriority == null) ...[
                const SizedBox(height: 16),
                Text(
                  'Custom Fee',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                FeeInfoInput(
                  asset: widget.asset,
                  selectedFee: _selectedFee,
                  isCustomFee: true,
                  onFeeSelected: (fee) {
                    setState(() => _selectedFee = fee);
                  },
                ),
              ],
              if (widget.asset.protocol.isMemoSupported) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _memoController,
                  decoration: const InputDecoration(
                    labelText: 'Memo (Optional)',
                    hintText: 'Enter optional transaction memo',
                    helperText: 'Required for some exchanges',
                  ),
                  maxLines: 2,
                ),
              ],
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transaction Summary',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      _buildTransactionSummary(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _previewWithdrawal,
                icon: const Icon(Icons.send),
                label: const Text('Preview Withdrawal'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildValidationStatus() {
    if (_toAddressController.text.isEmpty) return null;

    if (_addressValidation == null) {
      return Container(
        padding: const EdgeInsets.all(4),
        width: 16,
        height: 16,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return Icon(
      _addressValidation!.isValid ? Icons.check_circle : Icons.error,
      color: _addressValidation!.isValid
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.error,
    );
  }

  Widget _buildTransactionSummary() {
    // final protocol = widget.asset.protocol;
    final balance = _selectedFromAddress?.balance ?? widget.pubkeys.balance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Available Balance:'),
            Text(
              '${balance.spendable} ${widget.asset.id.id}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        if (balance.unspendable > Decimal.zero) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Locked:'),
              Text(
                '${balance.unspendable} ${widget.asset.id.id}',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ],
        const Divider(),
        if (_selectedFee != null) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estimated Fee:'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [Text(_getFeeDisplay())],
              ),
            ],
          ),
        ],
        if (!_isMaxAmount && _amountController.text.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Amount:'),
              Text(
                '${_amountController.text} ${widget.asset.id.id}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
        if (_isIbcTransfer) ...[
          const Divider(),
          Text(
            'IBC transfers may take several minutes to complete and require '
            'additional fees on the destination chain.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
          ),
        ],
      ],
    );
  }

  String _getFeeDisplay() {
    final fee = _selectedFee;
    if (fee == null) return 'Calculating...';
    return fee.formatTotal();
  }
}
