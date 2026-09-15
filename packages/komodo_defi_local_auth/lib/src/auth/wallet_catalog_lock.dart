export 'wallet_catalog_lock_native.dart'
    if (dart.library.js_interop) 'wallet_catalog_lock_web.dart';

/// SDK-owned identity of one local wallet entry, renewed on recreation.
const walletEntryIdMetadataKey = '_wallet_entry_id';
