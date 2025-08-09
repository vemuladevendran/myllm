import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/input_bar.dart';
import '../models/chat_message.dart';
import '../state/model_provider.dart';
import '../models/model_metadata.dart';
import '../llm/llama_ffi.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  String? _loadedModel; // this stores the model *name* (without .gguf)
  bool _isLoadingModel = false;

  Future<void> _handleSend(String prompt, ModelMetadata selectedModel) async {
    // Insert the user message immediately
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          id: DateTime.now().toIso8601String(),
          text: "🧑 $prompt",
          type: MessageType.user,
        ),
      );
    });

    final modelName = selectedModel.name; // <- pass plain name, no ".gguf"
    debugPrint("[CHAT] selectedModel = ${selectedModel.name} (downloaded=${selectedModel.isDownloaded})");
    debugPrint("[CHAT] _loadedModel = $_loadedModel");

    // Load model if it's not the current one
    if (_loadedModel != modelName) {
      setState(() => _isLoadingModel = true);
      debugPrint("[CHAT] Loading model: $modelName");

      final ok = await loadModel(modelName);
      setState(() => _isLoadingModel = false);

      if (!ok) {
        debugPrint("[CHAT] ❌ Failed to load model: $modelName");
        setState(() {
          _messages.insert(
            0,
            ChatMessage(
              id: DateTime.now().toIso8601String(),
              text: "❌ Failed to load model: $modelName",
              type: MessageType.bot,
            ),
          );
        });
        return;
      }

      debugPrint("[CHAT] ✅ Model loaded: $modelName");
      _loadedModel = modelName;
    }

    // Run inference
    debugPrint("[CHAT] Running model: $_loadedModel with prompt='${prompt.replaceAll('\n', ' ')}'");
    final reply = await runModel(prompt, maxTokens: 64);

    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          id: DateTime.now().toIso8601String(),
          text: "🤖 $reply",
          type: MessageType.bot,
        ),
      );
    });
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
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text("Chat with Local LLM", style: TextStyle(fontSize: 20)),
          ),
          if (_isLoadingModel)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          InputBar(
            onSend: _handleSend,
            downloadedModels: downloadedModels,
          ),
        ],
      ),
    );
  }
}
