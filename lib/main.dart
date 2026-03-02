import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:manga_sonic/data/db/library_db.dart';
import 'package:manga_sonic/data/db/download_db.dart';
import 'package:manga_sonic/data/db/history_db.dart';
import 'package:manga_sonic/services/theme_service.dart';
import 'package:manga_sonic/utils/download_manager.dart';
import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await LibraryDB.init();
  await DownloadDB.init();
  await HistoryDB.init();
  
  final themeService = ThemeService();
  final downloadManager = DownloadManager();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider.value(value: downloadManager),
      ],
      child: const MangaSonicApp(),
    ),
  );
}

class MangaSonicApp extends StatelessWidget {
  const MangaSonicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          title: 'MangaSonic',
          debugShowCheckedModeBanner: false,
          theme: themeService.themeData,
          home: const HomeScreen(),
        );
      },
    );
  }
}
