// iOS: the local database stays out of backups and of a restore onto another iPhone (audit H-06).
import 'package:flutter_test/flutter_test.dart';
import 'package:wattbyte/storage/database.dart';

import 'support/fake_system.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the files SQLite keeps for the database are all named', () {
    expect(WattByteDb.filesOf('/data/wattbyte.db'), [
      '/data/wattbyte.db',
      '/data/wattbyte.db-wal',
      '/data/wattbyte.db-shm',
      '/data/wattbyte.db-journal',
    ]);
  });

  test('the request reaches the native side with every path', () async {
    final fake = FakeSystem(platform: HarnessPlatform.ios);
    addTearDown(fake.dispose);
    await fake.system
        .excludeFromBackup(WattByteDb.filesOf('/Documents/wattbyte.db'));
    expect(
        fake.excludedFromBackup, WattByteDb.filesOf('/Documents/wattbyte.db'));
  });

  test('a native side without the call is not an error', () async {
    final fake = FakeSystem(platform: HarnessPlatform.ios);
    addTearDown(fake.dispose);
    fake.unsupported.add('excludeFromBackup');
    await fake.system.excludeFromBackup(['/x']);
  });
}
