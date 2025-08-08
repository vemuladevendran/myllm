// lib/layout/shell.dart
import 'package:flutter/material.dart';
import '../screens/model_manager_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/chat_history_screen.dart';
import '../screens/profile_screen.dart';
import 'side_nav_bar.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  String _selectedRoute = '/chat';

  Widget _getScreen() {
    switch (_selectedRoute) {
      case '/chat_history':
        return const ChatHistoryScreen();
      case '/profile':
        return const ProfileScreen();
      case '/models':
        return const ModelManagerScreen();
      case '/chat':
      default:
        return const ChatScreen();
    }
  }

  void _onItemSelected(String route) {
    Navigator.pop(context); // Close the drawer
    setState(() => _selectedRoute = route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: SideNavBar(
        selectedRoute: _selectedRoute,
        onItemSelected: _onItemSelected,
      ),
      appBar: AppBar(
        title: const Text('Chat with Gemini'),
      ),
      body: _getScreen(),
    );
  }
}
