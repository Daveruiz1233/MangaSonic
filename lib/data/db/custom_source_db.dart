import 'package:hive/hive.dart';
import '../models/custom_source_model.dart';

class CustomSourceDB {
  static const String boxName = 'custom_sources';

  static Future<void> init() async {
    await Hive.openBox(boxName);
  }

  static List<CustomSourceModel> getSources() {
    final box = Hive.box(boxName);
    return box.values
        .map((e) => CustomSourceModel.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  static CustomSourceModel? getSource(String sourceId) {
    final box = Hive.box(boxName);
    final data = box.get(sourceId);
    if (data == null) return null;
    return CustomSourceModel.fromMap(data as Map<dynamic, dynamic>);
  }

  static bool hasSource(String sourceId) {
    return Hive.box(boxName).containsKey(sourceId);
  }

  static Future<void> saveSource(CustomSourceModel source) async {
    await Hive.box(boxName).put(source.sourceId, source.toMap());
  }

  static Future<void> removeSource(String sourceId) async {
    await Hive.box(boxName).delete(sourceId);
  }

  static Future<void> updateSelectors(
    String sourceId,
    Map<String, String> selectors,
  ) async {
    final source = getSource(sourceId);
    if (source != null) {
      await saveSource(source.copyWith(selectors: selectors));
    }
  }
}
