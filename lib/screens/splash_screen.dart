import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/widgets/sari_storefront.dart';
import '../services/notification_store.dart';
import '../services/push_notification_service.dart';
import '../services/settings_store.dart';
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
  late final AnimationController _c;
  Timer? _pulseTimer;
  double _pulseT = 0;

  late final Animation<Offset> _awningSlide;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
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
      duration: const Duration(milliseconds: 2500),
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
        tween: Tween(begin: 0.5, end: 1.07)
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

    _logoFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.20, 0.48, curve: Curves.easeOut),
    );

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
        _pulseTimer = Timer.periodic(const Duration(milliseconds: 40), (_) {
          if (!mounted) return;
          setState(() => _pulseT = (_pulseT + 0.035) % 1.0);
        });
      } else {
        _c.value = 1;
      }
    });

    unawaited(_openNextScreen());
  }

  Future<User?> _restoredUser() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) return currentUser;

    try {
      return await FirebaseAuth.instance.authStateChanges().first.timeout(
            const Duration(seconds: 2),
          );
    } catch (_) {
      return FirebaseAuth.instance.currentUser;
    }
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
    final userFuture = _restoredUser();

    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final user = await userFuture;

    if (!mounted) return;

    if (user != null) {
      await Future.wait<void>([
        _runStartupTask(
          'settings refresh',
          () => SettingsStore.instance.reloadForCurrentUser(),
        ),
        _runStartupTask(
          'notification refresh',
          () => NotificationStore.instance.reloadForCurrentUser(),
        ),
        _runStartupTask(
          'profile refresh',
          () => UserProfileStore.instance.reload(),
        ),
        _runStartupTask(
          'push token binding',
          () => PushNotificationService.instance.bindTokenToCurrentUser(),
        ),
      ]);
    } else {
      UserProfileStore.instance.clear();
    }

    await _runStartupTask(
      'notification permission',
      () => PushNotificationService.instance.requestPermissionIfNeeded(),
    );

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, animation, __) {
          return user != null ? const MainShell() : const LoginScreen();
        },
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SariBrandDecor.headerGreen,
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
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: const SariLogo(size: 140),
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
                        SariPulseDots(t: _pulseT),
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
