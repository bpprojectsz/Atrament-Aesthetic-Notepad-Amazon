import 'dart:async';

import 'package:flutter/services.dart';

/// Product metadata returned by the Amazon Appstore IAP SDK via the
/// native bridge. Mirrors a subset of the SDK's `Product` fields that
/// the paywall and provider consume.
class AmazonProductDetails {
  const AmazonProductDetails({
    required this.id,
    required this.price,
    this.title = '',
    this.description = '',
  });

  factory AmazonProductDetails.fromMap(Map<String, dynamic> m) {
    return AmazonProductDetails(
      id: (m['sku'] as String?) ?? '',
      price: (m['price'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
    );
  }

  final String id;
  final String price;
  final String title;
  final String description;
}

/// A single purchase or restore event emitted by the native handler.
/// `status` carries either a `PurchaseResponse.RequestStatus` name
/// (SUCCESSFUL, FAILED, ALREADY_PURCHASED, INVALID_SKU, etc.) or the
/// synthetic tag `RESTORED` for receipts replayed through
/// `getPurchaseUpdates`.
class AmazonPurchaseEvent {
  const AmazonPurchaseEvent({
    required this.status,
    required this.receiptId,
    required this.sku,
  });

  factory AmazonPurchaseEvent.fromMap(Map<String, dynamic> m) {
    return AmazonPurchaseEvent(
      status: (m['status'] as String?) ?? '',
      receiptId: (m['receiptId'] as String?) ?? '',
      sku: (m['sku'] as String?) ?? '',
    );
  }

  final String status;
  final String receiptId;
  final String sku;
}

/// Low-level bridge to the Amazon Appstore SDK IAP MethodChannel. The
/// app-level IAP logic lives in `core/services/iap_service.dart`; this
/// class only opens the channel, forwards commands, and exposes the
/// native event streams.
class AmazonIapService {
  AmazonIapService._internal();

  static final AmazonIapService instance = AmazonIapService._internal();

  static const MethodChannel _commands = MethodChannel('amazon_iap');
  static const MethodChannel _events = MethodChannel('amazon_iap_events');

  final _productsController =
      StreamController<List<AmazonProductDetails>>.broadcast();
  final _purchaseController = StreamController<AmazonPurchaseEvent>.broadcast();
  final _restoreController =
      StreamController<List<AmazonPurchaseEvent>>.broadcast();

  Stream<List<AmazonProductDetails>> get productEvents =>
      _productsController.stream;
  Stream<AmazonPurchaseEvent> get purchaseEvents => _purchaseController.stream;
  Stream<List<AmazonPurchaseEvent>> get restoreEvents =>
      _restoreController.stream;

  bool _initialized = false;

  /// Registers the Dart-side event handler and calls `initialize` on the
  /// native side, which is already registered from MainActivity. Safe to
  /// call multiple times.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    _events.setMethodCallHandler(_handleNativeEvent);

    try {
      await _commands.invokeMethod<void>('initialize');
    } catch (_) {
      // Native side missing (e.g. running unit tests on a host without
      // the Amazon SDK). IAP degrades to "no products available" and
      // the paywall hides the purchase button.
    }
  }

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    switch (call.method) {
      case 'onProductData':
        final raw = (call.arguments as List).cast<Map>();
        _productsController.add(
          raw
              .map((m) =>
                  AmazonProductDetails.fromMap(Map<String, dynamic>.from(m)))
              .toList(),
        );
        break;
      case 'onPurchaseResponse':
        final raw = Map<String, dynamic>.from(call.arguments as Map);
        _purchaseController.add(AmazonPurchaseEvent.fromMap(raw));
        break;
      case 'onPurchaseUpdatesResponse':
        final raw = (call.arguments as List).cast<Map>();
        _restoreController.add(
          raw
              .map((m) => AmazonPurchaseEvent.fromMap(Map<String, dynamic>.from(m)))
              .toList(),
        );
        break;
    }
    return null;
  }

  Future<void> getProductData(List<String> skus) =>
      _commands.invokeMethod<void>('getProductData', {'skus': skus});

  Future<void> getPurchaseUpdates({bool reset = false}) =>
      _commands.invokeMethod<void>('getPurchaseUpdates', {'reset': reset});

  Future<void> purchase(String sku) =>
      _commands.invokeMethod<void>('purchase', {'sku': sku});

  Future<void> notifyFulfillment(String receiptId, {required bool fulfilled}) =>
      _commands.invokeMethod<void>('notifyFulfillment', {
        'receiptId': receiptId,
        'result': fulfilled ? 'FULFILLED' : 'UNAVAILABLE',
      });
}
