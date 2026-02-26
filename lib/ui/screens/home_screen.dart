import 'package:flutter/material.dart';
import 'library_screen.dart';
import 'downloads_screen.dart';
import 'site_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const SiteListTab(),
    const LibraryScreen(),
    const DownloadsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.deepPurpleAccent,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1E1E1E),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Browse'),
          BottomNavigationBarItem(icon: Icon(Icons.library_books), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Downloads'),
        ],
      ),
    );
  }
}

class SiteListTab extends StatelessWidget {
  const SiteListTab({Key? key}) : super(key: key);

  final List<Map<String, String>> sites = const [
    {'name': 'ManhuaTop', 'url': 'https://manhuatop.org/'},
    {'name': 'AsuraComic', 'url': 'https://asuracomic.net/'},
    {'name': 'ManhuaPlus', 'url': 'https://manhuaplus.com/'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MangaSonic')),
      body: ListView.builder(
        itemCount: sites.length,
        itemBuilder: (context, index) {
          final site = sites[index];
          return ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.deepPurple,
              child: Icon(Icons.public, color: Colors.white),
            ),
            title: Text(site['name']!),
            subtitle: Text(site['url']!),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SiteScreen(siteName: site['name']!, siteUrl: site['url']!),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
