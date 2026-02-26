import 'package:flutter/material.dart';
import 'package:manga_sonic/ui/screens/manga_screen.dart';

class SiteScreen extends StatefulWidget {
  final String siteName;
  final String siteUrl;

  const SiteScreen({Key? key, required this.siteName, required this.siteUrl}) : super(key: key);

  @override
  State<SiteScreen> createState() => _SiteScreenState();
}

class _SiteScreenState extends State<SiteScreen> {
  // We will load manga logic here later
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.siteName),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: 9, // Fake items for now
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MangaScreen(
                          mangaTitle: 'Manga $index',
                          mangaUrl: '/dummy/path/$index',
                          coverUrl: '',
                        ),
                      ),
                    );
                  },
                  child: Card(
                    color: Colors.grey[900],
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Container(
                            color: Colors.deepPurple[800],
                            child: const Center(child: Icon(Icons.image)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Text(
                            'Manga Title $index',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
