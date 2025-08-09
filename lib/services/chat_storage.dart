// services/chat_storage.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/chat_message.dart';

class ChatStorage {
  static Future<String> _baseDir() async {
    final d = await getApplicationDocumentsDirectory();
    final path = '${d.path}/chats';
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return path;
  }

  static Future<File> _fileForSession(String sessionId) async {
    final dir = await _baseDir();
    return File('$dir/$sessionId.json');
  }

  static Future<void> saveMessage(String sessionId, ChatMessage m) async {
    final f = await _fileForSession(sessionId);
    List<Map<String, dynamic>> list = [];
    if (await f.exists()) {
      final txt = await f.readAsString();
      if (txt.isNotEmpty) {
        list = (jsonDecode(txt) as List).cast<Map<String, dynamic>>();
      }
    }
    list.add({
      'id': m.id,
      'text': m.text,
      'type': m.type.name,
      'ts': DateTime.now().toIso8601String(),
    });
    await f.writeAsString(jsonEncode(list));
  }

  static Future<List<ChatMessage>> loadSession(String sessionId) async {
    final f = await _fileForSession(sessionId);
    if (!await f.exists()) return [];
    final txt = await f.readAsString();
    if (txt.isEmpty) return [];
    final list = (jsonDecode(txt) as List).cast<Map<String, dynamic>>();
    return list
        .map((m) => ChatMessage(
              id: m['id'] as String,
              text: m['text'] as String,
              type: (m['type'] as String) == 'user'
                  ? MessageType.user
                  : MessageType.bot,
            ))
        .toList();
  }

  // ---------- NEW: listing & deleting ----------

  static Future<List<ChatSessionMeta>> listSessions() async {
    final dirPath = await _baseDir();
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();

    final metas = <ChatSessionMeta>[];
    for (final f in files) {
      final sessionId =
          f.uri.pathSegments.last.replaceAll('.json', ''); // filename
      int count = 0;
      String preview = '';
      try {
        final txt = await f.readAsString();
        if (txt.isNotEmpty) {
          final list = (jsonDecode(txt) as List).cast<Map<String, dynamic>>();
          count = list.length;
          if (count > 0) {
            final last = list.last;
            final t = (last['text'] as String?) ?? '';
            preview = t.replaceAll('\n', ' ');
            if (preview.length > 80) preview = '${preview.substring(0, 80)}…';
          }
        }
      } catch (_) {}
      final stat = await f.stat();
      metas.add(ChatSessionMeta(
        id: sessionId,
        lastModified: stat.modified,
        messageCount: count,
        preview: preview,
      ));
    }

    metas.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return metas;
  }

  static Future<void> deleteSession(String sessionId) async {
    final f = await _fileForSession(sessionId);
    if (await f.exists()) {
      await f.delete();
    }
  }
}

class ChatSessionMeta {
  final String id;
  final DateTime lastModified;
  final int messageCount;
  final String preview;

  ChatSessionMeta({
    required this.id,
    required this.lastModified,
    required this.messageCount,
    required this.preview,
  });
}
