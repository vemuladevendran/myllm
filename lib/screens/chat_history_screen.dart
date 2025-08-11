// screens/chat_history_screen.dart
import 'package:flutter/material.dart';
import '../services/chat_storage.dart';
import '../models/chat_message.dart';
import '../widgets/message_bubble.dart';

class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  late Future<List<ChatSessionMeta>> _future;

  @override
  void initState() {
    super.initState();
    _future = ChatStorage.listSessions();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = ChatStorage.listSessions();
    });
    await _future;
  }

  void _openSession(ChatSessionMeta meta) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChatSessionView(sessionId: meta.id),
    ));
  }

  Future<void> _deleteSession(ChatSessionMeta meta) async {
    await ChatStorage.deleteSession(meta.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${meta.id}')),
      );
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Chat History')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ChatSessionMeta>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Error: ${snap.error}'));
            }
            final sessions = snap.data ?? [];
            if (sessions.isEmpty) {
              return const Center(
                child: Text('No chats yet. Start a new chat to see it here.'),
              );
            }

            return ListView.separated(
              itemCount: sessions.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                color: theme.dividerColor.withOpacity(0.3),
              ),
              itemBuilder: (context, i) {
                final s = sessions[i];
                return Dismissible(
                  key: ValueKey(s.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => _deleteSession(s),
                  child: ListTile(
                    title: Text(
                      s.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      s.preview.isNotEmpty
                          ? s.preview
                          : '(no messages yet)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatWhen(s.lastModified),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text('${s.messageCount} msgs',
                            style: theme.textTheme.labelSmall),
                      ],
                    ),
                    onTap: () => _openSession(s),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _formatWhen(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    if (that == today) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
}

class ChatSessionView extends StatefulWidget {
  final String sessionId;
  const ChatSessionView({super.key, required this.sessionId});

  @override
  State<ChatSessionView> createState() => _ChatSessionViewState();
}

class _ChatSessionViewState extends State<ChatSessionView> {
  late Future<List<ChatMessage>> _future;

  @override
  void initState() {
    super.initState();
    _future = ChatStorage.loadSession(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Session: ${widget.sessionId}')),
      body: FutureBuilder<List<ChatMessage>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final msgs = snap.data ?? [];
          if (msgs.isEmpty) {
            return const Center(child: Text('No messages in this session.'));
          }
          // Display like ChatScreen (latest at top)
          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: msgs.length,
            itemBuilder: (context, i) {
              return MessageBubble(message: msgs[msgs.length - 1 - i]);
            },
          );
        },
      ),
    );
  }
}
