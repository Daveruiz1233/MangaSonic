import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  // Open Hive boxes for library and downloads later
  // await Hive.openBox('library');
  
  runApp(
    MultiProvider(
      providers: [
        // App State providers will go here
        Provider<String>(create: (_) => 'DummyProvider'),
      ],
      child: const MangaSonicApp(),
    ),
  );
}

class MangaSonicApp extends StatelessWidget {
  const MangaSonicApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MangaSonic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
