import 'package:flutter/material.dart';

import '../features/incident/presentation/pages/incident_form_page.dart';
import '../features/auth/presentation/pages/account_page.dart';
import '../features/auth/presentation/pages/auth_page.dart';
import '../features/map/presentation/pages/map_page.dart';
import '../features/weather/presentation/pages/weather_page.dart';
import 'app_initializer.dart';

class UrbanEyeApp extends StatelessWidget {
  const UrbanEyeApp({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF176B5B);
    final colors = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: const Color(0xFFF7FAF8),
    );
    return MaterialApp(
      title: 'UrbanEye',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colors,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3F7F5),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: Color(0xFF18332D),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE1EAE6)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          height: 72,
          backgroundColor: Colors.white,
          indicatorColor: Color(0xFFD9EEE8),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      home: AnimatedBuilder(
        animation: dependencies.auth,
        builder: (context, _) => dependencies.auth.isAuthenticated
            ? _Home(dependencies: dependencies)
            : AuthPage(
                auth: dependencies.auth,
                locationService: dependencies.location,
              ),
      ),
    );
  }
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
  void initState() {
    super.initState();
    widget.dependencies.notifications.addListener(_onNotification);
    widget.dependencies.notifications.start();
  }

  @override
  void dispose() {
    widget.dependencies.notifications.removeListener(_onNotification);
    super.dispose();
  }

  void _onNotification() {
    final notification = widget.dependencies.notifications
        .consumeLatestUnread();
    if (notification == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${notification.title}: ${notification.message}'),
        action: SnackBarAction(
          label: 'Ok',
          onPressed: () =>
              widget.dependencies.notifications.markRead(notification.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      IncidentFormPage(dependencies: widget.dependencies),
      MapPage(repository: widget.dependencies.repository),
      WeatherPage(locationService: widget.dependencies.location),
      AccountPage(
        auth: widget.dependencies.auth,
        notifications: widget.dependencies.notifications,
      ),
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
          NavigationDestination(
            icon: Icon(Icons.cloud_outlined),
            selectedIcon: Icon(Icons.cloud),
            label: 'Clima',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Conta',
          ),
        ],
      ),
    );
  }
}
