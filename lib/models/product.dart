
class Product {
  static const int lowStockThreshold = 10;

  // ==========================================
  // PRODUCT INFORMATION
  // ==========================================

  final String id;
  final String name;
  final String size;
  final String category;
  final String sku;

  // ==========================================
  // PRICE AND INVENTORY
  // ==========================================

  final double price;
  final int stock;

  // ==========================================
  // PRODUCT IMAGE AND BARCODE
  // ==========================================

  final String imageUrl;
  final String barcode;

  // ==========================================
  // PRODUCT STATUS
  // ==========================================

  final bool hidden;
  final bool isCatalogOnly;

  // ID of the original catalog product.
  final String catalogProductId;

  // ==========================================
  // CONSTRUCTOR
  // ==========================================

  Product({
    required this.id,
    required this.name,
    this.size = '',
    required this.category,
    required this.sku,
    required this.price,
    required this.stock,
    required this.imageUrl,
    required this.barcode,
    this.hidden = false,
    this.isCatalogOnly = false,
    this.catalogProductId = '',
  });

  // ==========================================
  // STOCK STATUS
  // ==========================================

  bool get isLowStock => stock > 0 && stock <= lowStockThreshold;

  bool get isOutOfStock => stock == 0;

  bool get isCustom =>
      !isCatalogOnly && catalogProductId.isEmpty;

  // ==========================================
  // PRODUCT KEY
  // ==========================================

  // Prefer barcode when available.
  // Otherwise, use the Firestore document ID.
  String get key => barcode.isNotEmpty ? barcode : id;

  // ==========================================
  // CONVERT PRODUCT TO FIRESTORE MAP
  // ==========================================

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'size': size.trim(),
      'category': category.trim(),
      'sku': sku.trim(),
      'price': price,
      'stock': stock,
      'imageUrl': imageUrl.trim(),
      'barcode': barcode.trim(),
      'hidden': hidden,
      'catalogProductId': catalogProductId,
    };
  }

  // ==========================================
  // CREATE PRODUCT FROM FIRESTORE MAP
  // ==========================================

  factory Product.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool isCatalogOnly = false,
  }) {
    // Read product name.
    // Supports both name and productName.
    final name = _firstNonEmpty([
      map['name'],
      map['productName'],
    ]);

    // Read image.
    // Supports imageUrl and image.
    final imageUrl = _firstNonEmpty([
      map['imageUrl'],
      map['image'],
      map['photoUrl'],
    ]);

    // Read barcode.
    final barcode = _asString(map['barcode']).trim();

    // Read catalog reference.
    final catalogId =
        _asString(map['catalogProductId']).trim();

    // Read category.
    final category = _firstNonEmpty([
      map['category'],
      map['productCategory'],
    ]);

    return Product(
      id: id,
      name: name,
      size: _asString(map['size']),
      category: category,
      sku: _asString(map['sku']),
      price: _asDouble(map['price']),
      stock: _asInt(map['stock']),
      imageUrl: imageUrl,
      barcode: barcode,
      hidden: map['hidden'] == true,
      isCatalogOnly: isCatalogOnly,
      catalogProductId: catalogId,
    );
  }

  // ==========================================
  // CREATE PRODUCT FROM FIRESTORE DOCUMENT
  // ==========================================

  factory Product.fromFirestore(
    String docId,
    Map<String, dynamic>? data, {
    bool isCatalogOnly = false,
  }) {
    return Product.fromMap(
      docId,
      data ?? const <String, dynamic>{},
      isCatalogOnly: isCatalogOnly,
    );
  }

  // ==========================================
  // COPY PRODUCT WITH UPDATED VALUES
  // ==========================================

  Product copyWith({
    String? id,
    String? name,
    String? size,
    String? category,
    String? sku,
    double? price,
    int? stock,
    String? imageUrl,
    String? barcode,
    bool? hidden,
    bool? isCatalogOnly,
    String? catalogProductId,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      size: size ?? this.size,
      category: category ?? this.category,
      sku: sku ?? this.sku,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      imageUrl: imageUrl ?? this.imageUrl,
      barcode: barcode ?? this.barcode,
      hidden: hidden ?? this.hidden,
      isCatalogOnly:
          isCatalogOnly ?? this.isCatalogOnly,
      catalogProductId:
          catalogProductId ?? this.catalogProductId,
    );
  }

  // ==========================================
  // UPDATE BARCODE
  // ==========================================

  Product copyWithBarcode(String newBarcode) {
    final code = newBarcode.trim();

    return copyWith(
      id: code.isNotEmpty ? code : id,
      barcode: code.isNotEmpty ? code : barcode,
    );
  }

  // ==========================================
  // MERGE CATALOG PRODUCT WITH USER INVENTORY
  // ==========================================

  // The catalog is the source of the official product name,
  // category and base product information.
  //
  // User inventory provides store-specific price and stock.
  //
  // This helps prevent different product names between
  // SARI Web and SARI Mobile for linked catalog products.

  static Product mergeCatalogWithUser(
    Product catalog,
    Product user,
  ) {
    return Product(
      id: user.id.isNotEmpty ? user.id : catalog.id,

      // Use catalog name for linked products.
      // Custom products retain their own names.
      name: catalog.name.trim().isNotEmpty
          ? catalog.name
          : user.name,

      // Prefer user's size when available.
      size: user.size.isNotEmpty
          ? user.size
          : catalog.size,

      // Keep catalog category consistent.
      category: catalog.category.isNotEmpty
          ? catalog.category
          : user.category,

      sku: user.sku.isNotEmpty
          ? user.sku
          : catalog.sku,

      // Store-specific price.
      price: user.price,

      // Store-specific inventory stock.
      stock: user.stock,

      // Prefer the user's uploaded image.
      imageUrl: user.imageUrl.isNotEmpty
          ? user.imageUrl
          : catalog.imageUrl,

      barcode: user.barcode.isNotEmpty
          ? user.barcode
          : catalog.barcode,

      hidden: user.hidden,

      isCatalogOnly: false,

      catalogProductId:
          user.catalogProductId.isNotEmpty
              ? user.catalogProductId
              : catalog.id,
    );
  }

  // ==========================================
  // HELPER: GET FIRST NON-EMPTY VALUE
  // ==========================================

  static String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = _asString(value).trim();

      if (text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  // ==========================================
  // HELPER: CONVERT TO STRING
  // ==========================================

  static String _asString(dynamic value) {
    if (value == null) return '';

    return value.toString().trim();
  }

  // ==========================================
  // HELPER: CONVERT TO DOUBLE
  // ==========================================

  static double _asDouble(dynamic value) {
    if (value == null) return 0;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value.toString().trim(),
        ) ??
        0;
  }

  // ==========================================
  // HELPER: CONVERT TO INTEGER
  // ==========================================

  static int _asInt(dynamic value) {
    if (value == null) return 0;

    if (value is int) return value;

    if (value is num) {
      return value.round();
    }

    final text = value.toString().trim();

    return int.tryParse(text) ??
        double.tryParse(text)?.round() ??
        0;
  }
}
