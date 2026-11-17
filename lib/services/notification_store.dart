import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/notification_item.dart';
import '../models/order.dart';
import '../models/product.dart';
import 'push_notification_service.dart';
import 'settings_store.dart';

class NotificationStore extends ChangeNotifier {
  NotificationStore._();
  static final NotificationStore instance = NotificationStore._();

  static const _storageKey = 'app_notifications_v2';

  final List<NotificationItem> _items = [];
  bool _loaded = false;
  final Set<String> _knownRemoteIds = {};
  final Set<String> _knownOrderIds = {};
  final Set<String> _lowStockProductIds = {};
  String? _loadedUid;
  String? _errorMessage;
  bool _ordersInitialized = false;
  DateTime? _orderBaselineAt;
  int _idSequence = 0;

  List<NotificationItem> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;
  String? get errorMessage => _errorMessage;

  int get unreadCount => _items.where((n) => n.unread).length;

  AppLocalizations get _l10n =>
      AppLocalizations(Locale(SettingsStore.instance.languageCode));

  Future<void> load() async {
    await reloadForCurrentUser();
  }

  Future<void> reloadForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final currentUid = (uid == null || uid.isEmpty) ? null : uid;

    _loadedUid = currentUid;
    _items.clear();
    _knownRemoteIds.clear();
    _knownOrderIds.clear();
    _lowStockProductIds.clear();
    _ordersInitialized = false;
    _orderBaselineAt = null;
    _errorMessage = null;
    _loaded = false;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_storageKey:${currentUid ?? 'guest'}');
      if (raw != null && raw.isNotEmpty) {
        final state = jsonDecode(raw) as Map<String, dynamic>;
        final rawItems = state['items'];
        if (rawItems is List) {
          for (final entry in rawItems) {
            if (entry is Map) {
              _items.add(
                NotificationItem.fromMap(Map<String, dynamic>.from(entry)),
              );
            }
          }
        }
        _knownRemoteIds.addAll(
          _items
              .map((item) => item.remoteId)
              .whereType<String>()
              .where((id) => id.isNotEmpty),
        );
        _knownOrderIds.addAll(
          (state['knownOrderIds'] as List? ?? const []).whereType<String>(),
        );
        final baseline = state['orderBaselineAt'];
        if (baseline is String) {
          _orderBaselineAt = DateTime.tryParse(baseline);
        }
        _lowStockProductIds.addAll(
          (state['lowStockProductIds'] as List? ?? const [])
              .whereType<String>(),
        );
        _ordersInitialized = state['ordersInitialized'] == true;
      }
    } catch (e) {
      _errorMessage = 'Unable to load notifications: $e';
      debugPrint('[NotificationStore] local load failed: $e');
    }
    final trimmedStoredItems = _items.length > 50;
    _trimItems();
    _loaded = true;
    notifyListeners();
    if (trimmedStoredItems) await _persist();
  }

  Future<void> _persist() async {
    final uid = _loadedUid;
    _trimItems();
    final state = jsonEncode({
      'items': _items.map((item) => item.toMap()).toList(),
      'ordersInitialized': _ordersInitialized,
      if (_orderBaselineAt != null)
        'orderBaselineAt': _orderBaselineAt!.toUtc().toIso8601String(),
      'knownOrderIds': _knownOrderIds.toList(),
      'lowStockProductIds': _lowStockProductIds.toList(),
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        '$_storageKey:${uid ?? 'guest'}',
        state,
      );
      if (!saved) throw StateError('SharedPreferences rejected the save.');
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Unable to save notifications: $e';
      debugPrint('[NotificationStore] local save failed: $e');
    }
    notifyListeners();
  }

  Future<void> updateOrders(
    Iterable<StoreOrder> orders, {
    required bool isFromCache,
  }) async {
    if (!_loaded) return;
    final current = orders.toList();
    if (!_ordersInitialized) {
      if (isFromCache) return;
      _orderBaselineAt = DateTime.now();
      _knownOrderIds.addAll(current.map((order) => order.id));
      _ordersInitialized = true;
      await _persist();
      return;
    }

    if (_orderBaselineAt == null) {
      _orderBaselineAt = DateTime.now();
      _knownOrderIds.addAll(current.map((order) => order.id));
      await _persist();
      return;
    }

    var changed = false;
    for (final order in current) {
      if (order.id.isEmpty || !_knownOrderIds.add(order.id)) continue;
      if (order.createdAt == null ||
          !order.createdAt!.isAfter(_orderBaselineAt!)) {
        changed = true;
        continue;
      }
      final isCredit = _isCredit(order.paymentMethod);
      _items.insert(
        0,
        NotificationItem(
          id: 'sale_${order.id}',
          title: isCredit ? 'Credit sale' : 'New sale',
          subtitle:
              '${order.customerName} · ${SettingsStore.instance.formatMoney(order.total)}',
          timeAgo: _l10n.text('justNow'),
          type: isCredit
              ? NotificationType.creditOverdue
              : NotificationType.transaction,
          unread: true,
          createdAt: DateTime.now(),
        ),
      );
      changed = true;
    }
    if (changed) {
      _trimItems();
      await _persist();
    }
  }

  Future<void> updateInventory(Iterable<Product> products) async {
    if (!_loaded) return;
    final lowStockIds = <String>{};
    var changed = false;

    for (final product in products) {
      if (product.isCatalogOnly || product.id.isEmpty) continue;
      if (product.stock > Product.lowStockThreshold) continue;

      final key = product.key.isEmpty ? product.id : product.key;
      lowStockIds.add(key);
      if (!_lowStockProductIds.add(key) ||
          !SettingsStore.instance.lowStockEnabled) {
        continue;
      }

      _items.insert(
        0,
        NotificationItem(
          id: 'low_stock_${key}_${DateTime.now().microsecondsSinceEpoch}',
          title: product.stock <= 0 ? 'Out of stock' : 'Low stock',
          subtitle: '${product.name} · ${product.stock} left',
          timeAgo: _l10n.text('justNow'),
          type: NotificationType.lowStock,
          unread: true,
          createdAt: DateTime.now(),
        ),
      );
      changed = true;
    }

    final oldLowStockCount = _lowStockProductIds.length;
    _lowStockProductIds.removeWhere((id) => !lowStockIds.contains(id));
    if (_lowStockProductIds.length != oldLowStockCount) {
      changed = true;
    }
    if (changed) {
      _trimItems();
      await _persist();
    }
  }

  bool _isCredit(String paymentMethod) {
    final method = paymentMethod.toLowerCase();
    return method.contains('credit') || method.contains('utang');
  }

  void _trimItems() {
    if (_items.length > 50) _items.removeRange(50, _items.length);
  }

  bool _allowedBySettings(NotificationType type) {
    final settings = SettingsStore.instance;
    switch (type) {
      case NotificationType.lowStock:
        return settings.lowStockEnabled;
      case NotificationType.payment:
      case NotificationType.creditOverdue:
      case NotificationType.orderReady:
      case NotificationType.inventory:
      case NotificationType.transaction:
        return true;
    }
  }

  bool hasRemoteId(String remoteId) {
    if (remoteId.isEmpty) return false;
    if (_knownRemoteIds.contains(remoteId)) return true;
    return _items.any((n) => n.remoteId == remoteId);
  }

  /// Upsert from FCM without creating duplicates for the same remote message.
  Future<void> ingestRemote({
    required String title,
    required String subtitle,
    required NotificationType type,
    String? remoteId,
    bool markUnread = true,
  }) async {
    if (!_allowedBySettings(type)) return;

    final id = remoteId?.trim() ?? '';
    if (id.isNotEmpty && hasRemoteId(id)) {
      if (!markUnread) {
        final match = _items.cast<NotificationItem?>().firstWhere(
          (n) => n?.remoteId == id || (n?.title == title && n!.unread),
          orElse: () => null,
        );
        if (match != null && match.id.isNotEmpty) {
          await markAsRead(match.id);
        }
      }
      return;
    }

    // Soft dedupe against a recent identical unread local item.
    final already = _items.any(
      (n) =>
          n.unread &&
          n.title == title &&
          n.subtitle == subtitle &&
          n.type == type,
    );
    if (already) {
      if (id.isNotEmpty) _knownRemoteIds.add(id);
      return;
    }

    await createNotification(
      title: title,
      subtitle: subtitle,
      type: type,
      showSystemBanner: false,
      remoteId: id.isEmpty ? null : id,
    );

    if (!markUnread && _items.isNotEmpty) {
      await markAsRead(_items.first.id);
    }
  }

  Future<void> createNotification({
    required String title,
    required String subtitle,
    required NotificationType type,
    String? timeAgo,
    bool showSystemBanner = true,
    String? remoteId,
  }) async {
    if (!_allowedBySettings(type)) return;

    final item = NotificationItem(
      id: 'notification_${DateTime.now().microsecondsSinceEpoch}_${_idSequence++}',
      title: title,
      subtitle: subtitle,
      timeAgo: timeAgo ?? _l10n.text('justNow'),
      type: type,
      unread: true,
      createdAt: DateTime.now(),
      remoteId: remoteId,
    );

    if (remoteId != null && remoteId.isNotEmpty) {
      _knownRemoteIds.add(remoteId);
    }

    _items.insert(0, item);
    _trimItems();
    _loaded = true;
    await _persist();

    if (showSystemBanner && SettingsStore.instance.pushEnabled) {
      await PushNotificationService.instance.showLocal(
        title: title,
        body: subtitle,
        payload: type.name,
      );
    }
  }

  Future<void> add({
    required String title,
    required String subtitle,
    required NotificationType type,
    String? timeAgo,
    bool showSystemBanner = true,
  }) => createNotification(
    title: title,
    subtitle: subtitle,
    type: type,
    timeAgo: timeAgo,
    showSystemBanner: showSystemBanner,
  );

  Future<void> addCheckoutThankYou({
    required String orderId,
    required double total,
    required String paymentMethod,
    String customerName = '',
  }) async {
    final who = customerName.trim().isEmpty
        ? _l10n.text('customer')
        : customerName.trim();
    final shortId = orderId.length > 8
        ? '${orderId.substring(0, 8)}…'
        : orderId;
    final money = SettingsStore.instance.formatMoney(total);
    await createNotification(
      title: _l10n.text('notificationThankYou'),
      subtitle: _l10n.text(
        'notificationCheckoutMessage',
        values: {
          'id': shortId,
          'customer': who,
          'method': paymentMethod,
          'amount': money,
        },
      ),
      type: NotificationType.payment,
    );
  }

  Future<void> addTransactionRecorded({
    required String paymentMethod,
    required double total,
    String customerName = '',
  }) async {
    final who = customerName.trim().isEmpty
        ? paymentMethod
        : customerName.trim();
    final money = SettingsStore.instance.formatMoney(total);
    await createNotification(
      title: _l10n.text('notificationTransactionRecorded'),
      subtitle: _l10n.text(
        'notificationTransactionMessage',
        values: {'customer': who, 'method': paymentMethod, 'amount': money},
      ),
      type: NotificationType.transaction,
    );
  }

  Future<void> addInventoryEvent({
    required String action,
    required String productName,
    int? stock,
  }) async {
    final stockPart = stock != null
        ? _l10n.text('notificationStockNow', values: {'stock': '$stock'})
        : '';
    final actionLabel = switch (action) {
      'added' => _l10n.text('actionAdded'),
      'edited' => _l10n.text('actionEdited'),
      'deleted' => _l10n.text('actionDeleted'),
      'added/updated' => _l10n.text('actionAddedUpdated'),
      'registered' => _l10n.text('actionRegistered'),
      _ => action,
    };
    await createNotification(
      title: _l10n.text('notificationInventoryUpdated'),
      subtitle: _l10n.text(
        'notificationInventoryMessage',
        values: {
          'name': productName,
          'action': actionLabel,
          'stock': stockPart,
        },
      ),
      type: NotificationType.inventory,
    );
  }

  Future<void> addLowStockAlert({
    required String productName,
    required int stock,
  }) async {
    if (!SettingsStore.instance.lowStockEnabled) return;
    final already = _items.any(
      (n) =>
          n.type == NotificationType.lowStock &&
          n.unread &&
          n.subtitle.contains(productName),
    );
    if (already) return;

    await createNotification(
      title: _l10n.text(
        stock <= 0 ? 'notificationOutOfStock' : 'notificationLowStock',
      ),
      subtitle: stock <= 0
          ? _l10n.text(
              'notificationItemOutOfStock',
              values: {'name': productName},
            )
          : _l10n.text(
              'notificationItemLowStock',
              values: {'name': productName, 'stock': '$stock'},
            ),
      type: NotificationType.lowStock,
    );
  }

  Future<void> addCreditOverdueAlert({
    required String creditId,
    required String customerName,
    required double amount,
    required int daysOverdue,
  }) async {
    final already = _items.any(
      (n) =>
          n.type == NotificationType.creditOverdue &&
          n.subtitle.contains(creditId),
    );
    if (already) return;

    final money = SettingsStore.instance.formatMoney(amount);
    await createNotification(
      title: _l10n.text('notificationCreditOverdue'),
      subtitle: _l10n.text(
        'notificationCreditMessage',
        values: {
          'name': customerName,
          'amount': money,
          'days': '$daysOverdue',
          'id': creditId,
        },
      ),
      type: NotificationType.creditOverdue,
    );
  }

  Future<void> markAsRead(String id) async {
    final index = _items.indexWhere((n) => n.id == id);
    if (index == -1 || !_items[index].unread) return;
    _items[index] = _items[index].copyWith(unread: false);
    await _persist();
  }

  Future<void> markAllAsRead() async {
    if (!_items.any((item) => item.unread)) return;
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].unread) {
        _items[i] = _items[i].copyWith(unread: false);
      }
    }
    await _persist();
  }

  Future<void> clearAll() async {
    if (_items.isEmpty) return;
    _items.clear();
    await _persist();
  }
}
