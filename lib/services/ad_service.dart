import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MASTER SWITCH FOR ALL ADS.
/// false = the app contains no ad activity at all.
const bool kAdsEnabled = true;

/// TEST MODE SWITCH.
/// true  = Google's official test ads (safe: use this on your own phone).
/// false = your REAL AdMob ads. Set to false ONLY for the build you upload to
///         Google Play, and never tap real ads on your own phone.
const bool kUseTestAds = true;

/// Optional: your phone's test-device ID(s), so even real ads show as test
/// ads on your own phone. Find it in the log: "Use RequestConfiguration...
/// setTestDeviceIds(Arrays.asList("XXXX"))" and paste the code between quotes.
const List<String> kTestDeviceIds = <String>[];

/// Your AdMob account IDs.
const String kRealBannerId = 'ca-app-pub-3240880973551531/6922214068';
const String kRealNativeId = 'ca-app-pub-3240880973551531/8309563338';
const String kRealRewardedId = 'ca-app-pub-3240880973551531/1474446265';
const String kRealInterstitialId = 'ca-app-pub-3240880973551531/4390499625';

/// Ad unit IDs. Test IDs are Google's official sample IDs.
class AdIds {
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  static String get banner => kUseTestAds
      ? (_ios
          ? 'ca-app-pub-3940256099942544/2934735716'
          : 'ca-app-pub-3940256099942544/6300978111')
      : kRealBannerId;

  static String get native => kUseTestAds
      ? (_ios
          ? 'ca-app-pub-3940256099942544/3986624511'
          : 'ca-app-pub-3940256099942544/2247696110')
      : kRealNativeId;

  static String get rewarded => kUseTestAds
      ? (_ios
          ? 'ca-app-pub-3940256099942544/1712485313'
          : 'ca-app-pub-3940256099942544/5224354917')
      : kRealRewardedId;

  static String get interstitial => kUseTestAds
      ? (_ios
          ? 'ca-app-pub-3940256099942544/4411468910'
          : 'ca-app-pub-3940256099942544/1033173712')
      : kRealInterstitialId;
}

class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static bool get supported =>
      kAdsEnabled &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final Completer<void> _ready = Completer<void>();

  /// Completes once the ads SDK has finished starting up.
  Future<void> get ready => _ready.future;

  bool _started = false;
  final DateTime _startedAt = DateTime.now();

  // ------------------------------------------------ ad-free reward (opt-in)
  static const Duration adFreeReward = Duration(hours: 1);
  static const String _kAdFree = 'adfree_until';

  /// true while the user has earned an ad-free period.
  final ValueNotifier<bool> adFree = ValueNotifier<bool>(false);
  DateTime? _adFreeUntil;
  Timer? _adFreeTimer;

  Duration get adFreeLeft {
    final u = _adFreeUntil;
    if (u == null) return Duration.zero;
    final d = u.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Future<void> _loadAdFree() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ms = p.getInt(_kAdFree);
      if (ms != null) {
        _setAdFree(DateTime.fromMillisecondsSinceEpoch(ms), save: false);
      }
    } catch (_) {}
  }

  Future<void> _saveAdFree(DateTime until) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kAdFree, until.millisecondsSinceEpoch);
    } catch (_) {}
  }

  void _setAdFree(DateTime until, {bool save = true}) {
    _adFreeTimer?.cancel();
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) {
      _adFreeUntil = null;
      adFree.value = false;
      return;
    }
    _adFreeUntil = until;
    adFree.value = true;
    _adFreeTimer = Timer(left, () {
      _adFreeUntil = null;
      adFree.value = false;
    });
    if (save) _saveAdFree(until);
  }

  void grantAdFree() {
    final now = DateTime.now();
    final current = _adFreeUntil;
    final base = (current != null && current.isAfter(now)) ? current : now;
    _setAdFree(base.add(adFreeReward));
  }

  /// The user chooses to watch a video; in return the banner and list ads
  /// are hidden for [adFreeReward].
  void watchForAdFree({
    required VoidCallback onGranted,
    required VoidCallback onUnavailable,
  }) {
    showRewarded(
      onReward: () {
        grantAdFree();
        onGranted();
      },
      onUnavailable: onUnavailable,
    );
  }

  // ------------------------------------------------------------ start up
  /// Called once, after the first screen is showing. Never throws.
  Future<void> init() async {
    if (!supported || _started) return;
    _started = true;
    await _loadAdFree();
    // Users in Europe / the UK see Google's consent message first.
    await _gatherConsent();
    if (!await _canRequestAds()) {
      debugPrint('Ads are off for this session: no consent yet.');
      return;
    }
    try {
      if (kTestDeviceIds.isNotEmpty) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: kTestDeviceIds),
        );
      }
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('Ads failed to initialise: $e');
    }
    if (!_ready.isCompleted) _ready.complete();
    loadRewarded();
    loadInterstitial();
  }

  // ------------------------------------------------------------- consent
  Future<void> _gatherConsent() async {
    final done = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          try {
            ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
              if (error != null) debugPrint('Consent form: ${error.message}');
              if (!done.isCompleted) done.complete();
            });
          } catch (e) {
            if (!done.isCompleted) done.complete();
          }
        },
        (FormError error) {
          debugPrint('Consent info: ${error.message}');
          if (!done.isCompleted) done.complete();
        },
      );
    } catch (e) {
      if (!done.isCompleted) done.complete();
    }
    await done.future.timeout(const Duration(minutes: 3), onTimeout: () {});
  }

  Future<bool> _canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('canRequestAds failed: $e');
      return false;
    }
  }

  /// true when the user must be offered a way to change their ad choices.
  Future<bool> privacyOptionsRequired() async {
    try {
      final status =
          await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  void showPrivacyOptions() {
    try {
      ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (error != null) debugPrint('Privacy options: ${error.message}');
      });
    } catch (_) {}
  }

  // ------------------------------------------------------------ rewarded
  RewardedAd? _rewarded;
  bool _loading = false;

  void loadRewarded() {
    if (!supported || !_ready.isCompleted || _loading || _rewarded != null) {
      return;
    }
    _loading = true;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          debugPrint('Rewarded failed: $error');
        },
      ),
    );
  }

  /// [onReward] runs only after the user watched the ad and closed it.
  /// [onUnavailable] runs if no ad is ready or it failed to show.
  void showRewarded({
    required VoidCallback onReward,
    required VoidCallback onUnavailable,
  }) {
    final ad = _rewarded;
    if (ad == null) {
      loadRewarded();
      onUnavailable();
      return;
    }
    _rewarded = null;
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        loadRewarded();
        if (earned) onReward();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        loadRewarded();
        onUnavailable();
      },
    );
    ad.show(onUserEarnedReward: (a, reward) => earned = true);
  }

  // -------------------------------------------------------- interstitial
  // Full-screen ads are the most annoying kind, so they are strictly limited:
  //  - never in the first 2 minutes of a session,
  //  - only after the user has finished 4 things (e.g. viewed 4 formulas),
  //  - at most once every 5 minutes,
  //  - never while ad-free is active.
  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;
  int _actions = 0;
  DateTime? _lastInterstitial;

  void loadInterstitial() {
    if (!supported ||
        !_ready.isCompleted ||
        _loadingInterstitial ||
        _interstitial != null) {
      return;
    }
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loadingInterstitial = false;
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          debugPrint('Interstitial failed: $error');
        },
      ),
    );
  }

  /// Call at a natural break (the user just finished something).
  void maybeShowInterstitial() {
    if (!supported || adFree.value) return;
    _actions++;
    if (_actions < 4) return;
    final now = DateTime.now();
    if (now.difference(_startedAt) < const Duration(minutes: 2)) return;
    final last = _lastInterstitial;
    if (last != null && now.difference(last) < const Duration(minutes: 5)) {
      return;
    }
    final ad = _interstitial;
    if (ad == null) {
      loadInterstitial();
      return;
    }
    _interstitial = null;
    _actions = 0;
    _lastInterstitial = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        loadInterstitial();
      },
    );
    ad.show();
  }
}
