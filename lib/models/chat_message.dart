enum MessageType { user, bot }

class ChatMessage {
  final String id;
  final String text;
  final MessageType type;

  ChatMessage({required this.id, required this.text, required this.type});
}
