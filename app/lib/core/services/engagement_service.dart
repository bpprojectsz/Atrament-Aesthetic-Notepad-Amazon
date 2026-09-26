import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/constants.dart';
import '../utils/error_handler.dart';

/// Owns engagement gating: the review prompt and the share-app prompt.
/// Every decision is a pure predicate over counters and timestamps
/// stored in SharedPreferences. Callers report events ("note saved",
/// "export completed"); the service decides whether a prompt is due.
///
/// Amazon fork differences from the main repo:
///   - `in_app_review` (Google Play Core) is unavailable on Fire OS.
///     Replaced with an Amazon Appstore deep link.
///   - iOS ATT is not applicable. The `app_tracking_transparency`
///     dependency and `_maybeRequestAtt` helper are removed.
///
/// Thresholds:
///   - Review: 20 successful note saves AND >= 5 days since install,
///     30-day cooldown between attempts.
///   - Share: 10 successful exports, 30-day cooldown.
class EngagementService {
  EngagementService._internal();

  static final EngagementService instance = EngagementService._internal();

  static const int _reviewMinSaves = 20;
  static const int _shareMinExports = 10;
  static const Duration _reviewMinAge = Duration(days: 5);
  static const Duration _reviewCooldown = Duration(days: 30);
  static const Duration _shareCooldown = Duration(days: 30);

  // Amazon Appstore deep link. Prefers the installed Amazon Shopping app;
  // the web URL is the fallback for tablets without it.
  static const String _amazonNativeUrl =
      'amzn://apps/android?p=com.zdmgold.atrament';
  static const String _amazonWebUrl =
      'https://www.amazon.com/gp/mas/dl/android?p=com.zdmgold.atrament';

  bool _installDateChecked = false;

  // -----------------------------------------------------------------
  // Install-date stamping — call once at startup.
  // -----------------------------------------------------------------
  Future<void> ensureInstallDate() async {
    if (_installDateChecked) return;
    _installDateChecked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(AppConstants.prefInstallDate)) {
        await prefs.setInt(
          AppConstants.prefInstallDate,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } catch (error, stackTrace) {
      ErrorHandler.report(
        error,
        stackTrace,
        message: 'Failed to stamp install date',
        context: 'engagement_service.ensureInstallDate',
        severity: ErrorSeverity.warning,
      );
    }
  }

  // -----------------------------------------------------------------
  // Event report + maybe prompt.
  // -----------------------------------------------------------------

  /// Call after a note save succeeds. Increments the save counter and
  /// fires the review prompt if the thresholds are met.
  Future<void> recordNoteSave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(AppConstants.prefNoteSaveCount) ?? 0) + 1;
      await prefs.setInt(AppConstants.prefNoteSaveCount, count);
      await _maybePromptReview(prefs, count);
    } catch (error, stackTrace) {
      ErrorHandler.report(
        error,
        stackTrace,
        message: 'Failed to record note save for engagement',
        context: 'engagement_service.recordNoteSave',
        severity: ErrorSeverity.warning,
      );
    }
  }

  /// Call after a successful export + share hand-off. Increments the
  /// export counter and fires the share-app prompt if the thresholds
  /// are met.
  Future<void> recordExport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(AppConstants.prefExportCount) ?? 0) + 1;
      await prefs.setInt(AppConstants.prefExportCount, count);
      await _maybePromptShare(prefs, count);
    } catch (error, stackTrace) {
      ErrorHandler.report(
        error,
        stackTrace,
        message: 'Failed to record export for engagement',
        context: 'engagement_service.recordExport',
        severity: ErrorSeverity.warning,
      );
    }
  }

  // -----------------------------------------------------------------
  // Predicates and firing.
  // -----------------------------------------------------------------

  Future<void> _maybePromptReview(SharedPreferences prefs, int count) async {
    if (count < _reviewMinSaves) return;

    final installMs = prefs.getInt(AppConstants.prefInstallDate) ?? 0;
    if (installMs == 0) return;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(installMs),
    );
    if (age < _reviewMinAge) return;

    final lastMs = prefs.getInt(AppConstants.prefLastReviewPrompt) ?? 0;
    if (lastMs != 0) {
      final sinceLast = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(lastMs),
      );
      if (sinceLast < _reviewCooldown) return;
    }

    await _openAmazonStoreListing();
    await prefs.setInt(
      AppConstants.prefLastReviewPrompt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _maybePromptShare(SharedPreferences prefs, int count) async {
    if (count < _shareMinExports) return;

    final lastMs = prefs.getInt(AppConstants.prefLastSharePrompt) ?? 0;
    if (lastMs != 0) {
      final sinceLast = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(lastMs),
      );
      if (sinceLast < _shareCooldown) return;
    }

    // The share sheet itself is triggered from Settings via the
    // "Share Atrament" ListTile. This hook only records that the
    // threshold was crossed; the UI layer decides whether to surface
    // a contextual card. No system dialog here.
    await prefs.setInt(
      AppConstants.prefLastSharePrompt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Opens the Atrament listing in the Amazon Appstore, preferring the
  /// installed Amazon Shopping app via the amzn:// deep link and
  /// falling back to the web URL if no handler is registered.
  Future<void> _openAmazonStoreListing() async {
    try {
      final nativeUri = Uri.parse(_amazonNativeUrl);
      if (await canLaunchUrl(nativeUri)) {
        await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // Fall through to the web URL.
    }
    try {
      await launchUrl(
        Uri.parse(_amazonWebUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (error, stackTrace) {
      ErrorHandler.report(
        error,
        stackTrace,
        message: 'Failed to open Amazon store listing',
        context: 'engagement_service.openAmazonStoreListing',
        severity: ErrorSeverity.warning,
      );
    }
  }

  // -----------------------------------------------------------------
  // Explicit user-initiated paths (Settings rows).
  // -----------------------------------------------------------------

  /// Called by the "Rate Atrament" row in Settings. Bypasses thresholds.
  Future<void> openStoreListingForReview() => _openAmazonStoreListing();
}
