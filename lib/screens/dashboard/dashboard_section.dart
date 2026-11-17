import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/app_bottom_nav.dart';
import '../../core/widgets/app_page_header.dart';
import '../../l10n/app_localizations.dart';
import '../../models/order.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_store.dart';
import '../../services/settings_store.dart';
import '../../theme/app_theme.dart';
import 'dashboard_metrics.dart';

/// Web-aligned category labels used for the Sales by Category donut.
const _kWebCategories = <String>[
  'Beverages',
  'Coffee & Tea',
  'Snacks',
  'Noodles',
  'Canned Goods',
  'Condiments',
  'Personal Care',
  'Household',
];

const _kCategoryColors = <Color>[
  Color(0xFF2E7D4F),
  Color(0xFF4CAF71),
  Color(0xFFC9A227),
  Color(0xFF5B8DEF),
  Color(0xFFE07A3D),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
  Color(0xFFEF4444),
  Color(0xFF94A3B8),
];

/// Full-page dashboard used as a bottom-nav tab.
class DashboardSection extends StatefulWidget {
  const DashboardSection({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<DashboardSection> createState() => _DashboardSectionState();
}

class _DashboardSectionState extends State<DashboardSection> {
  SariColors get sari => context.sari;
  ColorScheme get scheme => Theme.of(context).colorScheme;

  late final Query<Map<String, dynamic>>? _ordersQuery;
  late final Stream<QuerySnapshot<Map<String, dynamic>>>? _ordersStream;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) {
      _ordersQuery = null;
      _ordersStream = null;
      return;
    }

    final now = _manilaNow();
    final yearStartUtc =
        DateTime.utc(now.year).subtract(const Duration(hours: 8));
    final nextYearStartUtc = DateTime.utc(now.year + 1)
        .subtract(const Duration(hours: 8));
    _ordersQuery = FirebaseFirestore.instance
        .collection(FirebaseService.ordersPath)
        .where('userId', isEqualTo: userId)
        .where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(yearStartUtc),
        )
        .where(
          'createdAt',
          isLessThan: Timestamp.fromDate(nextYearStartUtc),
        )
        .orderBy('createdAt', descending: true);
    _ordersStream = _ordersQuery!.snapshots(includeMetadataChanges: true);
  }

  Future<void> _refreshFromServer() async {
    final query = _ordersQuery;
    if (query == null) return;
    try {
      await query.get(const GetOptions(source: Source.server));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  DateTime? _manilaTime(DateTime? date) =>
      date?.toUtc().add(const Duration(hours: 8));

  DateTime _manilaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));

  @override
  Widget build(BuildContext context) {
    final settings = SettingsStore.instance;
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: widget.isActive ? _ordersStream : null,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return RefreshIndicator(
                    color: scheme.primary,
                    onRefresh: _refreshFromServer,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      children: [
                        const SizedBox(height: 80),
                        _panel(
                          child: Text(
                            l10n.text(
                              'couldNotLoadDashboard',
                              values: {'error': '${snapshot.error}'},
                            ),
                            style: GoogleFonts.outfit(
                              color: sari.danger,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.5,
                        child: Center(
                          child: CircularProgressIndicator(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                final now = _manilaNow();
                final orders =
                    snapshot.data!.docs
                        .map(
                          (doc) => StoreOrder.fromFirestore(doc.id, doc.data()),
                        )
                        .where((order) {
                          final createdAt = _manilaTime(order.createdAt);
                          return createdAt != null &&
                              createdAt.year == now.year;
                        })
                        .toList()
                      ..sort(
                        (a, b) =>
                            (_manilaTime(b.createdAt) ?? DateTime.utc(1970))
                                .compareTo(
                                  _manilaTime(a.createdAt) ??
                                      DateTime.utc(1970),
                                ),
                      );
                unawaited(
                  NotificationStore.instance.updateOrders(
                    orders,
                    isFromCache: snapshot.data!.metadata.isFromCache,
                  ),
                );
                final isSyncing =
                    snapshot.data!.metadata.isFromCache ||
                    snapshot.data!.metadata.hasPendingWrites;

                return RefreshIndicator(
                  color: scheme.primary,
                  onRefresh: _refreshFromServer,
                  child: _buildBody(
                    settings,
                    l10n,
                    locale,
                    orders,
                    now,
                    isSyncing,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    SettingsStore settings,
    AppLocalizations l10n,
    String locale,
    List<StoreOrder> orders,
    DateTime now,
    bool isSyncing,
  ) {
    final day30 = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 29));
    final metrics = DashboardMetrics.fromOrders(
      orders: orders,
      taxRate: settings.taxRate,
      now: now,
    );

    var revenue30 = 0.0;
    var tx30 = 0;
    for (final o in orders) {
      final when = _manilaTime(o.createdAt);
      if (when == null || when.isBefore(day30)) continue;
      revenue30 += o.total;
      tx30++;
    }
    final profit30 = revenue30 * 0.20;
    const profitMargin = 20.0;
    final avgSale = tx30 > 0 ? revenue30 / tx30 : 0.0;

    final yearRevenue = List<double>.filled(12, 0);
    final yearProfit = List<double>.filled(12, 0);
    for (final o in orders) {
      final when = _manilaTime(o.createdAt);
      if (when == null || when.year != now.year) continue;
      yearRevenue[when.month - 1] += o.total;
      yearProfit[when.month - 1] += o.total * 0.20;
    }

    final categoryTotals = <String, double>{};
    for (final o in orders) {
      for (final item in o.items) {
        final cat = _normalizeCategory((item['category'] ?? '').toString());
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        final sub = (item['subtotal'] as num?)?.toDouble() ?? (price * qty);
        categoryTotals[cat] = (categoryTotals[cat] ?? 0) + sub;
      }
    }
    final categoryEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final categorySum = categoryEntries.fold<double>(0, (s, e) => s + e.value);

    final monthSoldQty = <String, int>{};
    final monthSoldRev = <String, double>{};
    for (final o in orders) {
      final when = _manilaTime(o.createdAt);
      if (when == null || when.year != now.year || when.month != now.month) {
        continue;
      }
      for (final item in o.items) {
        final name = (item['name'] ?? 'Item').toString();
        final qty = (item['quantity'] as num?)?.toInt() ?? 0;
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        final sub = (item['subtotal'] as num?)?.toDouble() ?? (price * qty);
        monthSoldQty[name] = (monthSoldQty[name] ?? 0) + qty;
        monthSoldRev[name] = (monthSoldRev[name] ?? 0) + sub;
      }
    }
    final topProducts = monthSoldQty.entries.toList()
      ..sort((a, b) {
        final q = b.value.compareTo(a.value);
        if (q != 0) return q;
        return (monthSoldRev[b.key] ?? 0).compareTo(monthSoldRev[a.key] ?? 0);
      });
    final top5 = topProducts.take(5).toList();

    var cashTotal = 0.0;
    var creditTotal = 0.0;
    for (final o in orders) {
      final method = o.paymentMethod.toLowerCase();
      if (method.contains('credit') || method.contains('utang')) {
        creditTotal += o.total;
      } else {
        cashTotal += o.total;
      }
    }
    final paySum = cashTotal + creditTotal;
    final cashPct = paySum > 0 ? (cashTotal / paySum) * 100 : 0.0;
    final creditPct = paySum > 0 ? (creditTotal / paySum) * 100 : 0.0;

    final monthLabels = List<String>.generate(
      12,
      (i) => DateFormat('MMM', locale).format(DateTime(now.year, i + 1)),
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        6,
        20,
        AppBottomNav.bodyBottomInset(context),
      ),
      children: [
        AppPageHeader(
          leading: AppPageHeader.iconBadge(
            context: context,
            icon: Icons.bar_chart_rounded,
          ),
          title: l10n.text('dashboard'),
          subtitle: DateFormat('EEEE, MMM d', locale).format(now),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            isSyncing ? 'Syncing...' : 'Synced',
            style: GoogleFonts.outfit(
              color: sari.faintText,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Compact Sales Today + Transactions Today
        Row(
          children: [
            Expanded(
              child: _compactStat(
                label: l10n.text('salesToday'),
                value: settings.formatMoney(metrics.salesToday),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _compactStat(
                label: 'Transactions Today',
                value: '${metrics.transactionsToday}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // KPI 2x2
        LayoutBuilder(
          builder: (context, constraints) {
            final w = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: w,
                  child: _kpiCard(
                    title: 'Total Revenue (30D)',
                    value: settings.formatMoney(revenue30),
                    subtitle: '$tx30 total transactions',
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _kpiCard(
                    title: 'Total Profit (30D)',
                    value: settings.formatMoney(profit30),
                    subtitle: 'Estimated (20%)',
                    valueColor: sari.accentAmber,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _kpiCard(
                    title: 'Profit Margin',
                    value: '${profitMargin.toStringAsFixed(0)}%',
                    subtitle: 'Standard estimate',
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _kpiCard(
                    title: 'Avg. Sale Value',
                    value: settings.formatMoney(avgSale),
                    subtitle: 'Per transaction',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),

        // Revenue & Profit Trend
        Text(
          'Revenue & Profit Trend (current year)',
          style: GoogleFonts.outfit(
            color: scheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _panel(
          padding: const EdgeInsets.fromLTRB(8, 14, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                child: Row(
                  children: [
                    _legendDot(scheme.primary, 'Revenue'),
                    const SizedBox(width: 14),
                    _legendDot(sari.accentAmber, 'Profit', dashed: true),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 220,
                width: double.infinity,
                child: _yearTrendChart(
                  revenue: yearRevenue,
                  profit: yearProfit,
                  labels: monthLabels,
                  settings: settings,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // Sales by Category
        Text(
          'Sales by Category',
          style: GoogleFonts.outfit(
            color: scheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _panel(
          child: categorySum <= 0
              ? Text(
                  'No sales yet',
                  style: GoogleFonts.outfit(
                    color: sari.mutedText,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 180,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 42,
                          sections: [
                            for (var i = 0; i < categoryEntries.length; i++)
                              PieChartSectionData(
                                color:
                                    _kCategoryColors[i %
                                        _kCategoryColors.length],
                                value: categoryEntries[i].value,
                                title: '',
                                radius: 34,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (var i = 0; i < categoryEntries.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color:
                                    _kCategoryColors[i %
                                        _kCategoryColors.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                l10n.category(categoryEntries[i].key),
                                style: GoogleFonts.outfit(
                                  color: scheme.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              '${((categoryEntries[i].value / categorySum) * 100).toStringAsFixed(0)}%',
                              style: GoogleFonts.outfit(
                                color: sari.mutedText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 22),

        // Top Products This Month
        Text(
          'Top Products This Month',
          style: GoogleFonts.outfit(
            color: scheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: top5.isEmpty
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: sari.faintText,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No sales yet - complete a checkout to see top products',
                        softWrap: true,
                        style: GoogleFonts.outfit(
                          color: sari.mutedText,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            'Product',
                            style: GoogleFonts.outfit(
                              color: sari.mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Units',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.outfit(
                              color: sari.mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Revenue',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.outfit(
                              color: sari.mutedText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < top5.length; i++) ...[
                      if (i > 0) Divider(height: 14, color: sari.cardBorder),
                      Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Text(
                              top5[i].key,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                              style: GoogleFonts.outfit(
                                color: scheme.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '${top5[i].value}',
                              textAlign: TextAlign.right,
                              style: GoogleFonts.outfit(
                                color: scheme.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              settings.formatMoney(
                                monthSoldRev[top5[i].key] ?? 0,
                              ),
                              textAlign: TextAlign.right,
                              style: GoogleFonts.outfit(
                                color: sari.accentAmber,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 22),

        // Payment Method Mix
        Text(
          'Payment Method Mix',
          style: GoogleFonts.outfit(
            color: scheme.onSurface,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _panel(
          child: Column(
            children: [
              _payRow(color: scheme.primary, label: 'Cash', percent: cashPct),
              const SizedBox(height: 12),
              _payRow(
                color: sari.accentAmber,
                label: 'Credit',
                percent: creditPct,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _normalizeCategory(String raw) {
    final n = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return 'Other';
    if (n == 'beverage' || n == 'beverages') return 'Beverages';
    if (n.startsWith('coffee') || n.contains('tea')) return 'Coffee & Tea';
    if (n.contains('snack')) return 'Snacks';
    if (n.contains('noodle')) return 'Noodles';
    if (n.startsWith('cann')) return 'Canned Goods';
    if (n.contains('condiment') || n.contains('sauce')) return 'Condiments';
    if (n.contains('personal')) return 'Personal Care';
    if (n.contains('household') || n.contains('cleaning')) return 'Household';
    for (final known in _kWebCategories) {
      if (known.toLowerCase() == n) return known;
    }
    return 'Other';
  }

  Widget _compactStat({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: sari.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sari.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: sari.mutedText,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: GoogleFonts.outfit(
                color: scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: sari.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: sari.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: sari.mutedText,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: GoogleFonts.outfit(
                color: valueColor ?? scheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: sari.faintText,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Nice top of Y-axis for ~4 evenly spaced labels.
  double _niceChartMax(double maxVal) {
    if (maxVal <= 0) return 10;
    final padded = maxVal * 1.1;
    final exp = (math.log(padded) / math.ln10).floor();
    final base = math.pow(10, exp).toDouble();
    final fraction = padded / base;
    final double niceFraction;
    if (fraction <= 1) {
      niceFraction = 1;
    } else if (fraction <= 2) {
      niceFraction = 2;
    } else if (fraction <= 5) {
      niceFraction = 5;
    } else {
      niceFraction = 10;
    }
    return niceFraction * base;
  }

  Widget _legendDot(Color color, String label, {bool dashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dashed)
          SizedBox(
            width: 16,
            child: CustomPaint(
              painter: _DashLinePainter(color),
              size: const Size(16, 2),
            ),
          )
        else
          Container(
            width: 16,
            height: 3,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: sari.mutedText,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _payRow({
    required Color color,
    required String label,
    required double percent,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '${percent.toStringAsFixed(0)}%',
          style: GoogleFonts.outfit(
            color: sari.mutedText,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: sari.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: sari.cardBorder),
      ),
      child: child,
    );
  }

  Widget _yearTrendChart({
    required List<double> revenue,
    required List<double> profit,
    required List<String> labels,
    required SettingsStore settings,
  }) {
    final maxVal = [
      ...revenue,
      ...profit,
    ].fold<double>(0, (m, v) => v > m ? v : m);
    final chartMax = _niceChartMax(maxVal);
    final interval = chartMax / 4;
    final hasData = maxVal > 0;

    final revenueSpots = List<FlSpot>.generate(
      12,
      (i) => FlSpot(i.toDouble(), revenue[i].clamp(0, double.infinity)),
    );
    final profitSpots = List<FlSpot>.generate(
      12,
      (i) => FlSpot(i.toDouble(), profit[i].clamp(0, double.infinity)),
    );

    return Stack(
      children: [
        LineChart(
          LineChartData(
            minX: 0,
            maxX: 11,
            minY: 0,
            maxY: chartMax,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: interval,
              getDrawingHorizontalLine: (value) => FlLine(
                color: scheme.onSurface.withValues(alpha: 0.06),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              enabled: hasData,
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => sari.cardSurface,
                getTooltipItems: (touched) {
                  return touched.map((spot) {
                    final i = spot.x.toInt();
                    if (i < 0 || i >= labels.length) return null;
                    final isProfit = spot.barIndex == 1;
                    return LineTooltipItem(
                      '${labels[i]} ${isProfit ? 'Profit' : 'Revenue'}\n'
                      '${settings.formatMoney(spot.y)}',
                      GoogleFonts.outfit(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    );
                  }).toList();
                },
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 52,
                  interval: interval,
                  getTitlesWidget: (value, meta) {
                    // Skip edge duplicates / floating-point noise.
                    if (value < -0.001 || value > chartMax + 0.001) {
                      return const SizedBox.shrink();
                    }
                    final nearZero = value.abs() < interval * 0.05;
                    final nearMax = (value - chartMax).abs() < interval * 0.05;
                    if (!nearZero &&
                        !nearMax &&
                        (value / interval - (value / interval).round()).abs() >
                            0.05) {
                      return const SizedBox.shrink();
                    }
                    final compact = settings.formatMoneyCompact(value);
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 6,
                      child: SizedBox(
                        width: 46,
                        child: Text(
                          compact,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: GoogleFonts.outfit(
                            color: sari.faintText,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= labels.length || i % 2 != 0) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 6,
                      child: Text(
                        labels[i],
                        style: GoogleFonts.outfit(
                          color: sari.faintText,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: revenueSpots,
                isCurved: true,
                curveSmoothness: 0.28,
                preventCurveOverShooting: true,
                preventCurveOvershootingThreshold: 4.0,
                color: scheme.primary,
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  cutOffY: 0,
                  applyCutOffY: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.primary.withValues(alpha: 0.28),
                      scheme.primary.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
              LineChartBarData(
                spots: profitSpots,
                isCurved: true,
                curveSmoothness: 0.28,
                preventCurveOverShooting: true,
                preventCurveOvershootingThreshold: 4.0,
                color: sari.accentAmber,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dashArray: const [6, 4],
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 450),
        ),
        if (!hasData)
          Center(
            child: Text(
              'No sales yet',
              style: GoogleFonts.outfit(
                color: sari.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _DashLinePainter extends CustomPainter {
  _DashLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const dash = 3.0;
    const gap = 2.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + dash, size.width), y),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
