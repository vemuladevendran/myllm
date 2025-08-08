// lib/screens/chat_screen.dart
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
  String? _loadedModel;

  Future<void> _handleSend(String prompt, ModelMetadata selectedModel) async {
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          id: DateTime.now().toString(),
          text: "🧑 $prompt",
          type: MessageType.user,
        ),
      );
    });

    final modelFilename = "${selectedModel.name.replaceAll(' ', '_')}.gguf";

    if (_loadedModel != modelFilename) {
      final success = await loadModel(modelFilename);
      if (!success) {
        setState(() {
          _messages.insert(
            0,
            ChatMessage(
              id: DateTime.now().toString(),
              text: "❌ Failed to load model: $modelFilename",
              type: MessageType.bot,
            ),
          );
        });
        return;
      }
      _loadedModel = modelFilename;
    }

    final reply = await runModel(prompt);
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          id: DateTime.now().toString(),
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
