import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/sari_storefront.dart';
import '../../l10n/app_localizations.dart';
import '../../services/notification_store.dart';
import '../../services/push_notification_service.dart';
import '../../services/settings_store.dart';
import '../home/main_shell.dart';
import 'forgot_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _rememberMe = true;
  bool _isLoading = false;
  bool _obscure = true;

  late final AnimationController _sheetCtrl;
  late final Animation<Offset> _sheetSlide;

  @override
  void initState() {
    super.initState();

    _sheetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _sheetSlide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _sheetCtrl,
      curve: Curves.easeOutCubic,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (sariAnimationsEnabled(context)) {
        _sheetCtrl.forward();
      } else {
        _sheetCtrl.value = 1;
      }
    });

    if (FirebaseAuth.instance.currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      });
    }
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final l10n = context.l10n;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      AppSnackbar.showError(context, l10n.text('loginEnterCredentials'));
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      await SettingsStore.instance.reloadForCurrentUser();
      await NotificationStore.instance.reloadForCurrentUser();

      try {
        await PushNotificationService.instance.bindTokenToCurrentUser();
      } catch (_) {}

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } on FirebaseAuthException catch (e) {
      String message = l10n.text('loginFailed');

      if (e.code == 'user-not-found') {
        message = l10n.text('loginNoAccountFound');
      } else if (e.code == 'wrong-password') {
        message = l10n.text('loginIncorrectPassword');
      } else if (e.code == 'invalid-credential') {
        message = l10n.text('loginInvalidCredentials');
      } else if (e.code == 'invalid-email') {
        message = l10n.text('resetInvalidEmail');
      } else if (e.code == 'too-many-requests') {
        message = 'Too many attempts. Please try again later.';
      }

      if (!mounted) return;
      AppSnackbar.showError(context, message);
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        l10n.text('loginGenericError', values: {'error': '$e'}),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    Widget? suffix,
  }) {
    final sari = context.sari;
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.outfit(
        color: sari.faintText,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: sari.fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      suffixIcon: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: sari.cardBorder, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: sari.cardBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sari = context.sari;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: SariBrandDecor.headerGreen,
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          SizedBox(
            height: 300,
            width: double.infinity,
            child: Stack(
              children: [
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SariAwning(),
                ),
                Positioned(
                  top: 118,
                  left: 28,
                  right: 28,
                  child: Row(
                    children: [
                      const SariLogo(size: 44),
                      const SizedBox(width: 12),
                      Text('Sari', style: sariOnGreenTitle(24)),
                    ],
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: SariShelf(height: 52),
                ),
              ],
            ),
          ),
          Expanded(
            child: SlideTransition(
              position: _sheetSlide,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(28, 28, 28, 28 + bottomInset),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Welcome back!',
                        style: GoogleFonts.outfit(
                          color: scheme.onSurface,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Log in to manage your store.',
                        style: GoogleFonts.outfit(
                          color: sari.mutedText,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Store / owner's name",
                        style: GoogleFonts.outfit(
                          color: scheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 52,
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.outfit(
                            color: scheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: _fieldDecoration(
                            hint: "e.g. Nena's Store",
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Password',
                        style: GoogleFonts.outfit(
                          color: scheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 52,
                        child: TextField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          style: GoogleFonts.outfit(
                            color: scheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: _fieldDecoration(
                            hint: 'Enter your password',
                            suffix: SizedBox(
                              width: 44,
                              height: 44,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  color: sari.mutedText,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              onChanged: (v) =>
                                  setState(() => _rememberMe = v ?? false),
                              activeColor: scheme.primary,
                              checkColor: scheme.onPrimary,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(
                                () => _rememberMe = !_rememberMe,
                              ),
                              child: Text(
                                'Remember me',
                                style: GoogleFonts.outfit(
                                  color: scheme.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ForgotPasswordScreen(
                                    initialEmail: _emailController.text.trim(),
                                  ),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Forgot password?',
                              style: GoogleFonts.outfit(
                                color: scheme.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: 'Log in',
                        height: 56,
                        borderRadius: 16,
                        isLoading: _isLoading,
                        onPressed: _login,
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: GoogleFonts.outfit(
                              color: sari.mutedText,
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SignupScreen(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Sign up',
                              style: GoogleFonts.outfit(
                                color: scheme.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
