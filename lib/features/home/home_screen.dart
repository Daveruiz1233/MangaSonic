import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:manga_sonic/features/browse/site_list_tab.dart';
import 'package:manga_sonic/features/library/library_screen.dart';
import 'package:manga_sonic/features/downloads/downloads_screen.dart';
import 'package:manga_sonic/features/settings/settings_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1;

  // Lazy-loaded screens - only created when first accessed
  final Map<int, Widget> _screenCache = {};

  Widget _getScreen(int index) {
    // Return cached screen if available
    if (_screenCache.containsKey(index)) {
      return _screenCache[index]!;
    }

    // Create and cache the screen on first access
    late final Widget screen;
    switch (index) {
      case 0:
        screen = const SiteListTab();
      case 1:
        screen = const LibraryScreen();
      case 2:
        screen = const DownloadsScreen();
      case 3:
        screen = const SettingsTab();
      default:
        screen = const SizedBox.shrink();
    }

    _screenCache[index] = screen;
    return screen;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBody: true,
      body: _getScreen(_currentIndex),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(Icons.explore, 'BROWSE', 0, theme),
                  _buildNavItem(Icons.library_books, 'LIBRARY', 1, theme),
                  _buildNavItem(Icons.download, 'DOWNLOADS', 2, theme),
                  _buildNavItem(Icons.settings, 'SETTINGS', 3, theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    String label,
    int index,
    ThemeData theme,
  ) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? theme.primaryColor : Colors.grey;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 75,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: isSelected
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withValues(alpha: 0.35),
                          blurRadius: 20,
                          spreadRadius: 8,
                        ),
                      ],
                    )
                  : const BoxDecoration(shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                letterSpacing: 0.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
