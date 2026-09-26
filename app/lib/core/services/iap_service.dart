import 'dart:async';

import '../../platform/amazon_iap_service.dart';
import '../utils/constants.dart';
import '../utils/error_handler.dart';

/// Current subscription state, emitted to `subscription_provider.dart`.
enum SubscriptionStatus {
  /// Purchase state not yet determined (still querying at startup).
  unknown,

  /// No active ad-removal entitlement — banner ads show.
  free,

  /// Active ad-removal entitlement — banner ads hidden.
  pro,
}

/// Result of a purchase or restore attempt, for explicit UI feedback.
class PurchaseAttemptResult {
  const PurchaseAttemptResult.success()
    : errorMessage = null,
      cancelled = false;
  const PurchaseAttemptResult.failure(this.errorMessage) : cancelled = false;
  const PurchaseAttemptResult.cancelled()
    : errorMessage = null,
      cancelled = true;

  final String? errorMessage;
  final bool cancelled;

  bool get succeeded => errorMessage == null && !cancelled;
}

/// Wraps the Amazon Appstore SDK IAP bridge for the single one-time
/// ad-removal entitlement. This is the only file that touches
/// [AmazonIapService]; `subscription_provider.dart` listens to
/// [statusStream] rather than the platform channel directly.
class IapService {
  IapService._internal();

  static final IapService instance = IapService._internal();

  final AmazonIapService _amazon = AmazonIapService.instance;

  StreamSubscription<List<AmazonProductDetails>>? _productSub;
  StreamSubscription<AmazonPurchaseEvent>? _purchaseSub;
  StreamSubscription<List<AmazonPurchaseEvent>>? _restoreSub;

  final StreamController<SubscriptionStatus> _statusController =
      StreamController<SubscriptionStatus>.broadcast();

  /// Emits whenever subscription status changes — provider subscribes to
  /// this to update ad visibility reactively.
  Stream<SubscriptionStatus> get statusStream => _statusController.stream;

  SubscriptionStatus _lastKnownStatus = SubscriptionStatus.unknown;
  SubscriptionStatus get lastKnownStatus => _lastKnownStatus;

  List<AmazonProductDetails> _products = const [];
  List<AmazonProductDetails> get products => _products;

  bool _initialized = false;

  /// Opens the Amazon bridge and starts listening for product, purchase,
  /// and restore events. Safe to call multiple times.
  ///
  /// When the PEM file is absent (before the first Amazon submission),
  /// getProductData returns an empty product list, `_products` stays
  /// empty, and the paywall hides the purchase button. Once the PEM is
  /// dropped in, this same code path returns the SKU and the button
  /// becomes active — no code change required.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _amazon.initialize();

      _productSub = _amazon.productEvents.listen((products) {
        _products = products;
      });

      _purchaseSub = _amazon.purchaseEvents.listen(_handlePurchaseEvent);

      _restoreSub = _amazon.restoreEvents.listen(_handleRestoreEvents);

      await _amazon.getProductData(const [AppConstants.iapAdFreeProductId]);
      await _amazon.getPurchaseUpdates(reset: true);
    } catch (error, stackTrace) {
      ErrorHandler.report(
        error,
        stackTrace,
        message: 'Failed to initialize Amazon in-app purchases',
        context: 'iap_service.initialize',
        severity: ErrorSeverity.warning,
      );
      // Degrade gracefully: treat as free tier rather than blocking.
      _emitStatus(SubscriptionStatus.free);
    }
  }

  Future<PurchaseAttemptResult> purchase(String productId) async {
    final product = _products.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      return const PurchaseAttemptResult.failure(
        'This product is not available right now. Please try again later.',
      );
    }

    try {
      await _amazon.purchase(productId);
      // Actual success/failure arrives asynchronously through the event
      // stream; this return only confirms the flow was launched.
      return const PurchaseAttemptResult.success();
    } catch (error, stackTrace) {
      ErrorHandler.report(
        error,
        stackTrace,
        message: 'Purchase attempt threw',
        context: 'iap_service.purchase',
        severity: ErrorSeverity.warning,
      );
      return const PurchaseAttemptResult.failure(
        'Something went wrong starting the purchase.',
      );
    }
  }

  Future<PurchaseAttemptResult> restorePurchases() async {
    try {
      await _amazon.getPurchaseUpdates(reset: true);
      return const PurchaseAttemptResult.success();
    } catch (error, stackTrace) {
      ErrorHandler.report(
        error,
        stackTrace,
        message: 'Restore purchases failed',
        context: 'iap_service.restorePurchases',
        severity: ErrorSeverity.warning,
      );
      return const PurchaseAttemptResult.failure(
        'Could not restore purchases. Please check your connection and try again.',
      );
    }
  }

  Future<void> _handlePurchaseEvent(AmazonPurchaseEvent event) async {
    // FULFILLED acknowledges the purchase so the Appstore stops replaying
    // it. ALREADY_PURCHASED means the user already owns the item; we
    // surface pro without re-notifying fulfillment.
    if (event.status == 'SUCCESSFUL' && event.receiptId.isNotEmpty) {
      await _amazon.notifyFulfillment(event.receiptId, fulfilled: true);
      _emitStatus(SubscriptionStatus.pro);
      return;
    }
    if (event.status == 'ALREADY_PURCHASED') {
      _emitStatus(SubscriptionStatus.pro);
      return;
    }
    // Any other status leaves the user on the free tier.
    _emitStatus(SubscriptionStatus.free);
  }

  Future<void> _handleRestoreEvents(List<AmazonPurchaseEvent> events) async {
    final hasEntitlement =
        events.any((e) => e.sku == AppConstants.iapAdFreeProductId);
    if (hasEntitlement) {
      _emitStatus(SubscriptionStatus.pro);
    }
    // No entitlement found: keep current status rather than forcibly
    // downgrading. The user may still be in the middle of a purchase.
  }

  void _emitStatus(SubscriptionStatus status) {
    _lastKnownStatus = status;
    _statusController.add(status);
  }

  void dispose() {
    _productSub?.cancel();
    _purchaseSub?.cancel();
    _restoreSub?.cancel();
    _statusController.close();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
