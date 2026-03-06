import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ThemeService extends ChangeNotifier {
  static const String _boxName = 'themeBox';
  static const String _colorKey = 'primaryColor';
  static const String _bgColorKey = 'backgroundColor';

  late Box _box;
  Color _primaryColor = Colors.deepPurple;
  Color _backgroundColor = const Color(0xFF121212); // Default dark grey/black

  ThemeService() {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox(_boxName);
    final colorValue = _box.get(
      _colorKey,
      defaultValue: Colors.deepPurple.toARGB32(),
    ) as int;
    final bgColorValue = _box.get(
      _bgColorKey,
      defaultValue: const Color(0xFF121212).toARGB32(),
    ) as int;

    _primaryColor = Color(colorValue);
    _backgroundColor = Color(bgColorValue);
    notifyListeners();
  }

  Color get primaryColor => _primaryColor;
  Color get backgroundColor => _backgroundColor;

  Future<void> setPrimaryColor(Color color) async {
    _primaryColor = color;
    await _box.put(_colorKey, color.toARGB32());
    notifyListeners();
  }

  Future<void> setBackgroundColor(Color color) async {
    _backgroundColor = color;
    await _box.put(_bgColorKey, color.toARGB32());
    notifyListeners();
  }

  ThemeData get themeData {
    return ThemeData.dark().copyWith(
      primaryColor: _primaryColor,
      scaffoldBackgroundColor: _backgroundColor,
      canvasColor: _backgroundColor,
      colorScheme: ColorScheme.dark(
        primary: _primaryColor,
        secondary: _primaryColor,
        surface: _backgroundColor,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _backgroundColor == Colors.black
            ? Colors.grey[900]
            : _backgroundColor,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _primaryColor,
      ),
    );
  }
}
