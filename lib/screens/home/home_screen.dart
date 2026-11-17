import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/app_bottom_nav.dart';
import '../../core/widgets/app_page_header.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_search_bar.dart';
import '../../core/widgets/app_snackbar.dart';
import '../../core/widgets/cart_added_popup.dart';
import '../../core/widgets/category_chip.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_indicator.dart';
import '../../core/widgets/product_card.dart';
import '../../core/widgets/section_header.dart';
import '../../l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../services/cart_store.dart';
import '../../services/notification_store.dart';
import '../../services/product_repository.dart';
import '../../services/user_profile_store.dart';

class HomeScreen extends StatefulWidget {
  final String? userName;
  final VoidCallback? onOpenCart;
  final VoidCallback? onOpenNotif;
  final VoidCallback? onOpenProfile;

  const HomeScreen({
    super.key,
    this.userName,
    this.onOpenCart,
    this.onOpenNotif,
    this.onOpenProfile,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ProductRepository _products = ProductRepository.instance;
  final UserProfileStore _profile = UserProfileStore.instance;
  String _selectedCategory = 'All';
  final _searchController = TextEditingController();
  Timer? _cartPopupTimer;
  bool _showCartPopup = false;
  String? _lastAddedProductName;
  int _lastAddedQuantity = 1;

  @override
  void initState() {
    super.initState();
    _profile.ensureLoaded();
  }

  void _retryProducts() {
    _products.refreshProducts();
  }

  List<String> _categoriesFor(Iterable<Product> products) {
    final categories = <String, String>{};

    for (final product in products) {
      final category = product.category.trim();
      if (category.isEmpty) continue;

      final normalized = category
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (normalized == 'id') continue;

      if (normalized == 'beverage' || normalized == 'beverages') {
        categories['beverages'] = 'Beverages';
      } else if (normalized.startsWith('cann')) {
        categories['canned goods'] = 'Canned Goods';
      } else {
        categories.putIfAbsent(normalized, () => category);
      }
    }

    final result = categories.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return ['All', ...result];
  }

  List<Product> _dedupe(List<Product> products) {
    final unique = <String, Product>{};

    for (final p in products) {
      final name = p.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      final size = p.size.toString().toLowerCase().trim();
      final key = '$name|$size';

      final existing = unique[key];
      if (existing == null) {
        unique[key] = p;
        continue;
      }

      final keepNew = (existing.isCatalogOnly && !p.isCatalogOnly) ||
          (existing.isCatalogOnly == p.isCatalogOnly &&
              p.stock > existing.stock);
      if (keepNew) unique[key] = p;
    }

    return unique.values.toList();
  }

  bool _categoryMatches(String productCat, String selectedCat) {
    final p = productCat
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final s = selectedCat
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (s == 'all') return true;
    if (p == s) return true;

    if ((p == 'beverage' || p == 'beverages') && s == 'beverages') {
      return true;
    }

    if (s == 'canned goods' && p.startsWith('cann')) {
      return true;
    }

    if (p.startsWith(s) || s.startsWith(p)) return true;

    if (s == 'snacks' &&
        (p.contains('snack') ||
            p.contains('chip') ||
            p.contains('biscuit') ||
            p.contains('cracker'))) {
      return true;
    }

    if (s == 'beverages' &&
        (p.contains('beverag') ||
            p.contains('drink') ||
            p.contains('juice') ||
            p.contains('soda') ||
            p.contains('alcohol'))) {
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    _cartPopupTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _goToCart() {
    final openCart = widget.onOpenCart;

    if (openCart != null) {
      openCart();
    } else {
      CartStore.instance.requestOpenCart();
    }
  }

  void _addToCart(Product product) {
    try {
      CartStore.instance.add(product);
    } catch (e) {
      AppSnackbar.showError(
        context,
        context.l10n.text('failed', values: {'error': '$e'}),
      );
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    _cartPopupTimer?.cancel();
    setState(() {
      _lastAddedProductName = product.name.trim();
      _lastAddedQuantity = 1;
      _showCartPopup = true;
    });

    _cartPopupTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _showCartPopup = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sari = context.sari;
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            CartStore.instance,
            _profile,
            _products.productsWatchGeneration,
          ]),
          builder: (context, _) {
            final cartItemCount = CartStore.instance.itemCount;
            // Home draws under the floating nav — clear bar + Scan FAB + gap.
            final navBottomInset = AppBottomNav.bodyBottomInset(context);
            final productStream = _products.watchProducts();

            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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
                                icon: Icons.home_rounded,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.l10n.text('navHome'),
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
                                      DateFormat('EEEE, MMM d', locale)
                                          .format(DateTime.now()),
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
                              ListenableBuilder(
                                listenable: NotificationStore.instance,
                                builder: (context, _) {
                                  final unread =
                                      NotificationStore.instance.unreadCount;
                                  return SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        IconButton(
                                          tooltip: 'Notifications',
                                          onPressed: widget.onOpenNotif,
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                            width: 44,
                                            height: 44,
                                          ),
                                          splashRadius: 22,
                                          icon: Icon(
                                            Icons.notifications_outlined,
                                            color: scheme.onSurface,
                                            size: 23,
                                          ),
                                        ),
                                        if (unread > 0)
                                          Positioned(
                                            top: -2,
                                            right: -2,
                                            child: Container(
                                              constraints: const BoxConstraints(
                                                minWidth: 18,
                                                minHeight: 18,
                                              ),
                                              padding: const EdgeInsets.all(3),
                                              decoration: BoxDecoration(
                                                color: sari.danger,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: theme.scaffoldBackgroundColor,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Text(
                                                unread > 9 ? '9+' : '$unread',
                                                textAlign: TextAlign.center,
                                                style: GoogleFonts.outfit(
                                                  color: scheme.onError,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w700,
                                                  height: 1,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 12),
                              AppPageHeader.avatarAction(
                                context: context,
                                onTap: widget.onOpenProfile,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Search Bar
                      AppSearchBar(
                        controller: _searchController,
                        hintText: context.l10n.text('searchByNameOrBarcode'),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 14),

                      // Category Horizontal Chips
                      StreamBuilder<List<Product>>(
                        stream: productStream,
                        builder: (context, snapshot) {
                          final categories = _categoriesFor(
                            snapshot.data ?? const <Product>[],
                          );

                          final selectedCategory =
                              categories.contains(_selectedCategory)
                                  ? _selectedCategory
                                  : 'All';

                          return SizedBox(
                            height: 38,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: categories.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final category = categories[index];

                                return CategoryChip(
                                  label: context.l10n.category(category),
                                  selected: category == selectedCategory,
                                  onSelected: (_) => setState(
                                    () => _selectedCategory = category,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Products Section Header
                      SectionHeader(
                        title: context.l10n.text('products'),
                        actionLabel: context.l10n.text('seeAll'),
                        onAction: () {
                          setState(() {
                            _selectedCategory = 'All';
                            _searchController.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      // Product Grid View
                      Expanded(
                        child: StreamBuilder<List<Product>>(
                          stream: productStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return EmptyState(
                                icon: Icons.error_outline_rounded,
                                title: 'Failed to load products',
                                message: '${snapshot.error}',
                                actionLabel: context.l10n.text('tryAgain'),
                                onAction: _retryProducts,
                              );
                            }

                            if (!snapshot.hasData) {
                              return const LoadingIndicator();
                            }

                            final allProducts = _dedupe(snapshot.data!);
                            final q = _searchController.text.toLowerCase().trim();
                            final qCompact = q.replaceAll(RegExp(r'\s+'), '');

                            final filteredProducts = allProducts.where((product) {
                              final barcode = product.barcode.toLowerCase().trim();
                              final id = product.id.toLowerCase().trim();
                              final barcodeCompact =
                                  barcode.replaceAll(RegExp(r'\s+'), '');

                              final matchesSearch = q.isEmpty ||
                                  product.name.toLowerCase().contains(q) ||
                                  barcode.contains(q) ||
                                  barcodeCompact.contains(qCompact) ||
                                  id.contains(q) ||
                                  id.replaceAll(RegExp(r'\s+'), '') == qCompact ||
                                  product.category.toLowerCase().contains(q);

                              final matchesCategory = q.isNotEmpty ||
                                  _selectedCategory == 'All' ||
                                  _categoryMatches(
                                    product.category,
                                    _selectedCategory,
                                  );

                              return matchesSearch && matchesCategory;
                            }).toList();

                            if (qCompact.isNotEmpty) {
                              filteredProducts.sort((a, b) {
                                int score(Product p) {
                                  final code = p.barcode
                                      .toLowerCase()
                                      .replaceAll(RegExp(r'\s+'), '');
                                  final id = p.id
                                      .toLowerCase()
                                      .replaceAll(RegExp(r'\s+'), '');

                                  if (code == qCompact || id == qCompact) {
                                    return 0;
                                  }

                                  if (code.startsWith(qCompact) ||
                                      id.startsWith(qCompact)) {
                                    return 1;
                                  }

                                  return 2;
                                }

                                return score(a).compareTo(score(b));
                              });
                            }

                            if (allProducts.isEmpty) {
                              return EmptyState(
                                icon: Icons.inventory_2_outlined,
                                title: context.l10n.text('noProductsFound'),
                                message: 'Add products from Inventory or Scan',
                                actionLabel: context.l10n.text('tryAgain'),
                                onAction: _retryProducts,
                              );
                            }

                            if (filteredProducts.isEmpty) {
                              return EmptyState(
                                icon: Icons.inventory_2_outlined,
                                title: context.l10n.text('noProductsFound'),
                                message: 'Try searching for something else',
                              );
                            }

                            return GridView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.only(
                                bottom: navBottomInset +
                                    (_showCartPopup && cartItemCount > 0
                                        ? 96
                                        : 0),
                              ),
                              itemCount: filteredProducts.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: 0.66,
                              ),
                              itemBuilder: (context, index) {
                                final product = filteredProducts[index];

                                return ProductCard(
                                  product: product,
                                  onAddToCart: () => _addToCart(product),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Floating "Added to Cart" toast (shared with Scan).
                // Home SafeArea is bottom:false — clear the full floating nav.
                if (_showCartPopup &&
                    cartItemCount > 0 &&
                    (_lastAddedProductName?.isNotEmpty ?? false))
                  CartAddedPopup(
                    productName: _lastAddedProductName!,
                    quantity: _lastAddedQuantity,
                    onViewCart: _goToCart,
                    insideSafeArea: false,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}