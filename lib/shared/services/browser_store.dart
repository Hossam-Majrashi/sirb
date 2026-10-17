import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/browser_tab.dart';
import '../models/error_log_entry.dart';

Future<String> _encodeSnapshot(List<Map<String, Object?>> snapshot) =>
    Isolate.run(() => jsonEncode(snapshot));

class BrowserStore {
  BrowserStore(this.db);
  final Database db;
  static Future<BrowserStore> open(String path) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.rawQuery('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA synchronous=FULL');
          await db.execute('PRAGMA foreign_keys=ON');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE session(id INTEGER PRIMARY KEY CHECK(id=1), snapshot TEXT NOT NULL, active TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE visits(id INTEGER PRIMARY KEY, url TEXT NOT NULL, title TEXT NOT NULL, icon TEXT NOT NULL, time INTEGER NOT NULL)',
          );
          await db.execute('CREATE INDEX visit_time ON visits(time)');
          await db.execute('CREATE INDEX visit_url ON visits(url)');
          await db.execute(
            'CREATE TABLE closures(id INTEGER PRIMARY KEY, time INTEGER NOT NULL, snapshot TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE downloads(id INTEGER PRIMARY KEY, snapshot TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE error_logs(id INTEGER PRIMARY KEY AUTOINCREMENT, time INTEGER NOT NULL, type TEXT NOT NULL, message TEXT NOT NULL, url TEXT, details TEXT)',
          );
          await db.execute('CREATE INDEX error_log_time ON error_logs(time)');
          await db.execute('CREATE INDEX error_log_type ON error_logs(type)');
        },
        onOpen: (db) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS error_logs(id INTEGER PRIMARY KEY AUTOINCREMENT, time INTEGER NOT NULL, type TEXT NOT NULL, message TEXT NOT NULL, url TEXT, details TEXT)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS error_log_time ON error_logs(time)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS error_log_type ON error_logs(type)',
          );
        },
      ),
    );
    return BrowserStore(db);
  }

  Future<void> _tail = Future.value();
  Future<void> _serialize(Future<void> Function() write) {
    final operation = _tail.then((_) => write());
    _tail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        stderr.writeln('Sirb SQLite: $error');
      },
    );
    return operation;
  }

  ({List<Map<String, Object?>> tabs, String active})? _pendingSession;
  Future<void>? _sessionSave;
  Future<void> saveSession(List<BrowserTab> tabs, String active) {
    _pendingSession = (
      tabs: tabs.map((t) => t.toMap()).toList(),
      active: active,
    );
    return _sessionSave ??=
        _serialize(() async {
          while (_pendingSession != null) {
            final pending = _pendingSession!;
            _pendingSession = null;
            final json = await _encodeSnapshot(pending.tabs);
            await db.transaction((tx) async {
              await tx.insert('session', {
                'id': 1,
                'snapshot': json,
                'active': pending.active,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            });
          }
        }).whenComplete(() {
          _sessionSave = null;
        });
  }

  Future<void> commitClosure(
    List<BrowserTab> closed,
    List<BrowserTab> remaining,
    String active,
  ) {
    final meaningfulClosed = closed
        .where((t) => t.url.isNotEmpty && t.url != 'sirb:new')
        .toList();
    final closedSnapshot = meaningfulClosed.map((t) => t.toMap()).toList();
    final remainingSnapshot = remaining.map((t) => t.toMap()).toList();
    return _serialize(() async {
      final closure = await _encodeSnapshot(closedSnapshot),
          session = await _encodeSnapshot(remainingSnapshot);
      await db.transaction((tx) async {
        if (closedSnapshot.isNotEmpty) {
          final latest = await tx.query(
            'closures',
            orderBy: 'time DESC',
            limit: 1,
          );
          if (latest.isEmpty || latest.first['snapshot'] != closure) {
            await tx.insert('closures', {
              'time': DateTime.now().millisecondsSinceEpoch,
              'snapshot': closure,
            });
          }
        }
        await tx.insert('session', {
          'id': 1,
          'snapshot': session,
          'active': active,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    });
  }

  Future<void> updateVisitMetadata(BrowserTab tab) async {
    await db.rawUpdate(
      'UPDATE visits SET title=?,icon=? WHERE id=(SELECT id FROM visits WHERE url=? ORDER BY time DESC LIMIT 1)',
      [tab.title, tab.icon, tab.url],
    );
  }

  Future<Map<String, dynamic>?> session() async {
    final rows = await db.query('session');
    if (rows.isEmpty) return null;
    return {
      'tabs': jsonDecode(rows.first['snapshot'] as String),
      'active': rows.first['active'],
    };
  }

  Future<void> recordVisit(BrowserTab tab) async {
    if (!['http', 'https', 'file'].contains(Uri.tryParse(tab.url)?.scheme)) {
      return;
    }
    await db.insert('visits', {
      'url': tab.url,
      'title': tab.title,
      'icon': tab.icon,
      'time': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> visits([String query = '']) => db.query(
    'visits',
    where: 'url LIKE ? OR title LIKE ?',
    whereArgs: ['%$query%', '%$query%'],
    orderBy: 'time DESC',
    limit: 500,
  );
  Future<List<Map<String, Object?>>> mostVisited() => db.rawQuery(
    'SELECT v.url,v.title,v.icon,totals.count FROM (SELECT url,COUNT(*) AS count,MAX(id) AS latest FROM visits GROUP BY url ORDER BY count DESC LIMIT 12) totals JOIN visits v ON v.id=totals.latest ORDER BY totals.count DESC',
  );
  Future<void> deleteVisit(int id) =>
      db.delete('visits', where: 'id=?', whereArgs: [id]);
  Future<void> clearVisits({DateTime? since}) => db.delete(
    'visits',
    where: since == null ? null : 'time>=?',
    whereArgs: since == null ? null : [since.millisecondsSinceEpoch],
  );
  Future<void> recordClosure(List<BrowserTab> tabs) async {
    final meaningful = tabs
        .where((t) => t.url.isNotEmpty && t.url != 'sirb:new')
        .toList();
    if (meaningful.isEmpty) return;
    final snapshot = jsonEncode(meaningful.map((t) => t.toMap()).toList());
    final latest = await db.query('closures', orderBy: 'time DESC', limit: 1);
    if (latest.isNotEmpty && latest.first['snapshot'] == snapshot) {
      return;
    }
    await db.insert('closures', {
      'time': DateTime.now().millisecondsSinceEpoch,
      'snapshot': snapshot,
    });
  }

  Future<List<Map<String, Object?>>> closures() =>
      db.query('closures', orderBy: 'time DESC');
  Future<void> removeClosure(int id) =>
      db.delete('closures', where: 'id=?', whereArgs: [id]);
  Future<void> clearClosures() => db.delete('closures');
  Future<void> saveDownload(Map<String, dynamic> d) async => db.insert(
    'downloads',
    {'id': d['id'], 'snapshot': jsonEncode(d)},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  Future<List<Map<String, dynamic>>> downloads() async =>
      (await db.query('downloads', orderBy: 'id DESC'))
          .map(
            (r) => Map<String, dynamic>.from(
              jsonDecode(r['snapshot'] as String) as Map,
            ),
          )
          .toList();

  Future<void> recordErrorLog({
    required String type,
    required String message,
    String? url,
    String? details,
  }) {
    final row = <String, Object?>{
      'time': DateTime.now().millisecondsSinceEpoch,
      'type': type,
      'message': message,
      'url': url,
      'details': details,
    };
    return _serialize(() async {
      await db.insert('error_logs', row);
    });
  }

  Future<List<ErrorLogEntry>> errorLogs({
    String? type,
    String? query,
    int? limit = 1000,
    int offset = 0,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (type == 'errors') {
      conditions.add("type NOT IN ('ad', 'performance', 'compatibility')");
    } else if (type != null && type.isNotEmpty && type != 'all') {
      conditions.add('type = ?');
      args.add(type);
    }
    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      conditions.add('(message LIKE ? OR url LIKE ? OR details LIKE ?)');
      args.addAll([q, q, q]);
    }
    final rows = await db.query(
      'error_logs',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'time DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => ErrorLogEntry.fromMap(r)).toList();
  }

  Future<void> deleteErrorLog(int id) =>
      db.delete('error_logs', where: 'id = ?', whereArgs: [id]);

  Future<void> clearErrorLogs({String? type}) => db.delete(
    'error_logs',
    where: type == 'errors'
        ? "type NOT IN ('ad', 'performance', 'compatibility')"
        : (type == null || type.isEmpty || type == 'all' ? null : 'type = ?'),
    whereArgs: type == 'errors' || type == null || type.isEmpty || type == 'all'
        ? null
        : [type],
  );

  Future<int> errorLogCount({String? type}) async {
    final String sql;
    final List<Object?> args;
    if (type == 'errors') {
      sql =
          "SELECT COUNT(*) as count FROM error_logs WHERE type NOT IN ('ad', 'performance', 'compatibility')";
      args = [];
    } else if (type == null || type.isEmpty || type == 'all') {
      sql = 'SELECT COUNT(*) as count FROM error_logs';
      args = [];
    } else {
      sql = 'SELECT COUNT(*) as count FROM error_logs WHERE type = ?';
      args = [type];
    }
    final rows = await db.rawQuery(sql, args);
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> close() async {
    await _tail;
    await db.close();
  }
}
