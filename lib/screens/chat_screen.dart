// lib/screens/chat_screen.dart
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../llm/llama_worker.dart';
import '../models/chat_message.dart';
import '../models/model_metadata.dart';
import '../services/chat_storage.dart';
import '../services/file_naming.dart'; // toGgufFileName
import '../state/model_provider.dart';
import '../widgets/input_bar.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  String? _loadedModel; // DISPLAY name
  bool _isLoadingModel = false;
  bool _isThinking = false;
  late final LlamaWorker _worker;

  int _adaptiveMax = 128; // adaptive cap for streaming

  String _sessionId = _newSessionId();
  static String _newSessionId() =>
      's_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  @override
  void initState() {
    super.initState();
    _worker = LlamaWorker();
    _safeStart();
  }

  Future<void> _safeStart() async {
    try {
      await _worker.start();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Worker failed to start: $e')),
      );
    }
  }

  @override
  void dispose() {
    _worker.stop();
    super.dispose();
  }

  Future<void> _newChat() async {
    setState(() {
      _messages.clear();
      _sessionId = _newSessionId();
      _isThinking = false;
    });
    try { await _worker.clearHistory(); } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Started a new chat')),
      );
    }
  }

 Future<void> _handleSend(String prompt, ModelMetadata selectedModel) async {
  // Don’t allow overlapping requests while we stream
  if (_isThinking) return;

  // 1) Insert the user message immediately + persist
  final userMsg = ChatMessage(
    id: DateTime.now().toIso8601String(),
    text: "🧑 $prompt",
    type: MessageType.user,
  );
  setState(() => _messages.insert(0, userMsg));
  await ChatStorage.saveMessage(_sessionId, userMsg);

  final modelName = selectedModel.name; // display name (may contain '/')

  // 2) Load model if needed (build absolute path using the *sanitized file name*)
  if (_loadedModel != modelName) {
    setState(() => _isLoadingModel = true);
    bool ok = false;
    String? err;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeFile = toGgufFileName(modelName);         // e.g. "Microsoft/Phi-3" -> "Microsoft_Phi-3.gguf"
      final fullPath = '${dir.path}/$safeFile';           // DO NOT replace slashes in the full path

      debugPrint('[CHAT] Trying to load: $fullPath');
      debugPrint('[CHAT] File exists? ${await File(fullPath).exists()}');

      ok = await _worker.loadModelAtPath(
        fullPath,
        timeout: const Duration(seconds: 90),
      );
    } catch (e) {
      err = e.toString();
    } finally {
      if (!mounted) return;
      setState(() => _isLoadingModel = false);
    }

    if (!ok) {
      setState(() {
        _messages.insert(
          0,
          ChatMessage(
            id: DateTime.now().toIso8601String(),
            text: "❌ Failed to load model: ${err ?? modelName}",
            type: MessageType.bot,
          ),
        );
      });
      return;
    }

    _loadedModel = modelName;
  }

  // 3) Create a live placeholder and stream tokens into it
  final placeholderId = 'pending_${DateTime.now().microsecondsSinceEpoch}';
  var liveText = '🤖 ';
  setState(() {
    _isThinking = true;
    _messages.insert(
      0,
      ChatMessage(id: placeholderId, text: liveText, type: MessageType.bot),
    );
  });

  final start = DateTime.now();
  int tokenPieces = 0;

  try {
    // 4) Stream eval with watchdog (won’t hang the UI)
    await _worker.streamEval(
      prompt,
      maxTokens: _adaptiveMax,                       // adaptive cap you track in state
      maxTotalTime: const Duration(seconds: 180),    // hard cap
      maxSilence: const Duration(seconds: 15),       // cancel if no activity for 15s
      onToken: (piece) {
        tokenPieces++;
        liveText += piece;

        // Update the placeholder bubble quickly
        final idx = _messages.indexWhere((m) => m.id == placeholderId);
        if (idx >= 0) {
          setState(() {
            _messages[idx] =
                ChatMessage(id: placeholderId, text: liveText, type: MessageType.bot);
          });
        }
      },
    );

    // 5) Finalize + persist
    final botMsg = ChatMessage(
      id: DateTime.now().toIso8601String(),
      text: liveText, // already includes 🤖 prefix
      type: MessageType.bot,
    );

    setState(() {
      _isThinking = false;
      final idx = _messages.indexWhere((m) => m.id == placeholderId);
      if (idx >= 0) {
        _messages.removeAt(idx);
        _messages.insert(0, botMsg);
      } else {
        _messages.insert(0, botMsg);
      }
    });
    await ChatStorage.saveMessage(_sessionId, botMsg);

    // 6) Adapt future maxTokens toward recent length (+headroom)
    final target = (0.7 * _adaptiveMax + 0.3 * (tokenPieces + 32)).toInt();
    _adaptiveMax = target.clamp(64, 512);
    debugPrint('[CHAT] adaptiveMax -> $_adaptiveMax (pieces=$tokenPieces, dt=${DateTime.now().difference(start).inSeconds}s)');
  } catch (e) {
    // Stream failed or timed out — replace placeholder with error
    setState(() {
      _isThinking = false;
      final idx = _messages.indexWhere((m) => m.id == placeholderId);
      if (idx >= 0) _messages.removeAt(idx);
      _messages.insert(
        0,
        ChatMessage(
          id: DateTime.now().toIso8601String(),
          text: '❌ Stream failed: $e',
          type: MessageType.bot,
        ),
      );
    });
  }
}


  @override
  Widget build(BuildContext context) {
    final downloadedModels = context
        .watch<ModelProvider>()
        .models
        .where((m) => m.isDownloaded)
        .toList();

    return SafeArea(
      child: Column(
        children: [
          // header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Chat with Local LLM', style: TextStyle(fontSize: 20)),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'New chat',
                  onPressed: _newChat,
                ),
              ],
            ),
          ),

          if (_isLoadingModel)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                border: Border.all(color: Colors.amber.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('⏳ Loading model...'),
            ),

          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) => MessageBubble(message: _messages[index]),
            ),
          ),

          if (_isThinking)
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: _TypingIndicator(),
            ),

          InputBar(
            onSend: _handleSend,
            downloadedModels: downloadedModels,
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        SizedBox(width: 12),
        CircularProgressIndicator(strokeWidth: 2),
        SizedBox(width: 8),
        Text('Generating…'),
      ],
    );
  }
}
