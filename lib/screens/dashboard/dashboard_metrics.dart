import '../../data/product_categories.dart';
import '../../models/order.dart';
import '../../models/product.dart';

/// Shared native/Flutter Web rules: Manila dates; all orders except cancelled
/// or refunded count as sales, including credit at creation; profit is a 20%
/// estimate on order totals.
class DashboardSeller {
  const DashboardSeller({required this.name, required this.quantity});

  final String name;
  final int quantity;
}

class DashboardMetrics {
  static const manilaOffset = Duration(hours: 8);
  static const estimatedProfitMargin = 0.20;

  const DashboardMetrics({
    required this.salesToday,
    required this.transactionsToday,
    required this.afterTaxToday,
    required this.weeklySales,
    required this.topSellers,
  });

  final double salesToday;
  final int transactionsToday;
  final double afterTaxToday;
  final List<double> weeklySales;
  final List<DashboardSeller> topSellers;

  bool get hasWeeklySales => weeklySales.any((value) => value > 0);

  static DateTime manilaNow() => DateTime.now().toUtc().add(manilaOffset);

  static DateTime toManila(DateTime date) => date.toUtc().add(manilaOffset);

  static DateTime manilaYearStartUtc(int year) =>
      DateTime.utc(year).subtract(manilaOffset);

  static DateTime manilaNextYearStartUtc(int year) =>
      DateTime.utc(year + 1).subtract(manilaOffset);

  static bool countsAsSale(StoreOrder order) => !order.isVoided;

  static double roundCurrency(double amount) =>
      (amount * 100).roundToDouble() / 100;

  static double totalRevenue(Iterable<StoreOrder> orders) => roundCurrency(
    orders
        .where(countsAsSale)
        .fold<double>(0, (total, order) => total + order.total),
  );

  static double estimatedProfit(double revenue) =>
      roundCurrency(revenue * estimatedProfitMargin);

  static String normalizeCategory(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return '';
    final lower = normalized.toLowerCase();
    if (lower == 'beverage' || lower == 'beverages') return 'Beverages';
    if (lower == 'coffee and tea') return 'Coffee & Tea';
    for (final known in ProductCategories.forPicker) {
      if (known.toLowerCase() == lower) return known;
    }
    return normalized;
  }

  static Map<String, double> categoryRevenue({
    required Iterable<StoreOrder> orders,
    Iterable<Product> products = const [],
  }) {
    final categoryByProductKey = <String, String>{};
    for (final product in products) {
      final category = normalizeCategory(product.category);
      if (category.isEmpty) continue;
      for (final identifier in [
        product.id,
        product.barcode,
        product.catalogProductId,
      ]) {
        final key = identifier.trim().toLowerCase();
        if (key.isNotEmpty) {
          categoryByProductKey.putIfAbsent(key, () => category);
        }
      }
    }

    final labels = <String, String>{};
    final totals = <String, double>{};
    for (final order in orders.where(countsAsSale)) {
      for (final item in order.items) {
        final rawCategory =
            [item['category'], item['categoryName'], item['productCategory']]
                .map((value) => value?.toString().trim() ?? '')
                .firstWhere((value) => value.isNotEmpty, orElse: () => '');
        var category = normalizeCategory(rawCategory);
        if (category.isEmpty || category.toLowerCase() == 'other') {
          for (final identifier in [
            item['inventoryId'],
            item['catalogProductId'],
            item['productId'],
            item['id'],
            item['barcode'],
          ]) {
            final key = identifier?.toString().trim().toLowerCase() ?? '';
            final lookedUp = categoryByProductKey[key];
            if (lookedUp != null) {
              category = lookedUp;
              break;
            }
          }
        }
        if (category.isEmpty || category.toLowerCase() == 'other') {
          category = 'Other';
        }

        final key = category.toLowerCase();
        labels.putIfAbsent(key, () => category);
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0;
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        final subtotal =
            (item['subtotal'] as num?)?.toDouble() ?? price * quantity;
        totals[key] = (totals[key] ?? 0) + subtotal;
      }
    }
    return {
      for (final entry in totals.entries)
        labels[entry.key]!: roundCurrency(entry.value),
    };
  }

  static List<int> percentageShares(Iterable<num> values) {
    final amounts = values.map((value) => value.toDouble()).toList();
    final total = amounts.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return List<int>.filled(amounts.length, 0);

    final exact = amounts.map((value) => value * 100 / total).toList();
    final shares = exact.map((value) => value.floor()).toList();
    final order = List<int>.generate(shares.length, (index) => index)
      ..sort((a, b) {
        final remainderOrder = (exact[b] - shares[b]).compareTo(
          exact[a] - shares[a],
        );
        return remainderOrder != 0 ? remainderOrder : a.compareTo(b);
      });
    final remaining = 100 - shares.fold<int>(0, (sum, value) => sum + value);
    for (var i = 0; i < remaining; i++) {
      shares[order[i % order.length]]++;
    }
    return shares;
  }

  factory DashboardMetrics.fromOrders({
    required Iterable<StoreOrder> orders,
    required double taxRate,
    DateTime? now,
  }) {
    final reference = now ?? manilaNow();
    final weekStart = startOfWeek(reference);
    var salesToday = 0.0;
    var transactionsToday = 0;
    final weeklySales = List<double>.filled(7, 0);
    final soldByName = <String, int>{};

    for (final order in orders) {
      if (!countsAsSale(order)) continue;
      final createdAt = order.createdAt == null
          ? null
          : toManila(order.createdAt!);
      if (createdAt != null) {
        if (isSameDay(createdAt, reference)) {
          salesToday += order.total;
          transactionsToday++;
        }

        final day = DateTime.utc(
          createdAt.year,
          createdAt.month,
          createdAt.day,
        );
        final weekdayOffset = day.difference(weekStart).inDays;
        if (weekdayOffset >= 0 && weekdayOffset < weeklySales.length) {
          weeklySales[weekdayOffset] += order.total;
        }
      }

      for (final item in order.items) {
        final name = (item['name'] ?? 'Item').toString();
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        soldByName[name] = (soldByName[name] ?? 0) + quantity;
      }
    }

    final topSellers =
        soldByName.entries
            .map(
              (entry) =>
                  DashboardSeller(name: entry.key, quantity: entry.value),
            )
            .toList()
          ..sort((a, b) {
            final quantityOrder = b.quantity.compareTo(a.quantity);
            return quantityOrder != 0
                ? quantityOrder
                : a.name.compareTo(b.name);
          });

    return DashboardMetrics(
      salesToday: roundCurrency(salesToday),
      transactionsToday: transactionsToday,
      afterTaxToday: roundCurrency(
        salesToday * (1 - (taxRate.clamp(0, 100) / 100)),
      ),
      weeklySales: weeklySales.map(roundCurrency).toList(growable: false),
      topSellers: topSellers.take(3).toList(growable: false),
    );
  }

  static double unpaidCredit(Iterable<Map<String, dynamic>> credits) {
    return credits.fold<double>(0, (total, credit) {
      if (credit['isPaid'] == true) return total;
      return total + ((credit['amount'] as num?)?.toDouble() ?? 0);
    });
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime startOfWeek(DateTime date) {
    final startOfDay = DateTime.utc(date.year, date.month, date.day);
    return startOfDay.subtract(Duration(days: date.weekday - 1));
  }
}
