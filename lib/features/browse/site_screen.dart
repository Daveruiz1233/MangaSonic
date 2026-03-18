import 'package:flutter/material.dart';
import 'package:manga_sonic/features/library/manga_screen.dart';
import 'package:manga_sonic/shared/widgets/manga_grid_card.dart';
import 'package:manga_sonic/data/models/models.dart';
import 'package:manga_sonic/utils/parser_factory.dart';
import 'package:manga_sonic/utils/cloudflare_interceptor.dart';

class SiteScreen extends StatefulWidget {
  final String siteName;
  final String siteUrl;

  const SiteScreen({super.key, required this.siteName, required this.siteUrl});

  @override
  State<SiteScreen> createState() => _SiteScreenState();
}

class _SiteScreenState extends State<SiteScreen> {
  final List<Manga> _mangas = [];
  bool _isLoading = true;
  int _currentPage = 1;
  final ScrollController _scrollController = ScrollController();

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 500 &&
          !_isLoading) {
        _currentPage++;
        _fetchData();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final parser = getParserForSite(widget.siteName);
      List<Manga> newMangas;

      if (_isSearching && _searchQuery.isNotEmpty) {
        newMangas = await parser.searchManga(_searchQuery, _currentPage);
      } else {
        newMangas = await parser.fetchMangaList(_currentPage);
      }

      if (!mounted) return;
      setState(() {
        _mangas.addAll(newMangas);
        _isLoading = false;
      });
    } catch (e) {
      if (e.toString().contains('403') || e.toString().contains('Cloudflare')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Passing Cloudflare... Please wait.')),
          );
        }
        await CloudflareInterceptor.bypass(widget.siteUrl);
        return _fetchData();
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search manga...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white54),
                ),
                style: const TextStyle(color: Colors.white),
                onSubmitted: (value) {
                  setState(() {
                    _searchQuery = value.trim();
                    _mangas.clear();
                    _currentPage = 1;
                  });
                  _fetchData();
                },
              )
            : Text(widget.siteName),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _searchQuery = '';
                  _mangas.clear();
                  _currentPage = 1;
                  _fetchData();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: _mangas.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _mangas.length + (_isLoading ? 3 : 0),
              itemBuilder: (context, index) {
                if (index >= _mangas.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final manga = _mangas[index];
                return MangaGridCard(
                  title: manga.title,
                  coverUrl: manga.coverUrl,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MangaScreen(
                          mangaTitle: manga.title,
                          mangaUrl: manga.url,
                          coverUrl: manga.coverUrl,
                          sourceId: manga.sourceId,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
