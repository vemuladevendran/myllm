// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/input_bar.dart';
import '../models/chat_message.dart';
import '../state/model_provider.dart';
import '../models/model_metadata.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];

  void _handleSend(String text, String model) {
    final message = ChatMessage(
      id: DateTime.now().toString(),
      text: '[$model] $text',
      type: MessageType.user,
    );
    setState(() => _messages.insert(0, message));

    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        _messages.insert(
          0,
          ChatMessage(
            id: DateTime.now().toString(),
            text: "Bot ($model) reply to: $text",
            type: MessageType.bot,
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<ModelMetadata> downloadedModels =
        context.watch<ModelProvider>().models.where((m) => m.isDownloaded).toList();

    return SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text("Chat with Gemini", style: TextStyle(fontSize: 20)),
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
