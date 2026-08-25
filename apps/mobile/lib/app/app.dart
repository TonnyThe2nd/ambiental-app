import 'package:flutter/material.dart';

import '../features/incident/presentation/pages/incident_form_page.dart';
import '../features/map/presentation/pages/map_page.dart';
import 'app_initializer.dart';

class UrbanEyeApp extends StatelessWidget {
  const UrbanEyeApp({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'UrbanEye',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: _Home(dependencies: dependencies),
  );
}

class _Home extends StatefulWidget {
  const _Home({required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      IncidentFormPage(dependencies: widget.dependencies),
      MapPage(repository: widget.dependencies.repository),
    ];
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_a_photo_outlined),
            label: 'Registrar',
          ),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Mapa'),
        ],
      ),
    );
  }
}
