import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/app_bottom_nav.dart';
import '../../core/widgets/app_page_header.dart';
import '../../l10n/app_localizations.dart';
import '../../services/user_profile_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_image.dart';

import '../orders/orders_screen.dart';
import '../orders/transactions_screen.dart';
import '../settings/settings_screen.dart';
import '../credit/credit_screen.dart';
import 'edit_profile_screen.dart';

// ============================================================
// IMAGE PROCESSING
// Center crop + resize + JPEG compression.
// Compatible with base64 images saved by the web application.
// ============================================================

class _CropArgs {
  final Uint8List bytes;
  final int width;
  final int height;
  final int quality;

  const _CropArgs(this.bytes, this.width, this.height, this.quality);
}

Uint8List _cropToJpeg(_CropArgs args) {
  final decoded = img.decodeImage(args.bytes);

  if (decoded == null) {
    throw Exception('Invalid image file.');
  }

  final source = img.bakeOrientation(decoded);

  final scale = math.max(
    args.width / source.width,
    args.height / source.height,
  );

  final cropWidth = (args.width / scale).round().clamp(1, source.width);

  final cropHeight = (args.height / scale).round().clamp(1, source.height);

  final cropX = ((source.width - cropWidth) / 2).round().clamp(
    0,
    source.width - cropWidth,
  );

  final cropY = ((source.height - cropHeight) / 2).round().clamp(
    0,
    source.height - cropHeight,
  );

  final cropped = img.copyCrop(
    source,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );

  final resized = img.copyResize(
    cropped,
    width: args.width,
    height: args.height,
  );

  return Uint8List.fromList(img.encodeJpg(resized, quality: args.quality));
}

// Convert selected image into a base64 data URL.
Future<String> _fileToDataUrl(
  XFile file, {
  required int width,
  required int height,
  required int quality,
}) async {
  final bytes = await file.readAsBytes();

  final jpeg = await compute(
    _cropToJpeg,
    _CropArgs(bytes, width, height, quality),
  );

  return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
}

// Decode base64 image.
Uint8List? _decodeBase64Image(String? source) {
  if (source == null || source.isEmpty) return null;

  if (!source.startsWith('data:image')) return null;

  try {
    final comma = source.indexOf(',');

    if (comma == -1) return null;

    return base64Decode(source.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

// Read different field names used by web and mobile.
String _readString(
  Map<String, dynamic> data,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = data[key];

    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }

  return fallback;
}

// ============================================================
// MENU MODEL
// ============================================================

class _MenuEntry {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget destination;

  const _MenuEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.destination,
  });
}

// ============================================================
// PROFILE SCREEN
// ============================================================

class ProfileScreen extends StatefulWidget {
  final String? userName;
  final ValueChanged<String>? onNameChanged;

  const ProfileScreen({super.key, this.userName, this.onNameChanged});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  SariColors get sari => context.sari;
  ColorScheme get scheme => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    UserProfileStore.instance.ensureLoaded();
  }

  User? get _user => FirebaseAuth.instance.currentUser;

  DocumentReference<Map<String, dynamic>>? get _userDocument {
    final user = _user;

    if (user == null) return null;

    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  bool _uploadingAvatar = false;
  bool _uploadingCover = false;

  String _lastNotifiedName = '';

  // ==========================================================
  // FIRESTORE UPDATE
  // ==========================================================

  Future<void> _saveUser(Map<String, dynamic> fields) async {
    final document = _userDocument;

    if (document == null) {
      throw Exception('User is not logged in.');
    }

    await document.set({
      ...fields,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==========================================================
  // PROFILE PICTURE
  // ==========================================================

  Future<void> _changeAvatar() async {
    if (_user == null || _uploadingAvatar) return;

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (picked == null || !mounted) return;

      setState(() => _uploadingAvatar = true);

      final dataUrl = await _fileToDataUrl(
        picked,
        width: 256,
        height: 256,
        quality: 85,
      );

      await _saveUser({'profile_image': dataUrl});

      if (!mounted) return;

      _toast('Profile picture updated successfully.');
    } catch (e) {
      debugPrint('Avatar upload error: $e');

      if (mounted) {
        _toast('Unable to update profile picture: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  // ==========================================================
  // COVER PHOTO
  // ==========================================================

  Future<void> _changeCover() async {
    if (_user == null || _uploadingCover) return;

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (picked == null || !mounted) return;

      setState(() => _uploadingCover = true);

      final dataUrl = await _fileToDataUrl(
        picked,
        width: 1400,
        height: 320,
        quality: 70,
      );

      await _saveUser({'cover_image': dataUrl});

      if (!mounted) return;

      _toast('Cover photo updated successfully.');
    } catch (e) {
      debugPrint('Cover upload error: $e');

      if (mounted) {
        _toast('Unable to update cover photo: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingCover = false);
      }
    }
  }

  // ==========================================================
  // EDIT PROFILE SCREEN
  // Preserve existing EditProfileScreen navigation.
  // ==========================================================

  Future<void> _openEditProfile() async {
    final updated = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const EditProfileScreen()));

    if (updated == true && mounted) {
      await _refreshName();
    }
  }

  Future<void> _refreshName() async {
    final user = _user;

    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      final data = snapshot.data() ?? {};

      final name = _readString(data, [
        'full_name',
        'name',
        'firstName',
      ], fallback: user.displayName ?? 'User');

      _notifyNameChanged(name);
    } catch (e) {
      debugPrint('Profile refresh error: $e');
    }
  }

  void _notifyNameChanged(String name) {
    if (name == _lastNotifiedName) return;

    _lastNotifiedName = name;

    widget.onNameChanged?.call(name);
  }

  // ==========================================================
  // REFRESH
  // ==========================================================

  Future<void> _refreshProfile() async {
    final user = _user;

    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
    } catch (e) {
      debugPrint('Refresh error: $e');
    }
  }

  // ==========================================================
  // SNACKBAR
  // ==========================================================

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Colors.red.shade700 : sari.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ==========================================================
  // AVATAR
  // ==========================================================

  Widget _avatar({
    double radius = 28,
    required String name,
    required String photoUrl,
  }) {
    final bytes = _decodeBase64Image(photoUrl);

    Widget avatar;

    if (bytes != null) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: sari.success,
        backgroundImage: MemoryImage(bytes),
      );
    } else if (photoUrl.isNotEmpty) {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: sari.success,
        child: ClipOval(
          child: ProductImage(
            imageUrl: photoUrl,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: radius,
        backgroundColor: sari.success,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: TextStyle(
            color: sari.onAccent,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.7,
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _uploadingAvatar ? null : _changeAvatar,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: sari.success.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: avatar,
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: sari.warning,
                  shape: BoxShape.circle,
                  border: Border.all(color: sari.cardSurfaceStrong, width: 2),
                ),
                child: _uploadingAvatar
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.camera_alt_rounded,
                        size: 12,
                        color: sari.onAccentAmber,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // COVER PHOTO
  // ==========================================================

  Widget _cover(String coverUrl) {
    final bytes = _decodeBase64Image(coverUrl);

    return Container(
      height: 135,
      width: double.infinity,
      decoration: BoxDecoration(
        color: sari.success.withValues(alpha: 0.18),
        image: bytes != null
            ? DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover)
            : coverUrl.isNotEmpty && !coverUrl.startsWith('data:image')
            ? DecorationImage(
                image: NetworkImage(coverUrl),
                fit: BoxFit.cover,
                onError: (_, __) {},
              )
            : null,
      ),
      child: Stack(
        children: [
          Positioned(
            right: 10,
            top: 10,
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: _uploadingCover ? null : _changeCover,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: _uploadingCover
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 19,
                        ),
                ),
              ),
            ),
          ),
          if (coverUrl.isEmpty)
            Center(
              child: Icon(
                Icons.storefront_rounded,
                color: Colors.white.withValues(alpha: 0.25),
                size: 55,
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================================
  // PROFILE IDENTITY CARD
  // ==========================================================

  Widget _identityCard({
    required String name,
    required String username,
    required String storeName,
    required String email,
    required String phone,
    required String address,
    required String photoUrl,
    required String coverUrl,
  }) {
    final contactRows = <Widget>[
      if (phone.isNotEmpty) _contactRow(Icons.phone_outlined, phone),
      if (address.isNotEmpty)
        _contactRow(Icons.location_on_outlined, address, maxLines: 2),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          decoration: BoxDecoration(
            color: sari.cardSurfaceStrong.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sari.glassBorder, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cover(coverUrl),

              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -35),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _avatar(radius: 38, name: name, photoUrl: photoUrl),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _editButton(),
                          ),
                        ],
                      ),
                    ),

                    Transform.translate(
                      offset: const Offset(0, -25),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 5),

                          Wrap(
                            spacing: 8,
                            runSpacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (username.isNotEmpty)
                                Text(
                                  '@$username',
                                  style: TextStyle(
                                    color: sari.warning,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (storeName.isNotEmpty) _storeChip(storeName),
                            ],
                          ),

                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: sari.mutedText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (contactRows.isNotEmpty) ...[
                      const SizedBox(height: 0),
                      Divider(color: sari.glassBorder, height: 1),
                      const SizedBox(height: 12),
                      for (var i = 0; i < contactRows.length; i++) ...[
                        if (i > 0) const SizedBox(height: 9),
                        contactRows[i],
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // EDIT BUTTON
  // ==========================================================

  Widget _editButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openEditProfile,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: sari.warning, width: 1.3),
          ),
          child: Icon(Icons.edit_outlined, size: 17, color: sari.warning),
        ),
      ),
    );
  }

  // ==========================================================
  // STORE CHIP
  // ==========================================================

  Widget _storeChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: sari.success.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 13, color: sari.success),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: sari.success,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONTACT ROW
  // ==========================================================

  Widget _contactRow(IconData icon, String text, {int maxLines = 1}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: sari.mutedText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // MENU GROUP
  // ==========================================================

  Widget _menuGroup(List<_MenuEntry> entries) {
    return Container(
      decoration: BoxDecoration(
        color: sari.cardSurfaceStrong.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: sari.glassBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                _menuRow(entries[i]),
                if (i < entries.length - 1)
                  Divider(
                    color: sari.glassBorder.withValues(alpha: 0.6),
                    height: 1,
                    thickness: 1,
                    indent: 62,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // MENU ROW
  // ==========================================================

  Widget _menuRow(_MenuEntry entry) {
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => entry.destination),
        );

        if (mounted) {
          await _refreshProfile();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: sari.success.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(entry.icon, color: sari.success, size: 18),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sari.mutedText, fontSize: 11.5),
                  ),
                ],
              ),
            ),

            Icon(Icons.chevron_right_rounded, color: sari.warning, size: 20),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // MAIN BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 360 ? 14.0 : 18.0;

    final l10n = context.l10n;
    final user = _user;
    final document = _userDocument;

    if (user == null || document == null) {
      return const Scaffold(body: Center(child: Text('Hindi naka-login.')));
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: BoxDecoration(gradient: sari.screenGradient),
        child: SafeArea(
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            // Live Firestore listener:
            // Changes from web and mobile appear automatically.
            stream: document.snapshots(),

            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Profile error: ${snapshot.error}',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return Center(
                  child: CircularProgressIndicator(color: sari.success),
                );
              }

              final data = snapshot.data!.data() ?? <String, dynamic>{};

              // Support web and mobile field names.
              final name = _readString(data, [
                'full_name',
                'name',
                'firstName',
              ], fallback: widget.userName ?? user.displayName ?? 'User');

              final storeName = _readString(data, [
                'store_name',
                'storeName',
              ], fallback: 'My Store');

              final username = _readString(data, ['username']);

              final photoUrl = _readString(data, [
                'profile_image',
                'photoUrl',
                'photo_url',
              ]);

              final coverUrl = _readString(data, [
                'cover_image',
                'coverImage',
                'cover_url',
              ]);

              final email = _readString(data, [
                'email',
              ], fallback: user.email ?? '');

              final phone = _readString(data, [
                'phone',
                'phone_number',
                'phoneNumber',
              ]);

              final address = _readString(data, [
                'store_address',
                'address',
                'storeAddress',
              ]);

              // Notify parent when owner name changes.
              if (name != _lastNotifiedName) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _notifyNameChanged(name);
                  }
                });
              }

              return RefreshIndicator(
                color: sari.warning,
                backgroundColor: sari.cardSurfaceStrong,
                onRefresh: _refreshProfile,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    6,
                    horizontal,
                    AppBottomNav.safeBodyBottomInset(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 6, 4, 4),
                        child: SizedBox(
                          height: 56,
                          child: Row(
                            children: [
                              AppPageHeader.iconBadge(
                                context: context,
                                icon: Icons.person_rounded,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.text('profileTitle'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: scheme.onSurface,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat(
                                        'EEEE, MMM d',
                                        Localizations.localeOf(context)
                                            .languageCode,
                                      ).format(DateTime.now()),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: sari.mutedText,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: AppPageHeader.avatarAction(
                                  context: context,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // PROFILE IDENTITY CARD
                      _identityCard(
                        name: name,
                        username: username,
                        storeName: storeName,
                        email: email,
                        phone: phone,
                        address: address,
                        photoUrl: photoUrl,
                        coverUrl: coverUrl,
                      ),

                      // MANAGE SECTION
                      const SizedBox(height: 18),

                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          l10n.text('manage'),
                          style: TextStyle(
                            color: sari.faintText,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),

                      // EXISTING NAVIGATION
                      _menuGroup([
                        _MenuEntry(
                          icon: Icons.receipt_long_rounded,
                          title: l10n.text('orders'),
                          subtitle: l10n.text('ordersSubtitle'),
                          destination: const OrdersScreen(),
                        ),
                        const _MenuEntry(
                          icon: Icons.receipt_long_outlined,
                          title: 'Transactions',
                          subtitle: 'View sales and payment history',
                          destination: TransactionsScreen(),
                        ),
                        _MenuEntry(
                          icon: Icons.assignment_outlined,
                          title: l10n.text('creditUtang'),
                          subtitle: l10n.text('creditUtangSubtitle'),
                          destination: const CreditScreen(),
                        ),
                        _MenuEntry(
                          icon: Icons.settings_outlined,
                          title: l10n.text('settings'),
                          subtitle: l10n.text('settingsMenuSubtitle'),
                          destination: const SettingsScreen(),
                        ),
                      ]),

                      const SizedBox(height: 90),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
