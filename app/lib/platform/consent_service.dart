import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/utils/error_handler.dart';

/// Wraps Google's User Messaging Platform (UMP) SDK, bundled inside
/// `google_mobile_ads`. Owns the consent state; `AdMobService` and the
/// Settings screen query this class rather than touching the UMP SDK
/// directly.
///
/// Required by Google's EU User Consent Policy for users in the EEA,
/// the UK, and Switzerland. Outside those regions the UMP SDK reports
/// that no form is required, and [canRequestAds] returns true on the
/// first check without any UI.
class ConsentService {
  ConsentService._internal();

  static final ConsentService instance = ConsentService._internal();

  bool _initialized = false;

  /// Flips to true once the UMP SDK confirms ads may be requested for
  /// the current session. `AdMobService` gates initialization on this.
  final ValueNotifier<bool> canRequestAds = ValueNotifier(false);

  /// True when the UMP SDK reports a publisher-rendered privacy options
  /// entry point is required (typically only in regulated regions).
  /// The Settings screen shows or hides its privacy-options row on this.
  final ValueNotifier<bool> privacyOptionsRequired = ValueNotifier(false);

  bool get isInitialized => _initialized;

  /// Runs the full consent flow:
  ///   1. requestConsentInfoUpdate on every app launch
  ///   2. loadAndShowConsentFormIfRequired when the SDK says a form is due
  ///   3. refresh [canRequestAds] and [privacyOptionsRequired]
  ///
  /// Safe to call once at startup. Returns after the consent decision
  /// for the current session is known. If the update fails (offline,
  /// transient network), the SDK falls back to the previous session's
  /// consent state — a returning user who already consented keeps ads.
  Future<void> initialize({ConsentDebugSettings? debugSettings}) async {
    if (_initialized) return;
    _initialized = true;

    final params = ConsentRequestParameters(
      consentDebugSettings: debugSettings,
    );

    final completer = Completer<void>();

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () {
          ConsentForm.loadAndShowConsentFormIfRequired((formError) {
            if (formError != null) {
              ErrorHandler.report(
                Exception(formError.message),
                StackTrace.current,
                message: 'Consent form failed to show',
                context: 'consent_service.loadAndShowConsentForm',
                severity: ErrorSeverity.warning,
              );
            }
            unawaited(_completeRefresh(completer));
          });
        },
        (formError) {
          // Network or config error. Fall through to the cached state.
          ErrorHandler.report(
            Exception(formError.message),
            StackTrace.current,
            message: 'Consent info update failed',
            context: 'consent_service.requestConsentInfoUpdate',
            severity: ErrorSeverity.warning,
          );
          unawaited(_completeRefresh(completer));
        },
      );
    } catch (error, stackTrace) {
      ErrorHandler.report(
        error,
        stackTrace,
        message: 'Consent info request threw',
        context: 'consent_service.initialize',
        severity: ErrorSeverity.warning,
      );
      unawaited(_completeRefresh(completer));
    }

    await completer.future;
  }

  Future<void> _completeRefresh(Completer<void> completer) async {
    await _refreshState();
    if (!completer.isCompleted) completer.complete();
  }

  Future<void> _refreshState() async {
    try {
      canRequestAds.value = await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      // Leave previous value in place.
    }
    try {
      final status =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      privacyOptionsRequired.value =
          status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      privacyOptionsRequired.value = false;
    }
  }

  /// Shows the Google-rendered privacy options form. Safe to call
  /// unconditionally — the UMP SDK no-ops when no entry point is
  /// required for the current user.
  Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((formError) {
        if (formError != null) {
          ErrorHandler.report(
            Exception(formError.message),
            StackTrace.current,
            message: 'Privacy options form failed',
            context: 'consent_service.showPrivacyOptions',
            severity: ErrorSeverity.warning,
          );
        }
      });
    } catch (error, stackTrace) {
      ErrorHandler.report(
        error,
        stackTrace,
        message: 'Privacy options form threw',
        context: 'consent_service.showPrivacyOptions',
        severity: ErrorSeverity.warning,
      );
    }
  }

  /// Test-only: resets the UMP SDK to simulate a fresh install.
  @visibleForTesting
  Future<void> reset() => ConsentInformation.instance.reset();
}
