import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'l10n/app_localizations.dart';
import 'screens/splash_screen.dart';
import 'services/settings_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SariApp());
}

class SariApp extends StatelessWidget {
  const SariApp({super.key});

  static SystemUiOverlayStyle _overlayFor(Brightness brightness) {
    final light = brightness == Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: light ? Brightness.dark : Brightness.light,
      statusBarBrightness: light ? Brightness.light : Brightness.dark,
      systemNavigationBarColor:
          light ? AppColors.lightBackground : AppColors.darkBackground,
      systemNavigationBarIconBrightness:
          light ? Brightness.dark : Brightness.light,
    );
  }

  static Brightness _resolveBrightness(
    BuildContext context,
    ThemeMode mode,
  ) {
    switch (mode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
      case ThemeMode.system:
        return Brightness.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        ThemeController.instance,
        SettingsStore.instance,
      ]),
      builder: (context, _) {
        final themeMode = ThemeController.instance.mode;
        return MaterialApp(
          title: 'Sari',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
          locale: Locale(SettingsStore.instance.languageCode),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final brightness = _resolveBrightness(context, themeMode);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: _overlayFor(brightness),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const SplashScreen(),
        );
      },
    );
  }
}
