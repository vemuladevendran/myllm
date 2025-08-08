// lib/layout/side_nav_bar.dart
import 'package:flutter/material.dart';

class SideNavBar extends StatelessWidget {
  final void Function(String route) onItemSelected;
  final String selectedRoute;

  const SideNavBar({
    super.key,
    required this.onItemSelected,
    required this.selectedRoute,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: const Text(
                'Chat with Gemini',
                style: TextStyle(fontSize: 20, color: Colors.white),
              ),
            ),
            _buildNavItem(context, 'Chat', '/chat'),
            _buildNavItem(context, 'Chat History', '/chat_history'),
            _buildNavItem(context, 'Models', '/models'),
            _buildNavItem(context, 'Profile', '/profile'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, String title, String route) {
    return ListTile(
      selected: selectedRoute == route,
      leading: Icon(
        route == '/chat' ? Icons.chat :
        route == '/chat_history' ? Icons.history :
        Icons.person,
      ),
      title: Text(title),
      onTap: () => onItemSelected(route),
    );
  }
}
