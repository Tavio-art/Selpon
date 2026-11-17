import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_bottom_nav.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_page_header.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_indicator.dart';
import '../../l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../services/firebase_service.dart';
import '../../services/product_repository.dart';
import '../../services/settings_store.dart';
import '../../services/user_profile_store.dart';
import '../../widgets/stat_card.dart';
import '../home/product_detail_screen.dart';

class InventoryScreen extends StatefulWidget {
  final String? userName;

  const InventoryScreen({
    super.key,
    this.userName,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

enum _InventoryFilter { all, lowStock, bestSellers, outOfStock }

class _InventoryScreenState extends State<InventoryScreen> {
  final ProductRepository _products = ProductRepository.instance;
  final UserProfileStore _profile = UserProfileStore.instance;
  final FirebaseService _firebase = FirebaseService();
  final _searchController = TextEditingController();
  _InventoryFilter _filter = _InventoryFilter.all;

  @override
  void initState() {
    super.initState();
    _profile.ensureLoaded();
  }

  void _retryProducts() {
    _products.refreshProducts();
  }

  /// Sold qty keyed by product id (same matching rules as the old best-seller card).
  Map<String, int> _soldQuantities(
    List<Product> products,
    QuerySnapshot? orders,
  ) {
    final productKeys = <String, String>{};
    for (final product in products) {
      final key = product.id;
      if (product.barcode.isNotEmpty) {
        productKeys[product.barcode.toLowerCase()] = key;
      }
      productKeys[key.toLowerCase()] = key;
    }

    final quantities = <String, int>{};
    for (final order in orders?.docs ?? const []) {
      final data = order.data();
      if (data is! Map<String, dynamic>) continue;
      final items = data['items'];
      if (items is! List) continue;
      for (final rawItem in items) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final barcode =
            (item['barcode'] ?? item['id'] ?? '').toString().toLowerCase();
        final productKey = productKeys[barcode];
        if (productKey == null) continue;
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        if (quantity <= 0) continue;
        quantities.update(
          productKey,
          (previous) => previous + quantity,
          ifAbsent: () => quantity,
        );
      }
    }
    return quantities;
  }

  /// Top sellers by units sold (up to 5) — card count matches filtered list size.
  Set<String> _bestSellerIds(
    List<Product> products,
    QuerySnapshot? orders,
  ) {
    final quantities = _soldQuantities(products, orders);
    if (quantities.isEmpty) return {};
    final ranked = quantities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(5).map((e) => e.key).toSet();
  }

  /// Web-aligned inventory value: Σ (price × stock).
  double _inventoryValue(List<Product> products) {
    return products.fold<double>(
      0,
      (total, p) => total + (p.price * p.stock),
    );
  }

  void _onFilterTap(_InventoryFilter next) {
    setState(() {
      // Tap active filter again (or Total Items) → show all.
      if (next == _InventoryFilter.all || _filter == next) {
        _filter = _InventoryFilter.all;
      } else {
        _filter = next;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getStockColor(int stock) {
    final sari = context.sari;
    if (stock == 0) {
      return sari.danger;
    } else if (stock <= Product.lowStockThreshold) {
      return sari.accentAmber;
    } else {
      return sari.success;
    }
  }

  void _openFullEdit(Product product) {
    ProductDetailScreen.show(context, product: product);
  }

  void _showQuickEditDialog(Product product) {
    final priceController =
        TextEditingController(text: product.price.toStringAsFixed(2));
    final stockController =
        TextEditingController(text: product.stock.toString());
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sari = context.sari;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: sari.cardSurface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: GoogleFonts.outfit(
                  color: scheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.text('quickUpdatePriceStock'),
                style: GoogleFonts.outfit(
                  color: sari.mutedText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                hintText: context.l10n.text(
                  'priceLabel',
                  values: {'symbol': SettingsStore.instance.currencySymbol},
                ),
                prefixIcon: Icons.payments_outlined,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: stockController,
                keyboardType: TextInputType.number,
                hintText: context.l10n.text('stockQuantity'),
                prefixIcon: Icons.layers_outlined,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _openFullEdit(product);
                  },
                  child: Text(
                    context.l10n.text('editAllDetails'),
                    style: GoogleFonts.outfit(
                      color: sari.accentAmber,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                context.l10n.text('cancel'),
                style: GoogleFonts.outfit(color: sari.mutedText),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final parsedPrice =
                    double.tryParse(priceController.text.trim());
                final parsedStock = int.tryParse(stockController.text.trim());
                if (parsedPrice == null || parsedPrice < 0) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.text('invalidPrice')),
                        backgroundColor: sari.danger,
                      ),
                    );
                  }
                  return;
                }
                if (parsedStock == null || parsedStock < 0) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                      SnackBar(
                        content: Text(context.l10n.text('quantityMinimum')),
                        backgroundColor: sari.danger,
                      ),
                    );
                  }
                  return;
                }

                final updated = Product(
                  id: product.id,
                  name: product.name,
                  size: product.size,
                  category: product.category,
                  sku: product.sku,
                  price: parsedPrice,
                  stock: parsedStock,
                  imageUrl: product.imageUrl,
                  barcode: product.barcode,
                  catalogProductId: product.catalogProductId.isNotEmpty
                      ? product.catalogProductId
                      : (product.isCatalogOnly ? product.id : ''),
                );

                try {
                  await _products.updateProduct(
                    product.barcode,
                    updated,
                    oldInventoryId: product.id,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                } catch (e) {
                  if (!dialogCtx.mounted) return;
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.text(
                        'failed',
                        values: {'error': '$e'},
                      )),
                      backgroundColor: sari.danger,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(context.l10n.text('save')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteProduct(Product product) async {
    final confirm = await ConfirmDialog.show(
      context,
      title: context.l10n.text('removeProductTitle'),
      message: context.l10n
          .text('removeProductMessage', values: {'name': product.name}),
      confirmLabel: context.l10n.text('remove'),
      cancelLabel: context.l10n.text('keep'),
      isDestructive: true,
    );

    if (confirm != true) return;
    try {
      await _products.deleteProduct(product);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('productRemoved'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text(
            'failed',
            values: {'error': '$e'},
          )),
          backgroundColor: context.sari.danger,
        ),
      );
    }
  }

  Widget _productActions(
    Product product,
    ColorScheme scheme,
    SariColors sari, {
    required double tap,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          onPressed: () => _showQuickEditDialog(product),
          tooltip: context.l10n.text('edit'),
          icon: Icon(Icons.edit_outlined, size: 18, color: scheme.primary),
          constraints: BoxConstraints(minWidth: tap, minHeight: tap),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: () => _deleteProduct(product),
          tooltip: context.l10n.text('remove'),
          icon: Icon(
            Icons.delete_outline_rounded,
            size: 18,
            color: sari.danger.withValues(alpha: 0.85),
          ),
          constraints: BoxConstraints(minWidth: tap, minHeight: tap),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _stockChip(int stock, Color stockColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: stockColor.withValues(alpha: 0.18),
        border: Border.all(
          color: stockColor.withValues(alpha: 0.6),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$stock',
        style: GoogleFonts.outfit(
          color: stockColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _tableRow({
    required bool compact,
    required Widget item,
    required Widget code,
    required Widget price,
    required Widget stock,
    required Widget actions,
  }) {
    final priceW = compact ? 58.0 : 84.0;
    final stockW = compact ? 40.0 : 60.0;
    final actionsW = compact ? 64.0 : 88.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: compact ? 5 : 4, child: item),
        const SizedBox(width: 6),
        Expanded(flex: compact ? 4 : 3, child: code),
        const SizedBox(width: 6),
        SizedBox(width: priceW, child: price),
        SizedBox(width: stockW, child: stock),
        SizedBox(width: actionsW, child: actions),
      ],
    );
  }

  Widget _headerCell(
    String text,
    TextStyle style, {
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(text, maxLines: 1, style: style),
      ),
    );
  }

  Widget _productListRow({
    required Product product,
    required bool compact,
    required ColorScheme scheme,
    required SariColors sari,
  }) {
    final stockColor = _getStockColor(product.stock);
    final nameStyle = GoogleFonts.outfit(
      color: scheme.onSurface,
      fontSize: compact ? 12 : 13,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );

    final barcodeLength = product.barcode.length;
    final double barcodeFontSize =
        compact ? (barcodeLength > 10 ? 9.0 : 10.5) : 11.0;

    final metaStyle = GoogleFonts.outfit(
      color: sari.mutedText,
      fontSize: barcodeFontSize,
      letterSpacing: -0.2,
      height: 1.2,
    );
    final priceStyle = GoogleFonts.outfit(
      color: scheme.onSurface,
      fontSize: compact ? 11.5 : 12,
      fontWeight: FontWeight.w700,
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10, horizontal: 2),
      child: _tableRow(
        compact: compact,
        item: Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: nameStyle,
        ),
        code: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            product.barcode.isNotEmpty ? product.barcode : '—',
            maxLines: 1,
            style: metaStyle,
          ),
        ),
        price: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            SettingsStore.instance.formatMoney(product.price),
            style: priceStyle,
          ),
        ),
        stock: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: _stockChip(product.stock, stockColor),
          ),
        ),
        actions: _productActions(
          product,
          scheme,
          sari,
          tap: compact ? 30 : 40,
        ),
      ),
    );
  }

  Widget _inventoryTable(
    List<Product> items,
    ColorScheme scheme,
    SariColors sari,
  ) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 520;

          final headerStyle = GoogleFonts.outfit(
            color: scheme.onSurface.withValues(alpha: 0.75),
            fontSize: compact ? 10 : 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: compact ? 0.4 : 0.6,
          );

          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: _tableRow(
                  compact: compact,
                  item: _headerCell(context.l10n.text('colItem'), headerStyle),
                  code: _headerCell(context.l10n.text('colCode'), headerStyle),
                  price:
                      _headerCell(context.l10n.text('colPrice'), headerStyle),
                  stock:
                      _headerCell(context.l10n.text('colStock'), headerStyle),
                  actions: _headerCell(
                    context.l10n.text('colActions'),
                    headerStyle,
                    alignment: Alignment.centerRight,
                  ),
                ),
              ),
              Divider(color: sari.cardBorder, thickness: 1, height: 8),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          context.l10n.text('noProducts'),
                          style: GoogleFonts.outfit(
                            color: sari.mutedText,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.only(
                          bottom: AppBottomNav.occupiedHeight(context) + 16,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => Divider(
                          color: sari.cardBorder,
                          height: 1,
                          thickness: 0.5,
                        ),
                        itemBuilder: (context, index) => _productListRow(
                          product: items[index],
                          compact: compact,
                          scheme: scheme,
                          sari: sari,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sari = context.sari;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.15,
        ),
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: Listenable.merge([
              _profile,
              _products.productsWatchGeneration,
              SettingsStore.instance,
            ]),
            builder: (context, _) {
              final storeName = _profile.headerStoreName;
              final productStream = _products.watchProducts();

              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppPageHeader(
                      leading: AppPageHeader.iconBadge(
                        context: context,
                        icon: Icons.storefront_rounded,
                      ),
                      title: storeName,
                      subtitle: context.l10n.text('manageStore'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.outfit(
                        color: scheme.onSurface,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: context.l10n.text('searchItems'),
                        hintStyle: GoogleFonts.outfit(
                          color: sari.faintText,
                          fontSize: 13.5,
                        ),
                        prefixIcon:
                            Icon(Icons.search, color: sari.mutedText, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear,
                                    color: sari.mutedText, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: sari.fieldFill,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: sari.cardBorder,
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: sari.cardBorder,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide(
                            color: scheme.primary,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: StreamBuilder<List<Product>>(
                        stream: productStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return EmptyState(
                              icon: Icons.error_outline_rounded,
                              title: context.l10n.text('inventoryLoadFailed'),
                              message: '${snapshot.error}',
                              actionLabel: context.l10n.text('tryAgain'),
                              onAction: _retryProducts,
                            );
                          }

                          if (!snapshot.hasData) {
                            return const LoadingIndicator();
                          }

                          final products = snapshot.data!;
                          final totalItems = products.length;
                          final lowStockItems =
                              products.where((p) => p.isLowStock).toList();
                          final outOfStockItems =
                              products.where((p) => p.isOutOfStock).toList();
                          final inventoryValue = _inventoryValue(products);

                          return StreamBuilder<QuerySnapshot>(
                            stream: _firebase.getOrdersStream(limit: 200),
                            builder: (context, ordersSnapshot) {
                              final bestSellerIds = ordersSnapshot.hasError
                                  ? <String>{}
                                  : _bestSellerIds(
                                      products,
                                      ordersSnapshot.data,
                                    );
                              final bestSellerItems = products
                                  .where((p) => bestSellerIds.contains(p.id))
                                  .toList();

                              final query =
                                  _searchController.text.toLowerCase().trim();
                              bool matchesSearch(Product p) {
                                if (query.isEmpty) return true;
                                return p.name.toLowerCase().contains(query) ||
                                    p.barcode.toLowerCase().contains(query) ||
                                    p.category.toLowerCase().contains(query);
                              }

                              late final List<Product> source;
                              late final String emptyMessage;
                              switch (_filter) {
                                case _InventoryFilter.lowStock:
                                  source = lowStockItems;
                                  emptyMessage =
                                      context.l10n.text('noLowStockItems');
                                  break;
                                case _InventoryFilter.bestSellers:
                                  source = bestSellerItems;
                                  emptyMessage =
                                      context.l10n.text('noBestSellerItems');
                                  break;
                                case _InventoryFilter.outOfStock:
                                  source = outOfStockItems;
                                  emptyMessage =
                                      context.l10n.text('noOutOfStockItems');
                                  break;
                                case _InventoryFilter.all:
                                  source = products;
                                  emptyMessage =
                                      context.l10n.text('noProducts');
                                  break;
                              }

                              final filteredProducts =
                                  source.where(matchesSearch).toList();

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  StatCard(
                                    label: context.l10n
                                        .text('inventoryValueStat'),
                                    value: SettingsStore.instance
                                        .formatMoney(inventoryValue),
                                    icon: Icons.payments_outlined,
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: StatCard(
                                          label: context.l10n
                                              .text('totalItemsStat'),
                                          value: '$totalItems',
                                          icon: Icons.inventory_2_outlined,
                                          selected: _filter ==
                                              _InventoryFilter.all,
                                          onTap: () => _onFilterTap(
                                            _InventoryFilter.all,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: StatCard(
                                          label: context.l10n
                                              .text('lowStockStat'),
                                          value: '${lowStockItems.length}',
                                          valueColor: lowStockItems.isNotEmpty
                                              ? sari.accentAmber
                                              : null,
                                          icon: Icons.warning_amber_rounded,
                                          iconColor: sari.accentAmber,
                                          selected: _filter ==
                                              _InventoryFilter.lowStock,
                                          onTap: () => _onFilterTap(
                                            _InventoryFilter.lowStock,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: StatCard(
                                          label: context.l10n
                                              .text('bestSellersStat'),
                                          value: ordersSnapshot.hasError
                                              ? '—'
                                              : '${bestSellerItems.length}',
                                          icon: Icons.trending_up_rounded,
                                          selected: _filter ==
                                              _InventoryFilter.bestSellers,
                                          onTap: ordersSnapshot.hasError
                                              ? null
                                              : () => _onFilterTap(
                                                    _InventoryFilter
                                                        .bestSellers,
                                                  ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: StatCard(
                                          label: context.l10n
                                              .text('outOfStockStat'),
                                          value: '${outOfStockItems.length}',
                                          valueColor:
                                              outOfStockItems.isNotEmpty
                                                  ? sari.danger
                                                  : null,
                                          icon: Icons
                                              .remove_circle_outline_rounded,
                                          iconColor: sari.danger,
                                          selected: _filter ==
                                              _InventoryFilter.outOfStock,
                                          onTap: () => _onFilterTap(
                                            _InventoryFilter.outOfStock,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: filteredProducts.isEmpty
                                        ? AppCard(
                                            padding: const EdgeInsets.all(24),
                                            child: Center(
                                              child: Text(
                                                query.isNotEmpty &&
                                                        source.isNotEmpty
                                                    ? context.l10n
                                                        .text('noProducts')
                                                    : emptyMessage,
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.outfit(
                                                  color: sari.mutedText,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          )
                                        : _inventoryTable(
                                            filteredProducts,
                                            scheme,
                                            sari,
                                          ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
