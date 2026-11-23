import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../firebase_options.dart';
import '../core/widgets/sari_storefront.dart';
import '../services/notification_store.dart';
import '../services/push_notification_service.dart';
import '../services/settings_store.dart';
import '../core/theme/theme_controller.dart';
import '../services/user_profile_store.dart';
import 'auth/login_screen.dart';
import 'home/main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _minimumSplashDuration = Duration(milliseconds: 2500);

  late final AnimationController _c;
  String? _startupError;

  late final Animation<Offset> _awningSlide;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _tagFade;
  late final Animation<Offset> _tagSlide;
  late final Animation<double> _shelfFade;
  late final Animation<Offset> _shelfSlide;

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _awningSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.32, curve: Curves.easeOutCubic),
    ));

    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.9, end: 1.07)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.07, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
    ]).animate(CurvedAnimation(
      parent: _c,
      curve: const Interval(0.20, 0.72, curve: Curves.linear),
    ));

    _titleFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.44, 0.72, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 16 / 60),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _c,
      curve: const Interval(0.44, 0.72, curve: Curves.easeOutCubic),
    ));

    _tagFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.52, 0.80, curve: Curves.easeOut),
    );
    _tagSlide = Tween<Offset>(
      begin: const Offset(0, 16 / 40),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _c,
      curve: const Interval(0.52, 0.80, curve: Curves.easeOutCubic),
    ));

    _shelfFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.36, 0.68, curve: Curves.easeOut),
    );
    _shelfSlide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _c,
      curve: const Interval(0.36, 0.68, curve: Curves.easeOutCubic),
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (sariAnimationsEnabled(context)) {
        _c.forward();
      } else {
        _c.value = 1;
      }
      unawaited(_openNextScreen());
    });
  }

  Future<User?> _restoredUser() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) return currentUser;
    return FirebaseAuth.instance.authStateChanges().first;
  }

  Future<void> _runStartupTask(
    String taskName,
    Future<void> Function() task,
  ) async {
    try {
      await task().timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('Splash startup task "$taskName" failed: $error');
    }
  }

  Future<void> _openNextScreen() async {
    final minimumDisplay = Future<void>.delayed(_minimumSplashDuration);
    late final User? user;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      try {
        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (error) {
        debugPrint('Firestore persistence skipped: $error');
      }

      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }

      final userFuture = _restoredUser();
      await Future.wait<void>([
        _runStartupTask('local settings', SettingsStore.instance.loadLocal),
        _runStartupTask('local theme', ThemeController.instance.load),
        _runStartupTask('date formatting', initializeDateFormatting),
      ]);
      user = await userFuture;
      await _runStartupTask(
        'local notifications',
        NotificationStore.instance.load,
      );
    } catch (error, stackTrace) {
      debugPrint('App startup failed: $error\n$stackTrace');
      await minimumDisplay;
      if (mounted) {
        setState(
          () => _startupError = 'Unable to start the app. Please retry.',
        );
      }
      return;
    }

    await minimumDisplay;
    if (!mounted) return;

    if (user == null) {
      UserProfileStore.instance.clear();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, animation, __) {
          return user != null ? const MainShell() : const LoginScreen();
        },
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );

    unawaited(
      _runStartupTask(
        'settings refresh',
        SettingsStore.instance.refreshFromFirestore,
      ),
    );
    if (user != null) {
      unawaited(
        _runStartupTask('profile refresh', UserProfileStore.instance.reload),
      );
    }
    unawaited(
      _runStartupTask('push startup', () async {
        final push = PushNotificationService.instance;
        await push.initialize();
        if (user != null) await push.bindTokenToCurrentUser();
        await push.requestPermissionIfNeeded();
      }),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_startupError != null) {
      return Scaffold(
        backgroundColor: SariBrandDecor.splashGreen,
        body: Center(
          child: Text(
            _startupError!,
            style: const TextStyle(color: SariBrandDecor.onGreen),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: SariBrandDecor.splashGreen,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SlideTransition(
                  position: _awningSlide,
                  child: const SariAwning(),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _logoScale,
                      child: Image.asset(
                        'assets/images/sari_splash_logo.png',
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FadeTransition(
                      opacity: _titleFade,
                      child: SlideTransition(
                        position: _titleSlide,
                        child: Text('Sari', style: sariOnGreenTitle(60)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeTransition(
                      opacity: _tagFade,
                      child: SlideTransition(
                        position: _tagSlide,
                        child: Text(
                          'Your store, in your pocket.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            color: SariBrandDecor.onGreen,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          SariBrandDecor.onGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 28,
                child: FadeTransition(
                  opacity: _shelfFade,
                  child: SlideTransition(
                    position: _shelfSlide,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SariPulseDots(t: _c.value),
                        const SizedBox(height: 10),
                        const SariShelf(height: 58),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
