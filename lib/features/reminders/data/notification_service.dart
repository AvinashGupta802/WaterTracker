import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/constants/app_constants.dart';
import '../../../database/app_database.dart';

// Fires when a notification is tapped while the app is fully terminated.
// Must be a top-level function since the plugin invokes it in a background
// isolate when notification actions are selected.
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse details) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().handleNotificationResponse(details);
}

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();
  factory NotificationService() => instance;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _soundChannelId = 'water_reminders_v2';
  static const String _silentChannelId = 'water_reminders_silent';
  static const String _quickAdd250ActionId = 'add_250_ml';
  static const String _pendingQuickAddCountKey =
      'pending_notification_add_250_count';
  static const String _pendingQuickAddAmountsKey =
      'pending_notification_add_amounts';
  static const String _scheduleAnchorDateKey = 'reminder_schedule_anchor_date';
  static const String _scheduleAnchorMillisKey =
      'reminder_schedule_anchor_millis';
  static const double _quickAddAmountMl = 250;

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );
    const iosSettings = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _soundChannelId,
        'Water Reminders',
        description: 'Hydration reminders throughout the day',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('water_pour'),
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _silentChannelId,
        'Water Reminders (Silent)',
        description: 'Silent hydration reminders',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );
  }

  Future<void> handleNotificationResponse(NotificationResponse details) async {
    if (details.actionId == _quickAdd250ActionId) {
      final amountMl =
          double.tryParse(details.payload ?? '') ?? _quickAddAmountMl;
      await _queueQuickIntakeFromNotification(amountMl);
      return;
    }

    await dismissActiveNotifications();
  }

  Future<void> showTestReminderNow({required bool soundEnabled}) async {
    await _ensureLocalTimezone();
    await initialize();

    final progress = await _loadTodayProgress();
    final quickAddAmountMl = _suggestedAmountMl(progress.remainingMl, 1);
    await _plugin.show(
      90,
      progress.title,
      progress.reminderBody(quickAddAmountMl),
      _buildNotificationDetails(
        soundEnabled: soundEnabled,
        progressPercent: progress.percent,
        quickAddAmountMl: quickAddAmountMl,
      ),
      payload: quickAddAmountMl.toString(),
    );
  }

  Future<bool> requestPermissions() async {
    final status = await Permission.notification.status;
    if (status.isDenied) {
      final result = await Permission.notification.request();
      return result.isGranted;
    }
    return status.isGranted;
  }

  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }

  Future<void> startTodayScheduleFromNow() async {
    await _ensureLocalTimezone();
    final now = tz.TZDateTime.now(tz.local);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scheduleAnchorDateKey, _dateKey(now));
    await prefs.setInt(
      _scheduleAnchorMillisKey,
      now.toLocal().millisecondsSinceEpoch,
    );
  }

  /// Dismisses only the notifications currently visible in the shade.
  /// getActiveNotifications() returns just what's visible right now, not the
  /// future scheduled alarms, so cancelling by id here leaves recurring
  /// AlarmManager entries intact.
  Future<void> dismissActiveNotifications() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    final active = await android.getActiveNotifications();
    for (final notification in active) {
      if (notification.id != null) {
        await _plugin.cancel(notification.id!);
      }
    }
  }

  Future<bool> isExactAlarmPermissionGranted() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await androidPlugin?.canScheduleExactNotifications() ?? false;
  }

  Future<ReminderPreview> getReminderPreview({
    required int wakeHour,
    required int wakeMinute,
    required int sleepHour,
    required int sleepMinute,
    required int intervalMinutes,
    required bool notificationsEnabled,
  }) async {
    try {
      await _ensureLocalTimezone();
      if (!notificationsEnabled || intervalMinutes == 0) {
        return const ReminderPreview.none();
      }

      final progress = await _loadTodayProgress();
      final now = tz.TZDateTime.now(tz.local);
      final days = await _buildScheduleDays(
        now: now,
        wakeHour: wakeHour,
        wakeMinute: wakeMinute,
        sleepHour: sleepHour,
        sleepMinute: sleepMinute,
        intervalMinutes: intervalMinutes,
      );
      final slots = days.expand((day) => day.slots).toList();
      if (slots.isEmpty) return const ReminderPreview.none();

      final todayKey = _dateKey(now);
      final tomorrowKey = _dateKey(now.add(const Duration(days: 1)));
      final todaySlots = slots
          .where((slot) => _dateKey(slot.time) == todayKey)
          .map((slot) => slot.time)
          .toList();
      final tomorrowSlots = slots
          .where((slot) => _dateKey(slot.time) == tomorrowKey)
          .map((slot) => slot.time)
          .toList();
      final isNextReminderToday = todaySlots.isNotEmpty;
      final suggestionSlots = isNextReminderToday
          ? todaySlots.length
          : tomorrowSlots.isNotEmpty
          ? tomorrowSlots.length
          : slots.length;
      final previewProgress = isNextReminderToday
          ? progress
          : _TodayProgress(totalMl: 0, goalMl: progress.goalMl);

      return ReminderPreview(
        nextReminderAt: slots.first.time,
        suggestedAmountMl: _suggestedAmountMl(
          previewProgress.remainingMl,
          suggestionSlots,
        ),
        remainingReminderSlots: suggestionSlots,
        targetComplete: previewProgress.percent >= 100,
        todayReminderTimes: todaySlots,
        tomorrowReminderTimes: tomorrowSlots,
      );
    } catch (e) {
      debugPrint('Failed to preview next reminder: $e');
      return const ReminderPreview.none();
    }
  }

  /// Cancels all pending reminders, then schedules today from the saved anchor
  /// and tomorrow from wake time. Each regular reminder gets one 5-minute
  /// follow-up. Any intake cancels and rebuilds this schedule.
  Future<void> scheduleReminders({
    required int wakeHour,
    required int wakeMinute,
    required int sleepHour,
    required int sleepMinute,
    required int intervalMinutes,
    required bool notificationsEnabled,
    required bool soundEnabled,
  }) async {
    var notificationId = 100;
    try {
      await _ensureLocalTimezone();

      await _plugin.cancelAll();
      if (!notificationsEnabled || intervalMinutes == 0) return;

      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final canScheduleExact =
          await androidPlugin?.canScheduleExactNotifications() ?? false;
      final scheduleMode = canScheduleExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexact;

      final progress = await _loadTodayProgress();
      final now = tz.TZDateTime.now(tz.local);
      final days = await _buildScheduleDays(
        now: now,
        wakeHour: wakeHour,
        wakeMinute: wakeMinute,
        sleepHour: sleepHour,
        sleepMinute: sleepMinute,
        intervalMinutes: intervalMinutes,
      );
      if (days.every((day) => day.slots.isEmpty)) return;

      final todayKey = _dateKey(now);
      for (final day in days) {
        if (day.slots.isEmpty) continue;

        final dayProgress = _dateKey(day.slots.first.time) == todayKey
            ? progress
            : _TodayProgress(totalMl: 0, goalMl: progress.goalMl);
        final quickAddAmountMl = _suggestedAmountMl(
          dayProgress.remainingMl,
          day.slots.length,
        );
        final notificationDetails = _buildNotificationDetails(
          soundEnabled: soundEnabled,
          progressPercent: dayProgress.percent,
          quickAddAmountMl: quickAddAmountMl,
        );

        for (final slot in day.slots) {
          final regularSlot = slot.time;
          await _plugin.zonedSchedule(
            notificationId,
            dayProgress.title,
            dayProgress.reminderBody(quickAddAmountMl),
            regularSlot,
            notificationDetails,
            androidScheduleMode: scheduleMode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: quickAddAmountMl.toString(),
          );
          notificationId++;

          final followUpSlot = regularSlot.add(const Duration(minutes: 5));
          if (followUpSlot.isBefore(slot.window.sleepTime)) {
            await _plugin.zonedSchedule(
              notificationId,
              dayProgress.followUpTitle,
              dayProgress.followUpBody(quickAddAmountMl),
              followUpSlot,
              notificationDetails,
              androidScheduleMode: scheduleMode,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              payload: quickAddAmountMl.toString(),
            );
            notificationId++;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to schedule reminders id=$notificationId: $e');
    }
  }

  NotificationDetails _buildNotificationDetails({
    required bool soundEnabled,
    required int progressPercent,
    required int quickAddAmountMl,
  }) {
    final channelId = soundEnabled ? _soundChannelId : _silentChannelId;
    final channelName = soundEnabled
        ? 'Water Reminders'
        : 'Water Reminders (Silent)';

    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Hydration reminders throughout the day',
        importance: soundEnabled ? Importance.high : Importance.low,
        priority: soundEnabled ? Priority.high : Priority.low,
        playSound: soundEnabled,
        sound: soundEnabled
            ? const RawResourceAndroidNotificationSound('water_pour')
            : null,
        enableVibration: soundEnabled,
        icon: '@mipmap/launcher_icon',
        showProgress: true,
        maxProgress: 100,
        progress: progressPercent.clamp(0, 100),
        actions: quickAddAmountMl > 0
            ? <AndroidNotificationAction>[
                AndroidNotificationAction(
                  _quickAdd250ActionId,
                  '+$quickAddAmountMl ml',
                  showsUserInterface: false,
                  cancelNotification: true,
                ),
              ]
            : null,
      ),
    );
  }

  Future<void> _queueQuickIntakeFromNotification(double amountMl) async {
    final prefs = await SharedPreferences.getInstance();
    final pendingAmounts =
        prefs.getStringList(_pendingQuickAddAmountsKey) ?? <String>[];
    pendingAmounts.add(amountMl.toString());
    await prefs.setStringList(_pendingQuickAddAmountsKey, pendingAmounts);
    await processPendingNotificationIntakes();
  }

  Future<int> processPendingNotificationIntakes() async {
    await _ensureLocalTimezone();

    final prefs = await SharedPreferences.getInstance();
    final pendingAmounts =
        (prefs.getStringList(_pendingQuickAddAmountsKey) ?? <String>[])
            .map(double.tryParse)
            .whereType<double>()
            .where((amountMl) => amountMl > 0)
            .toList();
    final legacyPendingCount = prefs.getInt(_pendingQuickAddCountKey) ?? 0;
    pendingAmounts.addAll(
      List<double>.filled(legacyPendingCount, _quickAddAmountMl),
    );
    if (pendingAmounts.isEmpty) return 0;

    _ReminderSchedule? schedule;
    final db = AppDatabase();
    try {
      var drinkTypes = await db.drinkTypesDao.getAllDrinkTypes();
      if (drinkTypes.isEmpty) {
        await db.drinkTypesDao.resetToDefaults();
        drinkTypes = await db.drinkTypesDao.getAllDrinkTypes();
      }

      if (drinkTypes.isEmpty) return 0;

      final drinkType = drinkTypes.firstWhere(
        (type) => type.name.toLowerCase() == 'water',
        orElse: () => drinkTypes.first,
      );

      final now = DateTime.now();
      for (var i = 0; i < pendingAmounts.length; i++) {
        final amountMl = pendingAmounts[i];
        await db.waterLogsDao.insertLog(
          WaterLogsCompanion.insert(
            loggedAt: now.add(Duration(milliseconds: i)),
            amountMl: amountMl,
            drinkTypeId: drinkType.id,
          ),
        );
      }

      await prefs.remove(_pendingQuickAddAmountsKey);
      await prefs.remove(_pendingQuickAddCountKey);
      await prefs.setInt(
        AppConstants.prefLastCupSizeMl,
        pendingAmounts.last.round(),
      );
      await prefs.setInt(AppConstants.prefLastDrinkTypeId, drinkType.id);

      final profile = await db.userProfileDao.getProfile();
      if (profile != null) {
        await prefs.setInt(AppConstants.prefTodayGoalMl, profile.dailyGoalMl);
        schedule = _ReminderSchedule.fromProfile(
          wakeHour: profile.wakeHour,
          wakeMinute: profile.wakeMinute,
          sleepHour: profile.sleepHour,
          sleepMinute: profile.sleepMinute,
          intervalMinutes: profile.reminderIntervalMinutes,
          notificationsEnabled: profile.notificationsEnabled,
          soundEnabled:
              prefs.getBool(AppConstants.prefNotificationSound) ?? true,
        );
      }
    } catch (e) {
      debugPrint('Failed to process notification intake: $e');
      return 0;
    } finally {
      await db.close();
    }

    if (schedule != null) {
      await scheduleReminders(
        wakeHour: schedule.wakeHour,
        wakeMinute: schedule.wakeMinute,
        sleepHour: schedule.sleepHour,
        sleepMinute: schedule.sleepMinute,
        intervalMinutes: schedule.intervalMinutes,
        notificationsEnabled: schedule.notificationsEnabled,
        soundEnabled: schedule.soundEnabled,
      );
    }

    return pendingAmounts.length;
  }

  Future<_TodayProgress> _loadTodayProgress() async {
    final db = AppDatabase();
    try {
      final profile = await db.userProfileDao.getProfile();
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final logs = await db.waterLogsDao.getLogsForDateRange(start, end);
      final totalMl = logs.fold<double>(0, (sum, log) => sum + log.amountMl);
      final goalMl = profile?.dailyGoalMl ?? AppConstants.defaultDailyGoalMl;
      return _TodayProgress(totalMl: totalMl, goalMl: goalMl);
    } catch (e) {
      debugPrint('Failed to load notification progress: $e');
      return const _TodayProgress(
        totalMl: 0,
        goalMl: AppConstants.defaultDailyGoalMl,
      );
    } finally {
      await db.close();
    }
  }

  Future<List<_ReminderScheduleDay>> _buildScheduleDays({
    required tz.TZDateTime now,
    required int wakeHour,
    required int wakeMinute,
    required int sleepHour,
    required int sleepMinute,
    required int intervalMinutes,
  }) async {
    final currentWindow = _ReminderWindow.fromNow(
      now: now,
      wakeHour: wakeHour,
      wakeMinute: wakeMinute,
      sleepHour: sleepHour,
      sleepMinute: sleepMinute,
    );
    final nextWindow = currentWindow.nextDay();
    final anchor = await _todayScheduleAnchor(now);
    final currentStart = _startForCurrentWindow(
      window: currentWindow,
      anchor: anchor,
    );

    return <_ReminderScheduleDay>[
      _ReminderScheduleDay(
        window: currentWindow,
        slots: _regularReminderSlots(
          now: now,
          window: currentWindow,
          intervalMinutes: intervalMinutes,
          startTime: currentStart,
        ),
      ),
      _ReminderScheduleDay(
        window: nextWindow,
        slots: _regularReminderSlots(
          now: now,
          window: nextWindow,
          intervalMinutes: intervalMinutes,
          startTime: nextWindow.wakeTime,
        ),
      ),
    ];
  }

  tz.TZDateTime _startForCurrentWindow({
    required _ReminderWindow window,
    required tz.TZDateTime? anchor,
  }) {
    if (anchor == null) return window.wakeTime;
    if (anchor.isBefore(window.wakeTime) ||
        !anchor.isBefore(window.sleepTime)) {
      return window.wakeTime;
    }
    return anchor;
  }

  List<_ReminderSlot> _regularReminderSlots({
    required tz.TZDateTime now,
    required _ReminderWindow window,
    required int intervalMinutes,
    required tz.TZDateTime startTime,
  }) {
    final slots = <_ReminderSlot>[];
    var regularSlot = startTime.add(Duration(minutes: intervalMinutes));
    while (!regularSlot.isAfter(now)) {
      regularSlot = regularSlot.add(Duration(minutes: intervalMinutes));
    }

    while (regularSlot.isBefore(window.sleepTime)) {
      slots.add(_ReminderSlot(time: regularSlot, window: window));
      regularSlot = regularSlot.add(Duration(minutes: intervalMinutes));
    }
    return slots;
  }

  Future<tz.TZDateTime?> _todayScheduleAnchor(tz.TZDateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_scheduleAnchorDateKey) != _dateKey(now)) return null;
    final millis = prefs.getInt(_scheduleAnchorMillisKey);
    if (millis == null) return null;
    return tz.TZDateTime.from(
      DateTime.fromMillisecondsSinceEpoch(millis),
      tz.local,
    );
  }

  String _dateKey(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  int _suggestedAmountMl(int remainingMl, int remainingReminderSlots) {
    if (remainingMl <= 0 || remainingReminderSlots <= 0) return 0;
    final rawAmount = (remainingMl / remainingReminderSlots).ceil();
    return ((rawAmount + 49) ~/ 50) * 50;
  }

  Future<void> _ensureLocalTimezone() async {
    try {
      tz.initializeTimeZones();
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (e) {
      debugPrint('Timezone init failed for notifications: $e');
    }
  }
}

class ReminderPreview {
  const ReminderPreview({
    required this.nextReminderAt,
    required this.suggestedAmountMl,
    required this.remainingReminderSlots,
    required this.targetComplete,
    required this.todayReminderTimes,
    required this.tomorrowReminderTimes,
  });

  const ReminderPreview.none()
    : nextReminderAt = null,
      suggestedAmountMl = 0,
      remainingReminderSlots = 0,
      targetComplete = false,
      todayReminderTimes = const <DateTime>[],
      tomorrowReminderTimes = const <DateTime>[];

  final DateTime? nextReminderAt;
  final int suggestedAmountMl;
  final int remainingReminderSlots;
  final bool targetComplete;
  final List<DateTime> todayReminderTimes;
  final List<DateTime> tomorrowReminderTimes;
}

class _ReminderScheduleDay {
  const _ReminderScheduleDay({required this.window, required this.slots});

  final _ReminderWindow window;
  final List<_ReminderSlot> slots;
}

class _ReminderSlot {
  const _ReminderSlot({required this.time, required this.window});

  final tz.TZDateTime time;
  final _ReminderWindow window;
}

class _ReminderWindow {
  const _ReminderWindow({required this.wakeTime, required this.sleepTime});

  factory _ReminderWindow.fromNow({
    required tz.TZDateTime now,
    required int wakeHour,
    required int wakeMinute,
    required int sleepHour,
    required int sleepMinute,
  }) {
    final wakeMinutesOfDay = wakeHour * 60 + wakeMinute;
    final sleepMinutesOfDay = sleepHour * 60 + sleepMinute;
    final nowMinutesOfDay = now.hour * 60 + now.minute;
    final sleepCrossesMidnight = sleepMinutesOfDay <= wakeMinutesOfDay;

    late tz.TZDateTime wakeTime;
    late tz.TZDateTime sleepTime;

    if (sleepCrossesMidnight && nowMinutesOfDay < sleepMinutesOfDay) {
      final yesterday = now.subtract(const Duration(days: 1));
      wakeTime = tz.TZDateTime(
        tz.local,
        yesterday.year,
        yesterday.month,
        yesterday.day,
        wakeHour,
        wakeMinute,
      );
      sleepTime = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        sleepHour,
        sleepMinute,
      );
    } else {
      wakeTime = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        wakeHour,
        wakeMinute,
      );
      final sleepDate = sleepCrossesMidnight
          ? now.add(const Duration(days: 1))
          : now;
      sleepTime = tz.TZDateTime(
        tz.local,
        sleepDate.year,
        sleepDate.month,
        sleepDate.day,
        sleepHour,
        sleepMinute,
      );
    }

    if (!sleepCrossesMidnight && !now.isBefore(sleepTime)) {
      final tomorrow = now.add(const Duration(days: 1));
      wakeTime = tz.TZDateTime(
        tz.local,
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        wakeHour,
        wakeMinute,
      );
      sleepTime = tz.TZDateTime(
        tz.local,
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        sleepHour,
        sleepMinute,
      );
    }

    if (sleepCrossesMidnight && !now.isBefore(sleepTime)) {
      wakeTime = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        wakeHour,
        wakeMinute,
      );
      final tomorrow = now.add(const Duration(days: 1));
      sleepTime = tz.TZDateTime(
        tz.local,
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        sleepHour,
        sleepMinute,
      );
    }

    return _ReminderWindow(wakeTime: wakeTime, sleepTime: sleepTime);
  }

  _ReminderWindow nextDay() => _ReminderWindow(
    wakeTime: wakeTime.add(const Duration(days: 1)),
    sleepTime: sleepTime.add(const Duration(days: 1)),
  );

  final tz.TZDateTime wakeTime;
  final tz.TZDateTime sleepTime;
}

class _ReminderSchedule {
  const _ReminderSchedule({
    required this.wakeHour,
    required this.wakeMinute,
    required this.sleepHour,
    required this.sleepMinute,
    required this.intervalMinutes,
    required this.notificationsEnabled,
    required this.soundEnabled,
  });

  factory _ReminderSchedule.fromProfile({
    required int wakeHour,
    required int wakeMinute,
    required int sleepHour,
    required int sleepMinute,
    required int intervalMinutes,
    required bool notificationsEnabled,
    required bool soundEnabled,
  }) => _ReminderSchedule(
    wakeHour: wakeHour,
    wakeMinute: wakeMinute,
    sleepHour: sleepHour,
    sleepMinute: sleepMinute,
    intervalMinutes: intervalMinutes,
    notificationsEnabled: notificationsEnabled,
    soundEnabled: soundEnabled,
  );

  final int wakeHour;
  final int wakeMinute;
  final int sleepHour;
  final int sleepMinute;
  final int intervalMinutes;
  final bool notificationsEnabled;
  final bool soundEnabled;
}

class _TodayProgress {
  const _TodayProgress({required this.totalMl, required this.goalMl});

  final double totalMl;
  final int goalMl;

  int get percent {
    if (goalMl <= 0) return 0;
    return ((totalMl / goalMl) * 100).round().clamp(0, 100);
  }

  int get remainingMl => (goalMl - totalMl).ceil().clamp(0, goalMl);

  String get title =>
      percent >= 100 ? 'Hydration goal complete!' : 'Time to hydrate!';

  String get followUpTitle =>
      percent >= 100 ? 'Hydration goal complete!' : 'Still time to hydrate';

  String reminderBody(int suggestedAmountMl) {
    final total = totalMl.round();
    if (percent >= 100) {
      return '$total / $goalMl ml - 100% complete';
    }
    return '$total / $goalMl ml - $percent% complete - add $suggestedAmountMl ml to stay on track';
  }

  String followUpBody(int suggestedAmountMl) {
    if (percent >= 100) return reminderBody(suggestedAmountMl);
    return 'No intake logged yet - add $suggestedAmountMl ml to stay on track';
  }
}
