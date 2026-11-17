import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_indicator.dart';
import '../../l10n/app_localizations.dart';
import '../../models/notification_item.dart';
import '../../services/notification_store.dart';
import '../credit/credit_screen.dart';
import '../orders/orders_screen.dart';
import '../orders/transactions_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final ValueChanged<NotificationType>? onOpenRelated;

  const NotificationsScreen({super.key, this.onOpenRelated});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _showUnreadOnly = false;
  final NotificationStore _store = NotificationStore.instance;

  Color _dotColor(NotificationType type, BuildContext context) {
    final sari = context.sari;
    switch (type) {
      case NotificationType.lowStock:
        return sari.accentAmber;
      case NotificationType.payment:
        return sari.success;
      case NotificationType.creditOverdue:
        return sari.danger;
      case NotificationType.orderReady:
        return sari.info;
      case NotificationType.inventory:
        return sari.success;
      case NotificationType.transaction:
        return sari.accentAmber;
    }
  }

  IconData _typeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.lowStock:
        return Icons.inventory_2_outlined;
      case NotificationType.payment:
        return Icons.payments_outlined;
      case NotificationType.creditOverdue:
        return Icons.warning_amber_rounded;
      case NotificationType.orderReady:
        return Icons.receipt_long_outlined;
      case NotificationType.inventory:
        return Icons.edit_note_outlined;
      case NotificationType.transaction:
        return Icons.receipt_outlined;
    }
  }

  Future<void> _onMarkAllRead() async {
    if (_store.unreadCount == 0) {
      AppSnackbar.showInfo(context, context.l10n.text('noUnreadNotifications'));
      return;
    }
    await _store.markAllAsRead();
    if (!mounted) return;
    AppSnackbar.showSuccess(context, context.l10n.text('allMarkedRead'));
  }

  Future<void> _onClearAll() async {
    if (_store.items.isEmpty) return;
    final confirmed = await ConfirmDialog.show(
      context,
      title: context.l10n.text('clearAllTitle'),
      message: context.l10n.text('clearAllMessage'),
      confirmLabel: context.l10n.text('clear'),
      cancelLabel: context.l10n.text('cancel'),
      isDestructive: true,
    );
    if (confirmed != true) return;
    await _store.clearAll();
    if (!mounted) return;
    AppSnackbar.showSuccess(context, context.l10n.text('notificationsCleared'));
  }

  Future<void> _onTapItem(NotificationItem n) async {
    await _store.markAsRead(n.id);
    if (!mounted) return;

    switch (n.type) {
      case NotificationType.lowStock:
        widget.onOpenRelated?.call(n.type);
        break;
      case NotificationType.payment:
      case NotificationType.orderReady:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const OrdersScreen()));
        break;
      case NotificationType.creditOverdue:
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const CreditScreen()));
        break;
      case NotificationType.inventory:
        widget.onOpenRelated?.call(n.type);
        break;
      case NotificationType.transaction:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const TransactionsScreen()));
        break;
    }
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final sari = context.sari;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? sari.accentAmber : sari.fieldFill,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected ? sari.accentAmber : sari.cardBorder,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: selected ? sari.onAccentAmber : sari.bodyText,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _manilaDate(DateTime? date) {
    if (date == null) return null;
    final manila = date.toUtc().add(const Duration(hours: 8));
    return DateTime.utc(manila.year, manila.month, manila.day);
  }

  bool _isToday(NotificationItem item) {
    final date = _manilaDate(item.createdAt);
    final now = _manilaDate(DateTime.now());
    return date != null && date == now;
  }

  Widget _sectionTitle(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _notificationCard(NotificationItem n) {
    final dot = _dotColor(n.type, context);
    final sari = context.sari;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        onTap: () => _onTapItem(n),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: dot.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(_typeIcon(n.type), size: 20, color: dot),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: GoogleFonts.outfit(
                            color: scheme.onSurface,
                            fontWeight: n.unread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (n.unread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n.subtitle,
                    style: GoogleFonts.outfit(
                      color: sari.mutedText,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    n.displayTime(context.l10n),
                    style: GoogleFonts.outfit(
                      color: sari.faintText,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: sari.faintText, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sari = context.sari;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              final items = _store.items
                  .where((n) => !_showUnreadOnly || n.unread)
                  .toList();
              final todayItems = items.where(_isToday).toList();
              final earlierItems = items.where((n) => !_isToday(n)).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (Navigator.of(context).canPop()) ...[
                        Material(
                          color: sari.fieldFill,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.of(context).pop(),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                Icons.arrow_back_rounded,
                                color: scheme.onSurface,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          context.l10n.text('notificationsTitle'),
                          style: GoogleFonts.outfit(
                            color: scheme.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_store.items.isNotEmpty) ...[
                        TextButton(
                          onPressed: _onMarkAllRead,
                          child: Text(
                            context.l10n.text('markAllRead'),
                            style: GoogleFonts.outfit(
                              color: sari.accentAmber,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert_rounded,
                            color: scheme.onSurface,
                            size: 22,
                          ),
                          color: sari.cardSurface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: sari.cardBorder),
                          ),
                          onSelected: (value) {
                            if (value == 'clear') _onClearAll();
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'clear',
                              child: Text(
                                context.l10n.text('clearAll'),
                                style: GoogleFonts.outfit(
                                  color: sari.danger,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _filterChip(
                        label: context.l10n.text('filterAll'),
                        selected: !_showUnreadOnly,
                        onSelected: () =>
                            setState(() => _showUnreadOnly = false),
                      ),
                      const SizedBox(width: 8),
                      _filterChip(
                        label: _store.unreadCount > 0
                            ? '${context.l10n.text('filterUnread')} (${_store.unreadCount})'
                            : context.l10n.text('filterUnread'),
                        selected: _showUnreadOnly,
                        onSelected: () =>
                            setState(() => _showUnreadOnly = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: !_store.isLoaded
                        ? const LoadingIndicator()
                        : _store.errorMessage != null
                        ? EmptyState(
                            icon: Icons.error_outline_rounded,
                            title: 'Could not load notifications',
                            message: _store.errorMessage!,
                            actionLabel: 'Retry',
                            onAction: () {
                              _store.reloadForCurrentUser();
                            },
                          )
                        : items.isEmpty
                        ? EmptyState(
                            icon: Icons.notifications_none_rounded,
                            title: _showUnreadOnly
                                ? 'No unread notifications'
                                : 'No notifications yet',
                            message: '',
                          )
                        : ListView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 96),
                            children: [
                              if (todayItems.isNotEmpty) ...[
                                _sectionTitle('Today', context),
                                for (final item in todayItems)
                                  _notificationCard(item),
                              ],
                              if (earlierItems.isNotEmpty) ...[
                                _sectionTitle('Earlier', context),
                                for (final item in earlierItems)
                                  _notificationCard(item),
                              ],
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
