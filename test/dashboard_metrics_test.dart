import 'package:flutter_test/flutter_test.dart';
import 'package:sari_app/models/order.dart';
import 'package:sari_app/models/product.dart';
import 'package:sari_app/screens/dashboard/dashboard_metrics.dart';

StoreOrder order({
  required String id,
  required double total,
  required DateTime createdAt,
  List<Map<String, dynamic>> items = const [],
}) {
  return StoreOrder(
    id: id,
    customerName: 'Walk-in',
    itemCount: items.fold<int>(
      0,
      (sum, item) => sum + ((item['quantity'] as num?)?.toInt() ?? 0),
    ),
    total: total,
    status: OrderStatus.done,
    createdAt: createdAt,
    items: items,
  );
}

void main() {
  final now = DateTime(2026, 9, 23, 12);

  test('parses transaction fields in camelCase and snake_case', () {
    final order = StoreOrder.fromFirestore('transaction-1', {
      'customer_name': 'Walk-in',
      'total_amount': 50,
      'payment_method': 'Credit / Utang',
      'created_at': '2026-09-23T09:00:00Z',
      'status': 'completed',
      'items': [
        {'name': 'Coffee', 'quantity': 2, 'price': 25},
      ],
    });

    expect(order.id, 'transaction-1');
    expect(order.customerName, 'Walk-in');
    expect(order.total, 50);
    expect(order.paymentMethod, 'Credit / Utang');
    expect(order.createdAt, DateTime.utc(2026, 9, 23, 9));
    expect(order.itemCount, 2);
  });

  test('aggregates today, VAT-adjusted sales, and Monday-to-Sunday values', () {
    final metrics = DashboardMetrics.fromOrders(
      now: now,
      taxRate: 12,
      orders: [
        order(
          id: 'monday',
          total: 100,
          createdAt: DateTime(2026, 9, 21),
          items: [
            {'name': 'Coffee', 'quantity': 2},
          ],
        ),
        order(
          id: 'wednesday',
          total: 50,
          createdAt: DateTime(2026, 9, 23, 9),
          items: [
            {'name': 'Tea', 'quantity': 1},
          ],
        ),
        order(
          id: 'previous-week',
          total: 900,
          createdAt: DateTime(2026, 9, 20),
        ),
      ],
    );

    expect(metrics.salesToday, 50);
    expect(metrics.transactionsToday, 1);
    expect(metrics.afterTaxToday, closeTo(44, 0.0001));
    expect(metrics.weeklySales, [100, 0, 50, 0, 0, 0, 0]);
    expect(metrics.hasWeeklySales, isTrue);
  });

  test('retains seven zero-value days for an empty week', () {
    final metrics = DashboardMetrics.fromOrders(
      now: now,
      taxRate: 12,
      orders: const [],
    );

    expect(metrics.weeklySales, hasLength(7));
    expect(metrics.weeklySales, everyElement(0));
    expect(metrics.hasWeeklySales, isFalse);
  });

  test('ranks top sellers deterministically by quantity then name', () {
    final metrics = DashboardMetrics.fromOrders(
      now: now,
      taxRate: 0,
      orders: [
        order(
          id: 'first',
          total: 10,
          createdAt: now,
          items: [
            {'name': 'Zucchini', 'quantity': 2},
            {'name': 'Apple', 'quantity': 2},
          ],
        ),
        order(
          id: 'second',
          total: 10,
          createdAt: now,
          items: [
            {'name': 'Apple', 'quantity': 1},
          ],
        ),
      ],
    );

    expect(
      metrics.topSellers.map((seller) => (seller.name, seller.quantity)),
      [('Apple', 3), ('Zucchini', 2)],
    );
  });

  test('sums only unpaid credit amounts', () {
    final total = DashboardMetrics.unpaidCredit([
      {'amount': 100, 'isPaid': false},
      {'amount': 50, 'isPaid': true},
      {'amount': 25.5},
    ]);

    expect(total, 125.5);
  });

  test('uses stored or looked-up categories and preserves custom names', () {
    final sales = DashboardMetrics.categoryRevenue(
      orders: [
        order(
          id: 'legacy',
          total: 35,
          createdAt: now,
          items: [
            {'barcode': '123', 'quantity': 2, 'price': 10},
            {'categoryName': 'Local Special', 'quantity': 1, 'price': 5},
            {'id': '123', 'category': 'Other', 'quantity': 1, 'price': 10},
          ],
        ),
      ],
      products: [
        Product.fromMap('product-1', {
          'barcode': '123',
          'categoryName': 'Frozen Foods',
        }),
      ],
    );

    expect(sales, {'Frozen Foods': 30, 'Local Special': 5});
  });

  test('rounded category percentages sum to 100', () {
    final percentages = DashboardMetrics.percentageShares([1, 1, 1]);

    expect(percentages, [34, 33, 33]);
    expect(percentages.reduce((total, value) => total + value), 100);
  });

  test('excludes cancelled and refunded orders from revenue', () {
    final cancelled = StoreOrder.fromFirestore('cancelled', {
      'status': 'cancelled',
      'totalAmount': 100,
    });
    final refunded = StoreOrder.fromFirestore('refunded', {
      'status': 'refunded',
      'totalAmount': 50,
    });

    expect(
      DashboardMetrics.totalRevenue([
        order(id: 'sale', total: 25.55, createdAt: now),
        cancelled,
        refunded,
      ]),
      25.55,
    );
    expect(DashboardMetrics.estimatedProfit(25.55), 5.11);
  });

  test('computes calendar-year query bounds in Asia/Manila', () {
    expect(
      DashboardMetrics.manilaYearStartUtc(2026),
      DateTime.utc(2025, 12, 31, 16),
    );
    expect(
      DashboardMetrics.manilaNextYearStartUtc(2026),
      DateTime.utc(2026, 12, 31, 16),
    );
  });
}
