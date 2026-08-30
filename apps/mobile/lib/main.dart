import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/app_initializer.dart';

Future<void> main() async {
  final dependencies = await AppInitializer.initialize();
  runApp(UrbanEyeApp(dependencies: dependencies));
}
