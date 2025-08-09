import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../llm/llama_worker.dart';
import '../llm/llama_ffi.dart'; // for clearHistory()
import '../models/chat_message.dart';
import '../models/model_metadata.dart';
import '../services/chat_storage.dart';
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
  String? _loadedModel; // model name (without .gguf)
  bool _isLoadingModel = false;
  bool _isThinking = false; // spinner for pending bot reply
  late final LlamaWorker _worker;

  // sessions
  String _sessionId = _newSessionId();
  static String _newSessionId() =>
      's_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

  @override
  void initState() {
    super.initState();
    _worker = LlamaWorker();
    _worker.start(); // background isolate
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
    // Clear native KV but keep the model loaded
    clearHistory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Started a new chat')),
      );
    }
  }

  Future<void> _handleSend(String prompt, ModelMetadata selectedModel) async {
    // 1) add user message + persist
    final userMsg = ChatMessage(
      id: DateTime.now().toIso8601String(),
      text: "🧑 $prompt",
      type: MessageType.user,
    );
    setState(() {
      _messages.insert(0, userMsg);
    });
    await ChatStorage.saveMessage(_sessionId, userMsg);

    final modelName = selectedModel.name;
    debugPrint(
        "[CHAT] selectedModel = ${selectedModel.name} (downloaded=${selectedModel.isDownloaded})");
    debugPrint("[CHAT] _loadedModel = $_loadedModel");

    // 2) load model in background isolate if needed — pass FULL PATH from UI isolate
    if (_loadedModel != modelName) {
      setState(() => _isLoadingModel = true);

      final dir = await getApplicationDocumentsDirectory();
      final hasExt = modelName.toLowerCase().endsWith('.gguf');
      final fullPath =
          '${dir.path}/${hasExt ? modelName : '$modelName.gguf'}';

      final ok = await _worker.loadModelAtPath(fullPath);
      setState(() => _isLoadingModel = false);

      if (!ok) {
        final err = ChatMessage(
          id: DateTime.now().toIso8601String(),
          text: "❌ Failed to load model: $modelName",
          type: MessageType.bot,
        );
        setState(() => _messages.insert(0, err));
        await ChatStorage.saveMessage(_sessionId, err);
        return;
      }
      _loadedModel = modelName;
    }

    // 3) show placeholder “typing …”
    final placeholderId = 'pending_${DateTime.now().microsecondsSinceEpoch}';
    final pending = ChatMessage(
      id: placeholderId,
      text: "🤖 …",
      type: MessageType.bot,
    );
    setState(() {
      _isThinking = true;
      _messages.insert(0, pending);
    });

    // 4) run inference in background isolate
    final replyText = await _worker.eval(prompt, maxTokens: 128);

    // 5) replace placeholder with final message + persist
    final idx = _messages.indexWhere((m) => m.id == placeholderId);
    final botMsg = ChatMessage(
      id: DateTime.now().toIso8601String(),
      text: "🤖 $replyText",
      type: MessageType.bot,
    );

    setState(() {
      _isThinking = false;
      if (idx >= 0) {
        _messages.removeAt(idx);
        _messages.insert(0, botMsg);
      } else {
        _messages.insert(0, botMsg);
      }
    });
    await ChatStorage.saveMessage(_sessionId, botMsg);
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
          // header with title + New Chat (+)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    "Chat with Local LLM",
                    style: TextStyle(fontSize: 20),
                  ),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                border: Border.all(color: Colors.amber.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text("⏳ Loading model..."),
            ),

          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) =>
                  MessageBubble(message: _messages[index]),
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
