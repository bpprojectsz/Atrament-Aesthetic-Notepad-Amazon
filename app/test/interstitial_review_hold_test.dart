import 'package:atrament/core/utils/constants.dart';
import 'package:atrament/platform/interstitial_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = InterstitialService.instance;
  final t0 = DateTime(2026, 11, 26, 12, 0);
  var clock = t0;
  var attempts = 0;

  Future<void> nineActions() async {
    for (var i = 0; i < InterstitialService.actionThreshold; i++) {
      await service.recordNoteSave();
    }
  }

  void setReview(Duration ago) {
    SharedPreferences.setMockInitialValues({
      AppConstants.prefLastReviewPrompt:
          t0.subtract(ago).millisecondsSinceEpoch,
    });
  }

  setUp(() {
    clock = t0;
    attempts = 0;
    service.resetCountersForTesting();
    service.clockForTesting = () => clock;
    service.showAttemptForTesting = () async {
      attempts++;
      return true;
    };
  });

  tearDown(service.resetCountersForTesting);

  test('the hold is seven minutes', () {
    expect(InterstitialService.reviewPromptHold, const Duration(minutes: 7));
  });

  test('a review prompt 3 minutes ago keeps the ad pending', () async {
    setReview(const Duration(minutes: 3));

    await nineActions();

    expect(attempts, 0);
    expect(service.isAdPending, isTrue);
  });

  test('just inside seven minutes is still held', () async {
    setReview(const Duration(minutes: 6, seconds: 59));

    await nineActions();

    expect(attempts, 0);
    expect(service.isAdPending, isTrue);
  });

  test('after seven minutes the pending ad shows on the next action', () async {
    setReview(const Duration(minutes: 3));
    await nineActions();
    expect(attempts, 0);

    clock = t0.add(const Duration(minutes: 5)); // 8 minutes after the prompt
    await service.recordNoteSave();

    expect(attempts, 1);
    expect(service.isAdPending, isFalse);
  });

  test('exactly seven minutes after the prompt is enough', () async {
    setReview(const Duration(minutes: 7));

    await nineActions();

    expect(attempts, 1);
  });

  test('no recorded review prompt never holds an ad', () async {
    SharedPreferences.setMockInitialValues({});

    await nineActions();

    expect(attempts, 1);
  });

  test('a review time in the future (clock moved back) does not block', () async {
    setReview(const Duration(minutes: -30));

    await nineActions();

    expect(attempts, 1);
  });
}
