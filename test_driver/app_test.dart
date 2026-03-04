import 'package:flutter_driver/flutter_driver.dart';

void main() async {
  final driver = await FlutterDriver.connect();
  print('Connected to app');
  // Wait for home screen
  await Future.delayed(Duration(seconds: 3));
  // Switch to Downloads tab (index 2 in bottom nav bar assume)
  final downloadsIcon = find.byType(
    'Icon',
  ); // Need better finder, but we don't have tooltips. Let's just find "Downloads".
  final downloadsText = find.text('Downloads');
  try {
    await driver.tap(downloadsText);
    print('Tapped Downloads tab');
  } catch (e) {
    print('Could not find Downloads tab text, trying library');
    final libText = find.text('Library');
    await driver.tap(libText);
  }
  await Future.delayed(Duration(seconds: 3));
  await driver.close();
}
