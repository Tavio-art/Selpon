import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../models/order.dart';
import '../../services/transactions_service.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TransactionsService _service = TransactionsService();
  final ScrollController _scrollController = ScrollController();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream;
  final List<TransactionRecord> _historicalRecords = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _historyCursor;
  TransactionPeriod _period = TransactionPeriod.today;
  bool _historyLoading = false;
  bool _historyHasMore = true;
  bool _periodHistoryComplete = false;
  bool _exporting = false;
  String? _historyError;

  ColorScheme get scheme => Theme.of(context).colorScheme;
  SariColors get sari => context.sari;

  static const _periodLabels = <TransactionPeriod, String>{
    TransactionPeriod.today: 'Today',
    TransactionPeriod.yesterday: 'Yesterday',
    TransactionPeriod.last7Days: 'Last 7 days',
    TransactionPeriod.last30Days: 'Last 30 days',
    TransactionPeriod.thisMonth: 'This month',
    TransactionPeriod.allTime: 'All time',
  };

  @override
  void initState() {
    super.initState();
    _ordersStream = _service.watchCurrentYearOrders();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  DateTime get _manilaNow =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  DateTime _periodStart(TransactionPeriod period) {
    final now = _manilaNow;
    final today = DateTime.utc(now.year, now.month, now.day);
    return switch (period) {
      TransactionPeriod.today => today,
      TransactionPeriod.yesterday => today.subtract(const Duration(days: 1)),
      TransactionPeriod.last7Days => today.subtract(const Duration(days: 6)),
      TransactionPeriod.last30Days => today.subtract(const Duration(days: 29)),
      TransactionPeriod.thisMonth => DateTime.utc(now.year, now.month),
      TransactionPeriod.allTime => DateTime.utc(1),
    };
  }

  bool get _needsHistory {
    if (_period == TransactionPeriod.allTime) return true;
    return _periodStart(_period).year < _manilaNow.year;
  }

  void _onScroll() {
    if (!_needsHistory ||
        _historyLoading ||
        !_historyHasMore ||
        _periodHistoryComplete) {
      return;
    }
    if (_scrollController.position.extentAfter < 500) {
      unawaited(_loadHistoryPage());
    }
  }

  Future<void> _loadHistoryPage() async {
    if (_historyLoading ||
        !_historyHasMore ||
        (_periodHistoryComplete && _period != TransactionPeriod.allTime)) {
      return;
    }
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final page = await _service.fetchHistoricalPage(
        startAfter: _historyCursor,
      );
      final records = page.docs
          .map(TransactionRecord.fromDocument)
          .toList(growable: false);
      final lastDate = records.isEmpty
          ? null
          : TransactionsService.manilaDate(records.last.order.createdAt);
      final periodStart = _periodStart(_period);
      final reachedPeriodStart =
          _period != TransactionPeriod.allTime &&
          lastDate != null &&
          lastDate.isBefore(periodStart);
      if (!mounted) return;
      setState(() {
        _historicalRecords.addAll(records);
        _historyCursor = page.docs.isEmpty ? _historyCursor : page.docs.last;
        _historyHasMore = page.docs.length == TransactionsService.pageSize;
        _periodHistoryComplete = reachedPeriodStart;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _historyError = '$error');
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  void _retry() {
    setState(() {
      _ordersStream = _service.watchCurrentYearOrders();
      _historicalRecords.clear();
      _historyCursor = null;
      _historyHasMore = true;
      _periodHistoryComplete = false;
      _historyError = null;
    });
    if (_needsHistory) unawaited(_loadHistoryPage());
  }

  void _selectPeriod(TransactionPeriod period) {
    setState(() {
      _period = period;
      _periodHistoryComplete = false;
      if (_historyHasMore &&
          period != TransactionPeriod.allTime &&
          _historicalRecords.isNotEmpty) {
        final oldest = TransactionsService.manilaDate(
          _historicalRecords.last.order.createdAt,
        );
        _periodHistoryComplete =
            oldest != null && oldest.isBefore(_periodStart(period));
      }
    });
    if (_needsHistory && _historicalRecords.isEmpty) {
      unawaited(_loadHistoryPage());
    }
  }

  String _money(double amount) =>
      '₱${NumberFormat('#,##0.00', 'en_PH').format(amount)}';

  String _receipt(TransactionRecord record) => record.receipt;

  String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  Future<void> _exportTransactions(List<TransactionRecord> records) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final rows = <String>[
        'receipt,customer,amount,payment,status,date',
        for (final record in records)
          [
            _csvCell(_receipt(record)),
            _csvCell(
              record.order.customerName.trim().isEmpty
                  ? 'Walk-in'
                  : record.order.customerName,
            ),
            record.order.total.toStringAsFixed(2),
            _csvCell(
              TransactionsService.isCredit(record.order.paymentMethod)
                  ? 'Credit'
                  : 'Cash',
            ),
            _csvCell(record.order.status.label),
            _csvCell(
              TransactionsService.manilaDate(record.order.createdAt)
                      ?.toIso8601String() ??
                  '',
            ),
          ].join(','),
      ];
      final directory = await Directory.systemTemp.createTemp(
        'sari_transactions_',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}transactions.csv',
      );
      await file.writeAsString(rows.join('\r\n'), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          title: 'Transactions',
          subject: 'Transactions',
          files: [XFile(file.path)],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Could not export transactions: $error')),
        );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showDetails(TransactionRecord record) {
    final order = record.order;
    final date = TransactionsService.manilaDate(order.createdAt);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: sari.cardSurfaceStrong,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final colors = context.sari;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              22,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Receipt ${_receipt(record)}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${order.customerName} · ${order.status.label}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.mutedText,
                    ),
                  ),
                  if (date != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM d, yyyy · h:mm a').format(date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.faintText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  for (final item in order.items)
                    _detailItem(item, theme, colors),
                  const Divider(height: 24),
                  _detailRow(
                    'Payment',
                    TransactionsService.isCredit(order.paymentMethod)
                        ? 'Credit'
                        : 'Cash',
                    theme,
                  ),
                  _detailRow('Status', order.status.label, theme),
                  _detailRow('Total', _money(order.total), theme, bold: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailItem(
    Map<String, dynamic> item,
    ThemeData theme,
    SariColors colors,
  ) {
    final name = (item['name'] ?? item['productName'] ?? 'Item').toString();
    final quantity =
        (item['quantity'] as num?)?.toInt() ??
        (item['qty'] as num?)?.toInt() ??
        1;
    final price =
        (item['price'] as num?)?.toDouble() ??
        (item['unitPrice'] as num?)?.toDouble() ??
        0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$name × $quantity',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            _money(price * quantity),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.mutedText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value,
    ThemeData theme, {
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: sari.mutedText, fontSize: 11),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transactionCard(TransactionRecord record) {
    final order = record.order;
    final isCredit = TransactionsService.isCredit(order.paymentMethod);
    final date = TransactionsService.manilaDate(order.createdAt);
    final color = isCredit ? const Color(0xFFF2A900) : sari.success;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: () => _showDetails(record),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _receipt(record),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  _money(order.total),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.customerName.trim().isEmpty
                        ? 'Walk-in'
                        : order.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: sari.mutedText, fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isCredit ? 'Credit' : 'Cash',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (date != null) ...[
              const SizedBox(height: 6),
              Text(
                DateFormat('MMM d, yyyy · h:mm a').format(date),
                style: TextStyle(color: sari.faintText, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loadingSkeleton() {
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            child: SizedBox(
              height: 74,
              child: Center(
                child: LinearProgressIndicator(
                  color: scheme.primary,
                  backgroundColor: sari.fieldFill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = _manilaNow;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _ordersStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load transactions',
                  message: '${snapshot.error}',
                  actionLabel: 'Retry',
                  onAction: _retry,
                ),
              );
            }
            final currentRecords = (snapshot.data?.docs ?? const [])
                .map(TransactionRecord.fromDocument)
                .toList(growable: false);
            final allRecords = <TransactionRecord>[
              ...currentRecords,
              ..._historicalRecords,
            ];
            final periodResult = TransactionsService.forPeriodWithOtherCount(
              allRecords,
              _period,
              now,
            );
            final displayed = periodResult.records;
            final otherCount = periodResult.otherPeriodCount;
            final loading =
                !snapshot.hasData ||
                (_needsHistory && displayed.isEmpty && _historyLoading);
            final summary = TransactionsService.summarize(displayed);
            final needEmptyHistoryCheck =
                snapshot.hasData && displayed.isEmpty && !_historyLoading;
            if (needEmptyHistoryCheck &&
                _period != TransactionPeriod.allTime &&
                _historicalRecords.isEmpty &&
                _historyCursor == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_historyLoading) {
                  unawaited(_loadHistoryPage());
                }
              });
            }

            return NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter < 500 &&
                    _needsHistory &&
                    !_historyLoading &&
                    _historyHasMore &&
                    !_periodHistoryComplete) {
                  unawaited(_loadHistoryPage());
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: scheme.onSurface,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Transactions',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _exporting
                              ? null
                              : () => _exportTransactions(displayed),
                          child: Text(_exporting ? 'Exporting...' : 'Export'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<TransactionPeriod>(
                      initialValue: _period,
                      decoration: InputDecoration(
                        labelText: 'Period',
                        filled: true,
                        fillColor: sari.fieldFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: sari.cardBorder),
                        ),
                      ),
                      dropdownColor: sari.cardSurface,
                      items: _periodLabels.entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (period) {
                        if (period != null) _selectPeriod(period);
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _statCard(
                          'Credit Sales',
                          _money(summary.creditTotal),
                          Icons.credit_card_rounded,
                        ),
                        const SizedBox(width: 8),
                        _statCard(
                          'Cash Sales',
                          _money(summary.cashTotal),
                          Icons.payments_outlined,
                        ),
                        const SizedBox(width: 8),
                        _statCard(
                          'Transactions',
                          '${summary.count}',
                          Icons.receipt_long_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (loading)
                      _loadingSkeleton()
                    else if (displayed.isEmpty)
                      Center(
                        child: Column(
                          children: [
                            const SizedBox(height: 30),
                            Text(
                              'No transactions for this period.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            if (otherCount > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                'There is $otherCount transaction in another period. Tap the period filter to change it.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: sari.mutedText),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      for (final record in displayed) _transactionCard(record),
                    if (_historyError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _historyError!,
                        style: TextStyle(color: sari.danger),
                      ),
                      TextButton(
                        onPressed: _loadHistoryPage,
                        child: const Text('Retry'),
                      ),
                    ],
                    if (_historyLoading && snapshot.hasData)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_needsHistory && _historyHasMore)
                      Center(
                        child: TextButton(
                          onPressed: _historyLoading ? null : _loadHistoryPage,
                          child: const Text('Load more'),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
