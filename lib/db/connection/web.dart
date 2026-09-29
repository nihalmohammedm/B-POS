import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openConnection({String name = 'bistro_pos'}) {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: name,
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}
