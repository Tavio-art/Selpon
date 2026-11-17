import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/user_profile_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_image.dart';

/// Shared page header used by Home, Inventory, Dashboard (and Profile title).
///
/// Keeps height, padding, and typography consistent. Parent screens should
/// still wrap with [SafeArea] (top) so status-bar insets stay correct.
class AppPageHeader extends StatelessWidget {
  /// Leading circle (avatar / store icon). Optional.
  final Widget? leading;

  /// Primary line (name, store name, or page title).
  final String title;

  /// Secondary line above or below [title] depending on [subtitleAboveTitle].
  final String? subtitle;

  /// When true, [subtitle] sits above [title] (Home "Welcome back" style).
  final bool subtitleAboveTitle;

  /// Trailing actions (cart, notifications, etc.).
  final List<Widget> actions;

  /// Optional tap on the leading + title block (e.g. open Profile from Home).
  final VoidCallback? onTitleTap;

  const AppPageHeader({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleAboveTitle = false,
    this.actions = const [],
    this.onTitleTap,
  });

  /// Circular leading icon matching Inventory / Dashboard chrome.
  static Widget iconBadge({
    required BuildContext context,
    required IconData icon,
  }) {
    final sari = context.sari;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: sari.fieldFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: sari.cardBorder, width: 1),
      ),
      child: Icon(icon, color: scheme.primary, size: 22),
    );
  }

  /// Circular profile avatar.
  static Widget avatarAction({
    required BuildContext context,
    VoidCallback? onTap,
  }) {
    return ListenableBuilder(
      listenable: UserProfileStore.instance,
      builder: (context, _) {
        final sari = context.sari;
        final scheme = Theme.of(context).colorScheme;
        final profile = UserProfileStore.instance;
        final photoUrl = profile.photoUrl;
        final name = profile.headerName;
        return SizedBox(
          width: 44,
          height: 44,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: sari.fieldFill,
                child: photoUrl.isNotEmpty
                    ? ClipOval(
                        child: ProductImage(
                          imageUrl: photoUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: GoogleFonts.outfit(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sari = context.sari;

    final titleStyle = GoogleFonts.outfit(
      color: scheme.onSurface,
      fontSize: 18,
      fontWeight: FontWeight.w800,
      height: 1.2,
    );
    final subtitleStyle = GoogleFonts.outfit(
      color: sari.mutedText,
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );

    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subtitle != null && subtitleAboveTitle) ...[
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          ),
          const SizedBox(height: 2),
        ],
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        ),
        if (subtitle != null && !subtitleAboveTitle) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          ),
        ],
      ],
    );

    final identity = Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: 12),
        ],
        Expanded(child: textBlock),
      ],
    );

    // Right inset when actions present so avatar badge is not clipped by edge.
    final rightPad = actions.isEmpty ? 0.0 : 4.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(0, 6, rightPad, 4),
      child: SizedBox(
        height: 56,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: onTitleTap == null
                  ? identity
                  : Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onTitleTap,
                        borderRadius: BorderRadius.circular(28),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: identity,
                        ),
                      ),
                    ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 8),
              ...actions.map(
                (action) => Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: action,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
