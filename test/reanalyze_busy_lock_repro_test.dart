// Phase 3C2A characterization of full re-analysis and the process-wide
// DerivationEngine latch. Every test uses a disposable, empty SQLite database;
// no user data or persisted application database is opened.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String databasePath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'phase_3c2a_reanalyze_busy_lock_test.db';
    final directory = await databaseFactory.getDatabasesPath();
    databasePath = p.join(directory, LocalDb.dbName);
  });

  setUp(() async {
    DerivationEngine.debugRunning = false;
    await LocalDb.close();
    await databaseFactory.deleteDatabase(databasePath);
    await LocalDb.instance; // create an isolated schema for this test
  });

  tearDown(() async {
    DerivationEngine.debugRunning = false;
    await LocalDb.close();
    await databaseFactory.deleteDatabase(databasePath);
  });

  test('idle full re-analysis completes with no seeded days', () async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);

    // The temporary database is empty: this proves a completed no-work pass,
    // not that any day was derived.
    expect(await app.reanalyzeAll(), 0);
    expect(app.reanalyzing, isFalse);
    expect(app.reanalyzeProgress, isEmpty);
    expect(DerivationEngine().running, isFalse);

    // A later idle request is accepted too; it still has no seeded day to run.
    expect(await app.reanalyzeAll(), 0);
    expect(app.reanalyzing, isFalse);
  });

  test('KNOWN DEFECT: full re-analysis under another pass latch reports zero '
      'and returns without queuing', () async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);

    // This is the existing deterministic test hook for the same process-wide
    // latch held by a concurrent derive pass. No wall-clock synchronization.
    DerivationEngine.debugRunning = true;
    final request = app.reanalyzeAll();

    // Current behavior: DerivationEngine.run returns 0 immediately. The
    // request resolves while the other-pass latch remains held, so it was not
    // queued for later execution. AppState exposes that as the same zero used
    // for a completed no-work request.
    expect(await request, 0);
    expect(DerivationEngine().running, isTrue);
    expect(app.reanalyzing, isFalse);
    expect(app.reanalyzeProgress, isEmpty);

    DerivationEngine.debugRunning = false;
    expect(
      await app.reanalyzeAll(),
      0,
      reason: 'a later explicit request can run after the latch is released',
    );
    expect(DerivationEngine().running, isFalse);
  });

  test(
    'a successful empty engine pass releases the process-wide latch',
    () async {
      final engine = DerivationEngine();

      expect(await engine.run(const Profile(), heavy: true, force: true), 0);
      expect(engine.running, isFalse);
      expect(engine.snapshot()['running'], isFalse);
    },
  );

  test('an error releases the latch and later requests can run', () async {
    final engine = DerivationEngine();
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    final db = await LocalDb.instance;

    // Break only the disposable test schema. The first decoded-store query in
    // run() fails deterministically; no malformed input or real database is
    // involved.
    await db.execute('DROP TABLE decoded_onehz');
    expect(await engine.run(const Profile(), heavy: true, force: true), 0);
    expect(engine.snapshot()['last_error'], contains('decoded_onehz'));
    expect(
      engine.running,
      isFalse,
      reason: 'the finally path must release the latch after an error',
    );

    // Exercise the public full-reanalysis wrapper against the same isolated
    // schema failure and verify its own visible busy state is also cleared.
    expect(await app.reanalyzeAll(), 0);
    expect(app.reanalyzing, isFalse);
    expect(app.reanalyzeProgress, isEmpty);
    expect(engine.running, isFalse);

    // Replace the isolated DB with a fresh schema, then prove a later request
    // can acquire and release the latch normally.
    await LocalDb.close();
    await databaseFactory.deleteDatabase(databasePath);
    await LocalDb.instance;
    expect(await engine.run(const Profile(), heavy: true, force: true), 0);
    expect(engine.running, isFalse);
    expect(
      await app.reanalyzeAll(),
      0,
      reason: 'a later AppState request is accepted after DB recovery',
    );
    expect(app.reanalyzing, isFalse);
  });
}
