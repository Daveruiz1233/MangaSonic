import 'package:flutter/material.dart';
import 'dart:ui';
import 'library_screen.dart';
import 'downloads_screen.dart';
import 'site_screen.dart';
import 'palette_personalizer_screen.dart';
import 'add_source_screen.dart';
import 'package:manga_sonic/data/db/custom_source_db.dart';
import 'package:manga_sonic/services/nim_ai_service.dart';
import 'package:manga_sonic/utils/source_registry.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1;

  final List<Widget> _screens = [
    const SiteListTab(),
    const LibraryScreen(),
    const DownloadsScreen(),
    const SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBody: true,
      body: _screens[_currentIndex],
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

class SiteListTab extends StatefulWidget {
  const SiteListTab({super.key});

  @override
  State<SiteListTab> createState() => _SiteListTabState();
}

class _SiteListTabState extends State<SiteListTab> {
  static const List<Map<String, String>> _builtInSites = [
    {
      'name': 'ManhuaTop',
      'url': 'https://manhuatop.org/',
      'logoUrl':
          'https://www.google.com/s2/favicons?domain=manhuatop.org&sz=128',
    },
    {
      'name': 'AsuraComic',
      'url': 'https://asuracomic.net/',
      'logoUrl': 'https://asuracomic.net/images/logo.webp',
    },
    {
      'name': 'ManhuaPlus',
      'url': 'https://manhuaplus.com/',
      'logoUrl':
          'https://manhuaplus.com/wp-content/uploads/2017/10/logo-1-1.png',
    },
  ];

  List<Map<String, String>> _allSites = [];

  @override
  void initState() {
    super.initState();
    _refreshSites();
  }

  void _refreshSites() {
    final customSources = CustomSourceDB.getSources();
    final customSiteMaps = customSources.map((s) => {
          'name': s.name,
          'url': s.url,
          'logoUrl': s.logoUrl,
          'isCustom': 'true',
        }).toList();
    setState(() {
      _allSites = [..._builtInSites, ...customSiteMaps];
    });
    SourceRegistry.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView.builder(
          itemCount: _allSites.length + 3,
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.only(
                  left: 20.0,
                  right: 20.0,
                  top: 20.0,
                  bottom: 10.0,
                ),
                child: Text(
                  'MangaSonic',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              );
            }
            if (index == 1) {
              return const Padding(
                padding: EdgeInsets.only(
                  left: 20.0,
                  right: 20.0,
                  top: 10.0,
                  bottom: 8.0,
                ),
                child: Text(
                  'AVAILABLE SOURCES',
                  style: TextStyle(
                    color: Colors.blueGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              );
            }
            if (index == _allSites.length + 2) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AddSourceScreen(),
                      ),
                    );
                    _refreshSites();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Install more sources'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF263238),
                    foregroundColor: Colors.blue[100],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              );
            }

            final site = _allSites[index - 2];
            final isCustom = site['isCustom'] == 'true';
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12.0,
                vertical: 4.0,
              ),
              child: Card(
                color: const Color(0xFF1E1E24),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.2),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Builder(
                        builder: (context) {
                          if (site['logoUrl'] != null) {
                            return Image.network(
                              site['logoUrl']!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, err, trace) => Icon(
                                Icons.public,
                                color: Theme.of(context).primaryColor,
                              ),
                            );
                          }
                          return Icon(
                            Icons.public,
                            color: Theme.of(context).primaryColor,
                          );
                        },
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          site['name']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCustom) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CUSTOM',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    site['url']!.replaceAll('https://', '').replaceAll('/', ''),
                    style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SiteScreen(
                          siteName: site['name']!,
                          siteUrl: site['url']!,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _nimKeyConfigured = NimAiService.isConfigured;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme Personalization'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PalettePersonalizerScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(
              _nimKeyConfigured ? Icons.check_circle : Icons.key,
              color: _nimKeyConfigured ? Colors.green : null,
            ),
            title: const Text('NVIDIA NIM API Key'),
            subtitle: Text(
              _nimKeyConfigured ? 'Configured' : 'Not set — AI features disabled',
              style: TextStyle(
                color: _nimKeyConfigured ? Colors.green : Colors.grey,
                fontSize: 12,
              ),
            ),
            trailing: _nimKeyConfigured
                ? const Icon(Icons.check, color: Colors.green, size: 20)
                : null,
            onTap: () => _showApiKeyDialog(context),
          ),
        ],
      ),
    );
  }

  void _showApiKeyDialog(BuildContext context) {
    final controller = TextEditingController(
      text: NimAiService.getApiKey() ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('NVIDIA NIM API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your NVIDIA NIM API key to enable AI-powered source detection.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'nvapi-...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: const Color(0xFF0D1117),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await NimAiService.setApiKey(controller.text.trim());
              setState(() => _nimKeyConfigured = NimAiService.isConfigured);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
