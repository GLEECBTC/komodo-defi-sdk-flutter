import 'package:komodo_defi_sdk/src/transaction_history/transaction_storage.dart';

import 'transaction_storage_conformance.dart';

void main() {
  runTransactionStorageConformanceTests(
    name: 'InMemoryTransactionStorage',
    create: () async => InMemoryTransactionStorage(),
  );
}
