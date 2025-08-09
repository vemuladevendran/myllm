import 'package:flutter/material.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.type == MessageType.user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color userColor = isDark
        ? Colors.deepPurple.shade400.withOpacity(0.3) // softer for dark
        : Colors.deepPurple.shade50;                  // light purple for light mode

    final Color botColor = isDark
        ? Colors.grey.shade800.withOpacity(0.7)       // dark bubble
        : Colors.grey.shade200;                       // light grey for light mode

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? userColor : botColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
