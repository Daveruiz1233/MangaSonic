import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:manga_sonic/services/theme_service.dart';
import 'package:manga_sonic/utils/download_manager.dart';
import 'package:manga_sonic/utils/library_update_service.dart';
import 'package:manga_sonic/features/home/home_screen.dart';

class MangaSonicApp extends StatelessWidget {
  final ThemeService themeService;
  final DownloadManager downloadManager;
  final LibraryUpdateService updateService;

  const MangaSonicApp({
    super.key,
    required this.themeService,
    required this.downloadManager,
    required this.updateService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider.value(value: downloadManager),
        ChangeNotifierProvider.value(value: updateService),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'MangaSonic',
            debugShowCheckedModeBanner: false,
            theme: themeService.themeData,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
