import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/hydration_calculator.dart';
import '../../../database/database_provider.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../reminders/data/notification_service.dart';
import '../data/home_repository.dart';
import '../domain/drink_type_model.dart';
import '../domain/today_override.dart';
import '../domain/today_summary.dart';
import '../domain/water_log_model.dart';
import '../../onboarding/domain/user_profile_model.dart';

part 'home_provider.g.dart';

@riverpod
HomeRepository homeRepository(HomeRepositoryRef ref) => HomeRepository(
      ref.watch(waterLogsDaoProvider),
      ref.watch(userProfileDaoProvider),
      ref.watch(drinkTypesDaoProvider),
    );

@riverpod
Future<UserProfileModel?> userProfile(UserProfileRef ref) =>
    ref.watch(homeRepositoryProvider).getProfile();

@riverpod
Stream<List<DrinkTypeModel>> drinkTypes(DrinkTypesRef ref) =>
    ref.watch(homeRepositoryProvider).watchDrinkTypes();

@riverpod
Stream<double> todayTotalMl(TodayTotalMlRef ref) =>
    ref.watch(homeRepositoryProvider).watchTodayTotalMl();

final selectedDrinkTypeIdProvider = StateProvider<int?>((ref) => null);

final goalPreviouslyAchievedProvider = StateProvider<bool>((ref) => false);

final showCelebrationProvider = StateProvider<bool>((ref) => false);

@riverpod
Future<WaterLogModel?> lastLog(LastLogRef ref) =>
    ref.watch(homeRepositoryProvider).getLastLog();

// ── Today's override ─────────────────────────────────────────────────────────

@riverpod
class TodayOverrideNotifier extends _$TodayOverrideNotifier {
  static const _keyClimate = 'override_climate';
  static const _keyActivity = 'override_activity';
  static const _keyDate = 'override_date';

  @override
  TodayOverride? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';

    final savedDate = prefs.getString(_keyDate);
    if (savedDate != today) {
      if (savedDate != null) Future.microtask(_clearPrefs);
      return null;
    }

    final climateRaw = prefs.getString(_keyClimate);
    final activityRaw = prefs.getInt(_keyActivity);
    final climate =
        climateRaw != null ? ClimateType.fromRaw(climateRaw) : null;
    final activity =
        activityRaw != null ? ActivityLevel.fromRaw(activityRaw) : null;

    if (climate == null && activity == null) return null;
    return TodayOverride(climate: climate, activity: activity, date: today);
  }

  Future<void> setClimate(ClimateType climate) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final today = _todayString();
    await prefs.setString(_keyClimate, climate.rawValue);
    await prefs.setString(_keyDate, today);
    state = TodayOverride(
      climate: climate,
      activity: state?.activity,
      date: today,
    );
  }

  Future<void> setActivity(ActivityLevel activity) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final today = _todayString();
    await prefs.setInt(_keyActivity, activity.rawValue);
    await prefs.setString(_keyDate, today);
    state = TodayOverride(
      climate: state?.climate,
      activity: activity,
      date: today,
    );
  }

  Future<void> clearClimate() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_keyClimate);
    final current = state;
    if (current?.activity == null) {
      await prefs.remove(_keyDate);
      state = null;
    } else {
      state =
          TodayOverride(climate: null, activity: current!.activity, date: current.date);
    }
  }

  Future<void> clearActivity() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_keyActivity);
    final current = state;
    if (current?.climate == null) {
      await prefs.remove(_keyDate);
      state = null;
    } else {
      state =
          TodayOverride(climate: current!.climate, activity: null, date: current.date);
    }
  }

  Future<void> makePermanent() async {
    final override = state;
    if (override == null) return;
    final repo = ref.read(settingsRepositoryProvider);
    if (override.climate != null) {
      await repo.updateClimateType(override.climate!.rawValue);
    }
    if (override.activity != null) {
      await repo.updateActivityLevel(override.activity!.rawValue);
    }
    await _clearPrefs();
    state = null;
    ref.invalidate(userProfileProvider);
    ref.invalidate(settingsNotifierProvider);
  }

  Future<void> makeClimatePermanent(ClimateType climate) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.updateClimateType(climate.rawValue);
    await clearClimate();
    ref.invalidate(userProfileProvider);
    ref.invalidate(settingsNotifierProvider);
  }

  Future<void> makeActivityPermanent(ActivityLevel activity) async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.updateActivityLevel(activity.rawValue);
    await clearActivity();
    ref.invalidate(userProfileProvider);
    ref.invalidate(settingsNotifierProvider);
  }

  Future<void> _clearPrefs() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_keyClimate);
    await prefs.remove(_keyActivity);
    await prefs.remove(_keyDate);
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }
}

// ── Summary (reacts to override) ─────────────────────────────────────────────

@riverpod
Future<TodaySummary> todaySummary(TodaySummaryRef ref) async {
  final profile = await ref.watch(userProfileProvider.future);
  final totalMl = await ref.watch(todayTotalMlProvider.future);
  final override = ref.watch(todayOverrideNotifierProvider);

  final int goalMl;
  if (profile != null && override != null && override.hasAny) {
    goalMl = HydrationCalculator.calculateDailyGoalMl(
      weightKg: profile.weightKg,
      activityLevel: override.activity?.rawValue ?? profile.activityLevel,
      gender: profile.gender,
      isPregnant: profile.isPregnant,
      climateType: override.climate?.rawValue ?? profile.climateType,
    );
  } else {
    goalMl = profile?.dailyGoalMl ?? AppConstants.defaultDailyGoalMl;
  }

  return TodaySummary(totalMl: totalMl, goalMl: goalMl, logs: []);
}

// ── Actions ───────────────────────────────────────────────────────────────────

@riverpod
class HomeAction extends _$HomeAction {
  @override
  void build() {}

  Future<void> addQuickLog(double amountMl) async {
    final profile = await ref.read(userProfileProvider.future);
    final goalMl = profile?.dailyGoalMl ?? AppConstants.defaultDailyGoalMl;
    final currentTotal = await ref.read(todayTotalMlProvider.future);
    final wasAlreadyAchieved = ref.read(goalPreviouslyAchievedProvider);

    final drinkTypes = await ref.read(drinkTypesProvider.future);
    final selectedId = ref.read(selectedDrinkTypeIdProvider);
    final drinkType = selectedId != null
        ? drinkTypes.firstWhere(
            (d) => d.id == selectedId,
            orElse: () => drinkTypes.first,
          )
        : drinkTypes.first;
    await ref.read(homeRepositoryProvider).addLog(
          amountMl: amountMl,
          drinkTypeId: drinkType.id,
        );

    // amountMl is stored and summed as-is (no hydrationCoefficient applied
    // in storage), so the local total must match that to stay in sync with
    // the eventual stream value.
    final newTotal = currentTotal + amountMl;
    final goalJustCrossed = !wasAlreadyAchieved && newTotal >= goalMl;

    if (goalJustCrossed) {
      ref.read(goalPreviouslyAchievedProvider.notifier).state = true;
      ref.read(showCelebrationProvider.notifier).state = true;
      Future.delayed(const Duration(seconds: 3), () {
        ref.read(showCelebrationProvider.notifier).state = false;
      });
      _maybeRequestReview();
    }

    ref.invalidate(lastLogProvider);
    await ref.read(jumboTapAmountProvider.notifier).setAmount(amountMl.round());

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.prefLastCupSizeMl, amountMl.round());
    await prefs.setInt(AppConstants.prefLastDrinkTypeId, drinkType.id);
    await prefs.setInt(AppConstants.prefTodayGoalMl, goalMl);

    if (profile != null) {
      final soundEnabled =
          prefs.getBool(AppConstants.prefNotificationSound) ?? true;
      await NotificationService().scheduleReminders(
        wakeHour: profile.wakeHour,
        wakeMinute: profile.wakeMinute,
        sleepHour: profile.sleepHour,
        sleepMinute: profile.sleepMinute,
        intervalMinutes: profile.reminderIntervalMinutes,
        notificationsEnabled: profile.notificationsEnabled,
        soundEnabled: soundEnabled,
      );
    }
  }

  Future<void> _maybeRequestReview() async {
    final prefs = await SharedPreferences.getInstance();

    // Hard cap — bail immediately if limit already reached
    final promptCount = prefs.getInt('review_prompt_count') ?? 0;
    if (promptCount >= 2) return;

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final lastDate = prefs.getString('last_goal_hit_for_review');
    if (lastDate == todayStr) return;

    final count = (prefs.getInt('goal_hit_days_count') ?? 0) + 1;
    await prefs.setInt('goal_hit_days_count', count);
    await prefs.setString('last_goal_hit_for_review', todayStr);

    if (count >= 3) {
      await prefs.setInt('goal_hit_days_count', 0);
      await prefs.setInt('review_prompt_count', promptCount + 1);
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    }
  }

  Future<void> deleteLastLog() async {
    final lastLog = await ref.read(lastLogProvider.future);
    if (lastLog == null) return;

    final currentTotal = await ref.read(todayTotalMlProvider.future);
    final summary = await ref.read(todaySummaryProvider.future);
    final totalAfterUndo = currentTotal - lastLog.amountMl;

    await ref.read(homeRepositoryProvider).deleteLog(lastLog.id);
    ref.invalidate(lastLogProvider);

    if (totalAfterUndo < summary.goalMl) {
      ref.read(goalPreviouslyAchievedProvider.notifier).state = false;
    }
  }
}

@riverpod
class JumboTapAmount extends _$JumboTapAmount {
  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(AppConstants.prefLastCupSizeMl) ?? 250;
  }

  Future<void> setAmount(int ml) async {
    state = AsyncData(ml);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.prefLastCupSizeMl, ml);
  }
}

@riverpod
Future<String> appUnit(AppUnitRef ref) async {
  final profile = await ref.watch(userProfileProvider.future);
  return profile?.unit ?? AppConstants.unitMl;
}
