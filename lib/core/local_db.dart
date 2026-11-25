import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// On-device SQLite: saved handwritten notes + downloaded study files.
/// Everything here is readable with no internet.
class LocalDb {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'huddle.db'),
      version: 1,
      onCreate: (d, v) async {
        await d.execute('''CREATE TABLE notes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL, json TEXT NOT NULL, created_at INTEGER NOT NULL)''');
        await d.execute('''CREATE TABLE downloads(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          remote_path TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
          local_path TEXT NOT NULL, saved_at INTEGER NOT NULL)''');
      },
    );
    return _db!;
  }

  // ---- notes ----
  static Future<int> saveNotes(String title, Map<String, dynamic> json) async =>
      (await db).insert('notes', {
        'title': title,
        'json': jsonEncode(json),
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  static Future<List<Map<String, dynamic>>> listNotes() async =>
      (await db).query('notes', orderBy: 'created_at DESC');

  static Future<void> deleteNotes(int id) async =>
      (await db).delete('notes', where: 'id=?', whereArgs: [id]);

  // ---- downloaded study documents ----
  static Future<void> addDownload(
          String remotePath, String name, String localPath) async =>
      (await db).insert(
          'downloads',
          {
            'remote_path': remotePath,
            'name': name,
            'local_path': localPath,
            'saved_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<Map<String, dynamic>?> findDownload(String remotePath) async {
    final r = await (await db)
        .query('downloads', where: 'remote_path=?', whereArgs: [remotePath]);
    return r.isEmpty ? null : r.first;
  }

  static Future<List<Map<String, dynamic>>> listDownloads() async =>
      (await db).query('downloads', orderBy: 'saved_at DESC');
}
