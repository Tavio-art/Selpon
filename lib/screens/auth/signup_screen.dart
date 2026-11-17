import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/sari_storefront.dart';
import '../../l10n/app_localizations.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _ownerNameController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscure = true;

  int? _month;
  int? _day;
  int? _year;

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
  }

  @override
  void dispose() {
    _sheetCtrl.dispose();
    _ownerNameController.dispose();
    _storeNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  List<int> get _years {
    final now = DateTime.now().year;
    return List<int>.generate(101, (i) => now - i);
  }

  List<int> get _days {
    if (_month == null || _year == null) {
      return List<int>.generate(31, (i) => i + 1);
    }
    final max = _daysInMonth(_year!, _month!);
    return List<int>.generate(max, (i) => i + 1);
  }

  String? get _birthdayIso {
    if (_year == null || _month == null || _day == null) return null;
    final max = _daysInMonth(_year!, _month!);
    if (_day! > max) return null;
    final dt = DateTime(_year!, _month!, _day!);
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  Future<void> _signUp() async {
    final l10n = context.l10n;
    final ownerName = _ownerNameController.text.trim();
    final storeName = _storeNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final birthday = _birthdayIso;

    if (ownerName.isEmpty ||
        storeName.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      AppSnackbar.showError(context, l10n.text('signupAllFields'));
      return;
    }

    if (birthday == null) {
      AppSnackbar.showError(context, l10n.text('selectBirthday'));
      return;
    }

    if (password.length < 6) {
      AppSnackbar.showError(context, l10n.text('passwordLength'));
      return;
    }

    final parts = ownerName.split(RegExp(r'\s+'));
    final firstName = parts.first;
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    setState(() => _isLoading = true);

    try {
      final UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = userCredential.user!.uid;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'uid': uid,
        'firstName': firstName,
        'lastName': lastName,
        'storeName': storeName,
        'email': email,
        'birthday': birthday,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      AppSnackbar.showSuccess(context, l10n.text('signupSuccess'));
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      AppSnackbar.showError(context, e.message ?? l10n.text('signupError'));
    } catch (e) {
      AppSnackbar.showError(
        context,
        l10n.text('signupFailed', values: {'error': '$e'}),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration({required String hint, Widget? suffix}) {
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

  Widget _label(String text, ColorScheme scheme) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        color: scheme.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _dropdown<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final sari = context.sari;
    return SizedBox(
      height: 52,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: _fieldDecoration(hint: hint),
        hint: Text(
          hint,
          style: GoogleFonts.outfit(color: sari.faintText, fontSize: 13),
        ),
        style: GoogleFonts.outfit(color: scheme.onSurface, fontSize: 14),
        items: items
            .map(
              (e) => DropdownMenuItem<T>(
                value: e,
                child: Text(labelOf(e)),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sari = context.sari;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    // Clamp day when month/year shrinks the calendar.
    if (_day != null && _month != null && _year != null) {
      final max = _daysInMonth(_year!, _month!);
      if (_day! > max) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _day = max);
        });
      }
    }

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
                      const SariLogo(size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Create account',
                          style: sariOnGreenTitle(26),
                        ),
                      ),
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
                      _label("Owner's name", scheme),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 52,
                        child: TextField(
                          controller: _ownerNameController,
                          style: GoogleFonts.outfit(
                            color: scheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: _fieldDecoration(hint: "Owner's name"),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _label('Store name', scheme),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 52,
                        child: TextField(
                          controller: _storeNameController,
                          style: GoogleFonts.outfit(
                            color: scheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: _fieldDecoration(hint: 'Store name'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _label('Email', scheme),
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
                          decoration: _fieldDecoration(hint: 'Email'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _label('Birthday', scheme),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 14,
                            child: _dropdown<int>(
                              value: _month,
                              hint: 'Month',
                              items: List<int>.generate(12, (i) => i + 1),
                              labelOf: (m) => months[m - 1],
                              onChanged: (v) => setState(() => _month = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 10,
                            child: _dropdown<int>(
                              value: _day != null && _days.contains(_day)
                                  ? _day
                                  : null,
                              hint: 'Day',
                              items: _days,
                              labelOf: (d) => '$d',
                              onChanged: (v) => setState(() => _day = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 11,
                            child: _dropdown<int>(
                              value: _year,
                              hint: 'Year',
                              items: _years,
                              labelOf: (y) => '$y',
                              onChanged: (v) => setState(() => _year = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _label('Password', scheme),
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
                            hint: 'At least 8 characters',
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
                      const SizedBox(height: 22),
                      PrimaryButton(
                        label: 'Create account',
                        height: 56,
                        borderRadius: 16,
                        isLoading: _isLoading,
                        onPressed: _signUp,
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: GoogleFonts.outfit(
                              color: sari.mutedText,
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 40),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Log in',
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
