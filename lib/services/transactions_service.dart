import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/order.dart';

enum TransactionPeriod {
  today,
  yesterday,
  last7Days,
  last30Days,
  thisMonth,
  allTime,
}

class TransactionRecord {
  const TransactionRecord({
    required this.documentId,
    required this.receipt,
    required this.order,
  });

  final String documentId;
  final String receipt;
  final StoreOrder order;

  factory TransactionRecord.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final receipt = (data['receipt'] ?? '').toString().trim();
    return TransactionRecord(
      documentId: document.id,
      receipt: receipt.isNotEmpty
          ? receipt
          : document.id
                .substring(document.id.length > 6 ? document.id.length - 6 : 0)
                .toUpperCase(),
      order: StoreOrder.fromFirestore(document.id, data),
    );
  }
}

class TransactionSummary {
  const TransactionSummary({
    required this.creditTotal,
    required this.cashTotal,
    required this.count,
  });

  final double creditTotal;
  final double cashTotal;
  final int count;
}

class TransactionPeriodResult {
  const TransactionPeriodResult({
    required this.records,
    required this.otherPeriodCount,
  });

  final List<TransactionRecord> records;
  final int otherPeriodCount;
}

class TransactionsService {
  TransactionsService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const int pageSize = 50;

  DateTime get _manilaNow =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  DateTime get _currentYearStartUtc =>
      DateTime.utc(_manilaNow.year).subtract(const Duration(hours: 8));

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCurrentYearOrders() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return const Stream.empty();

    final start = _currentYearStartUtc;
    final end = DateTime.utc(_manilaNow.year + 1)
        .subtract(const Duration(hours: 8));
    return _db
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('createdAt', descending: true)
        .snapshots(includeMetadataChanges: true);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchHistoricalPage({
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to load transactions.');
    }

    Query<Map<String, dynamic>> query = _db
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .where(
          'createdAt',
          isLessThan: Timestamp.fromDate(_currentYearStartUtc),
        )
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return query.get();
  }

  static bool isCredit(String paymentMethod) {
    final method = paymentMethod.toLowerCase();
    return method.contains('credit') || method.contains('utang');
  }

  static DateTime? manilaDate(DateTime? date) =>
      date?.toUtc().add(const Duration(hours: 8));

  static List<TransactionRecord> forPeriod(
    Iterable<TransactionRecord> records,
    TransactionPeriod period,
    DateTime now,
  ) {
    final today = DateTime.utc(now.year, now.month, now.day);
    final start = switch (period) {
      TransactionPeriod.today => today,
      TransactionPeriod.yesterday => today.subtract(const Duration(days: 1)),
      TransactionPeriod.last7Days => today.subtract(const Duration(days: 6)),
      TransactionPeriod.last30Days => today.subtract(const Duration(days: 29)),
      TransactionPeriod.thisMonth => DateTime.utc(now.year, now.month),
      TransactionPeriod.allTime => DateTime.utc(1),
    };
    final end = switch (period) {
      TransactionPeriod.today => today.add(const Duration(days: 1)),
      TransactionPeriod.yesterday => today,
      TransactionPeriod.last7Days ||
      TransactionPeriod.last30Days ||
      TransactionPeriod.thisMonth ||
      TransactionPeriod.allTime => today.add(const Duration(days: 1)),
    };

    return records.where((record) {
      final date = manilaDate(record.order.createdAt);
      return date != null && !date.isBefore(start) && date.isBefore(end);
    }).toList()..sort((a, b) {
      return (b.order.createdAt ?? DateTime(1)).compareTo(
        a.order.createdAt ?? DateTime(1),
      );
    });
  }

  static TransactionPeriodResult forPeriodWithOtherCount(
    Iterable<TransactionRecord> records,
    TransactionPeriod period,
    DateTime now,
  ) {
    final all = records.toList();
    final filtered = forPeriod(all, period, now);
    return TransactionPeriodResult(
      records: filtered,
      otherPeriodCount: period == TransactionPeriod.allTime
          ? 0
          : all.length - filtered.length,
    );
  }

  static TransactionSummary summarize(Iterable<TransactionRecord> records) {
    var credit = 0.0;
    var cash = 0.0;
    var count = 0;
    for (final record in records) {
      count++;
      if (isCredit(record.order.paymentMethod)) {
        credit += record.order.total;
      } else {
        cash += record.order.total;
      }
    }
    return TransactionSummary(
      creditTotal: credit,
      cashTotal: cash,
      count: count,
    );
  }
}
