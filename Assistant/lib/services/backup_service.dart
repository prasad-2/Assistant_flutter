// Backup / restore of the complete database file.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/models.dart';
import 'auth_service.dart';

class BackupService {
  /// Saves a copy of the whole database through the system "save file"
  /// dialog. Returns the saved path, or null when the user cancelled.
  static Future<String?> backup() async {
    final dbPath = await AppDatabase.instance.path;
    // closing flushes everything into the single .db file
    await AppDatabase.instance.close();
    final bytes = await File(dbPath).readAsBytes();
    await AppDatabase.instance.db; // reopen
    final name =
        'finance_todo_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.db';
    return LockGuard.run(() => FilePicker.platform
        .saveFile(dialogTitle: 'Save backup', fileName: name, bytes: bytes));
  }

  /// Replaces the complete database with a backup file chosen by the user.
  /// The file is validated first. Returns false when the user cancelled.
  static Future<bool> restore() async {
    final res = await LockGuard.run(() =>
        FilePicker.platform.pickFiles(type: FileType.any, withData: true));
    if (res == null || res.files.isEmpty) return false;
    final f = res.files.single;
    final bytes = f.bytes ??
        (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null || bytes.length < 100) {
      throw ValidationException('The selected file is empty or unreadable.');
    }
    // every SQLite file starts with this 15 byte header
    final header = String.fromCharCodes(bytes.sublist(0, 15));
    if (header != 'SQLite format 3') {
      throw ValidationException('This is not a valid backup file.');
    }

    final dbPath = await AppDatabase.instance.path;
    final tmp = '$dbPath.restore_tmp';
    await File(tmp).writeAsBytes(bytes, flush: true);

    // make sure it really is a database of this app before touching ours
    try {
      final test = await openDatabase(tmp, readOnly: true);
      final tables = (await test
              .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toSet();
      await test.close();
      const need = {'accounts', 'categories', 'transactions', 'todos', 'todo_groups'};
      if (!tables.containsAll(need)) {
        throw ValidationException('This file is not a backup of this app.');
      }
    } catch (e) {
      await File(tmp).delete();
      if (e is ValidationException) rethrow;
      throw ValidationException('This is not a valid backup file.');
    }

    // swap the files; reopening runs migrations if the backup is an old version
    await AppDatabase.instance.close();
    for (final suffix in ['-wal', '-shm', '-journal']) {
      final x = File('$dbPath$suffix');
      if (await x.exists()) await x.delete();
    }
    await File(tmp).copy(dbPath);
    await File(tmp).delete();
    await AppDatabase.instance.db;
    return true;
  }
}
