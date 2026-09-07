import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/double_extensions.dart';
import '../../../core/providers/theme_mode_provider.dart';
import '../../../core/utils/hydration_calculator.dart';
import '../../../core/widgets/weight_picker_dialog.dart';
import '../../onboarding/domain/user_profile_model.dart';
import '../../reminders/data/notification_service.dart';
import '../domain/mascot_type.dart';
import 'providers/mascot_provider.dart';
import 'settings_provider.dart';

Future<void> openBatteryOptimizationSettings() async {
  try {
    const channel = MethodChannel(
      'com.ishaansharma.hydrate_yourself/device_info',
    );
    await channel.invokeMethod('openBatterySettings');
  } catch (e) {
    debugPrint('Could not open battery settings: $e');
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Future<String> _versionFuture;

  @override
  void initState() {
    super.initState();
    _versionFuture = PackageInfo.fromPlatform().then((info) => info.version);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settingsAsync = ref.watch(settingsNotifierProvider);
    final themeMode = ref.watch(themeModeNotifierProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
          child: settingsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Failed to load settings'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref.invalidate(settingsNotifierProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            },
            data: (profile) => profile == null
                ? const Center(child: Text('No profile found'))
                : _buildContent(context, ref, profile, themeMode),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    UserProfileModel profile,
    ThemeMode themeMode,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedMascot = ref.watch(selectedMascotProvider);
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'Settings',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Section A — Profile
              _buildSectionHeader(context, 'Profile'),
              _buildCard(
                context,
                children: [
                  _buildEditableTile(
                    context,
                    icon: Icons.person_outline,
                    label: 'Name',
                    value: profile.name,
                    onTap: () =>
                        _showEditNameDialog(context, ref, profile.name),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildEditableTile(
                    context,
                    icon: Icons.monitor_weight_outlined,
                    label: 'Weight',
                    value: profile.weightKg.toWeightString(profile.weightUnit),
                    onTap: () => _handleEditWeightTap(context, ref, profile),
                  ),
                  const Divider(height: 1, indent: 56),
                  _buildActivityTile(context, ref, profile.activityLevel),
                  const Divider(height: 1, indent: 56),
                  _buildWakeTimeTile(context, ref, profile),
                  const Divider(height: 1, indent: 56),
                  _buildSleepTimeTile(context, ref, profile),
                ],
              ),

              const SizedBox(height: 8),

              // Section B — Lifestyle
              _buildSectionHeader(context, 'Lifestyle'),
              _buildCard(
                context,
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.person_outlined,
                      color: colorScheme.primary,
                    ),
                    title: Text(
                      'Gender',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _genderEmoji(profile.gender),
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            HydrationCalculator.genderLabel(profile.gender),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    onTap: () => _showGenderDialog(context, ref, profile),
                  ),
                  if (profile.gender == 'female') ...[
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: const Text(
                        '🤰',
                        style: TextStyle(fontSize: 22),
                      ),
                      title: Text(
                        'Pregnant',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      subtitle: Builder(
                        builder: (ctx) {
                          final extraRaw = (profile.weightKg * 3.5).clamp(
                            0.0,
                            300.0,
                          );
                          final extra = ((extraRaw / 5).round() * 5).toDouble();
                          final display = profile.unit == 'oz'
                              ? extra.toHalfOzString()
                              : '${extra.round()}ml';
                          return Text(
                            '+$display',
                            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                      value: profile.isPregnant,
                      onChanged: (val) => ref
                          .read(settingsNotifierProvider.notifier)
                          .updateIsPregnant(val),
                    ),
                  ],
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Text(
                      HydrationCalculator.climateEmoji(profile.climateType),
                      style: const TextStyle(fontSize: 20),
                    ),
                    title: Text(
                      'Climate',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            HydrationCalculator.climateLabel(
                              profile.climateType,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    onTap: () => _showClimateDialog(context, ref, profile),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Section C — Hydration
              _buildSectionHeader(context, 'Hydration'),
              _buildCard(
                context,
                children: [
                  _buildGoalTile(context, ref, profile),
                  const Divider(height: 1, indent: 56),
                  _buildGoalBreakdownTile(context, profile),
                  const Divider(height: 1, indent: 56),
                  _buildUnitToggleTile(context, ref, profile.unit),
                ],
              ),

              const SizedBox(height: 8),

              // Section D — Reminders
              _buildSectionHeader(context, 'Reminders'),
              _buildCard(
                context,
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined),
                    title: Text(
                      'Enable reminders',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    value: profile.notificationsEnabled,
                    onChanged: _onNotificationsToggled,
                  ),
                  if (profile.notificationsEnabled) ...[
                    const Divider(height: 1, indent: 56),
                    _buildReminderIntervalTile(context, ref, profile),
                    const Divider(height: 1, indent: 56),
                    _buildSoundToggleTile(context),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.notification_add_outlined,
                        color: colorScheme.primary,
                      ),
                      title: const Text('Send test notification'),
                      subtitle: const Text(
                        'Show one reminder now without changing your schedule',
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: colorScheme.outline,
                      ),
                      onTap: () => _sendTestNotification(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.battery_alert_outlined,
                        color: colorScheme.primary,
                      ),
                      title: const Text('Notifications not arriving on time?'),
                      subtitle: const Text(
                        'Allow Hydrate Yourself to bypass battery '
                        'optimization for reliable delivery',
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: colorScheme.outline,
                      ),
                      onTap: () => _showBatteryOptimizationDialog(context),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.alarm_outlined,
                        color: colorScheme.primary,
                      ),
                      title: const Text('Alarms & reminders'),
                      subtitle: const Text(
                        'Allow Hydrate Yourself to set exact alarms '
                        'so reminders fire on time',
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color: colorScheme.outline,
                      ),
                      onTap: () => _handleAlarmsRowTap(context),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // Section E — Appearance
              _buildSectionHeader(context, 'Appearance'),
              _buildCard(
                context,
                children: [_buildThemeModeTile(context, ref, themeMode)],
              ),

              const SizedBox(height: 8),

              // Section E2 — Jumbo style
              _buildSectionHeader(context, 'Jumbo style'),
              _buildCard(
                context,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: MascotType.values.map((mascot) {
                          final isSelected = mascot == selectedMascot;
                          return GestureDetector(
                            onTap: () => ref
                                .read(selectedMascotProvider.notifier)
                                .setMascot(mascot),
                            child: Container(
                              width: 80,
                              margin: const EdgeInsets.only(right: 10),
                              clipBehavior: Clip.hardEdge,
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.outline.withValues(
                                          alpha: 0.3,
                                        ),
                                  width: isSelected ? 2 : 0.5,
                                ),
                                color: isSelected
                                    ? colorScheme.primaryContainer
                                    : colorScheme.surface,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 52,
                                    height: 52,
                                    child: Image.asset(
                                      mascot.assetPath,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      mascot.label,
                                      style: const TextStyle(fontSize: 11),
                                      maxLines: 1,
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(height: 2),
                                    Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: colorScheme.primary,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Section F — Support
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  'Support',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              _buildCard(
                context,
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.star_outline,
                      color: colorScheme.primary,
                    ),
                    title: Text(
                      'Rate the app',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    onTap: _rateApp,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Icon(
                      Icons.share_outlined,
                      color: colorScheme.primary,
                    ),
                    title: Text(
                      'Share with friends',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    onTap: () => Share.share(
                      'Stay hydrated with Jumbo! 🐘💧\n\n'
                      'Hydrate Yourself helps you track your daily '
                      'water intake with smart reminders\n\n '
                      'Download it free on Google Play:\n'
                      'https://play.google.com/store/apps/details'
                      '?id=com.avinashgupta.watertracker',
                      subject: 'Check out Hydrate Yourself',
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Icon(
                      Icons.mail_outline,
                      color: colorScheme.primary,
                    ),
                    title: Text(
                      'Contact developer',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    subtitle: const Text('Questions, feedback or bugs'),
                    onTap: () async {
                      final Uri emailUri = Uri(
                        scheme: 'mailto',
                        path: 'sarthiindia2020@gmail.com',
                        queryParameters: {
                          'subject': 'Hydrate Yourself — Feedback',
                        },
                      );
                      try {
                        final launched = await launchUrl(
                          emailUri,
                          mode: LaunchMode.externalApplication,
                        );
                        if (!launched && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('sarthiindia2020@gmail.com'),
                              action: SnackBarAction(
                                label: 'Copy',
                                onPressed: () => Clipboard.setData(
                                  const ClipboardData(
                                    text: 'sarthiindia2020@gmail.com',
                                  ),
                                ),
                              ),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('sarthiindia2020@gmail.com'),
                              action: SnackBarAction(
                                label: 'Copy',
                                onPressed: () => Clipboard.setData(
                                  const ClipboardData(
                                    text: 'sarthiindia2020@gmail.com',
                                  ),
                                ),
                              ),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: Icon(
                      Icons.privacy_tip_outlined,
                      color: colorScheme.primary,
                    ),
                    title: const Text('Privacy Policy'),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: colorScheme.outline,
                    ),
                    onTap: () async {
                      final uri = Uri.parse(
                        'https://sarthi2020.github.io/hydrate_yourself_privacy/',
                      );
                      try {
                        final launched = await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                        if (!launched && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Visit our privacy policy at: '
                                'sarthi2020.github.io/hydrate_yourself_privacy',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not open browser. Visit our privacy '
                                'policy at: sarthi2020.github.io/hydrate_yourself_privacy',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Section G — About
              _buildSectionHeader(context, 'About'),
              _buildCard(
                context,
                children: [
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(
                      'Version',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    trailing: FutureBuilder<String>(
                      future: _versionFuture,
                      builder: (context, snapshot) => Text(
                        snapshot.data ?? '—',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Section G — Data
              _buildSectionHeader(context, 'Data'),
              _buildCard(
                context,
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.delete_forever_outlined,
                      color: colorScheme.error,
                    ),
                    title: Text(
                      'Delete all data',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: colorScheme.error),
                    ),
                    onTap: () => _confirmDeleteAllData(context, ref),
                  ),
                ],
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _sendTestNotification(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final granted = await NotificationService().requestPermissions();
    if (!granted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Notification permission is required')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final soundEnabled =
        prefs.getBool(AppConstants.prefNotificationSound) ?? true;
    await NotificationService().showTestReminderNow(soundEnabled: soundEnabled);

    messenger.showSnackBar(
      const SnackBar(content: Text('Test notification sent')),
    );
  }

  Future<void> _onNotificationsToggled(bool enabled) async {
    if (enabled) {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      final canSchedule = await android?.canScheduleExactNotifications();
      if (canSchedule == false) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Enable exact reminders'),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: const Text(
                    'To receive reminders at exactly the right time, '
                    'Hydrate Yourself needs permission to set precise alarms.\n\n'
                    'On the next screen, enable '
                    '"Allow setting alarms and reminders".',
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Cancel'),
                  ),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await android?.requestExactAlarmsPermission();
                  },
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Open settings'),
                  ),
                ),
              ],
            ),
          );
        }
      }
    }

    ref
        .read(settingsNotifierProvider.notifier)
        .updateNotificationsEnabled(enabled);
  }

  Widget _buildThemeModeTile(
    BuildContext context,
    WidgetRef ref,
    ThemeMode themeMode,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.brightness_6_outlined, color: colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Theme', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _themeChip(
                        label: 'Auto',
                        icon: Icons.brightness_auto_outlined,
                        value: ThemeMode.system,
                        selected: themeMode,
                        onTap: (v) => ref
                            .read(themeModeNotifierProvider.notifier)
                            .setThemeMode(v),
                      ),
                      const SizedBox(width: 8),
                      _themeChip(
                        label: 'Light',
                        icon: Icons.light_mode_outlined,
                        value: ThemeMode.light,
                        selected: themeMode,
                        onTap: (v) => ref
                            .read(themeModeNotifierProvider.notifier)
                            .setThemeMode(v),
                      ),
                      const SizedBox(width: 8),
                      _themeChip(
                        label: 'Dark',
                        icon: Icons.dark_mode_outlined,
                        value: ThemeMode.dark,
                        selected: themeMode,
                        onTap: (v) => ref
                            .read(themeModeNotifierProvider.notifier)
                            .setThemeMode(v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeChip({
    required String label,
    required IconData icon,
    required ThemeMode value,
    required ThemeMode selected,
    required void Function(ThemeMode) onTap,
  }) {
    final isSelected = value == selected;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surface,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rateApp() async {
    try {
      await InAppReview.instance.openStoreListing(
        appStoreId: 'com.avinashgupta.watertracker',
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Play Store')),
        );
      }
    }
  }

  void _confirmDeleteAllData(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('Delete all data?'),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This will permanently delete all your water logs and reset your profile. This cannot be undone.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Cancel'),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () async {
                Navigator.pop(dialogContext);
                await ref
                    .read(settingsNotifierProvider.notifier)
                    .deleteAllData();
                ref
                    .read(themeModeNotifierProvider.notifier)
                    .setThemeMode(ThemeMode.system);
                if (context.mounted) {
                  context.go('/onboarding');
                }
              },
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Delete everything'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, {required List<Widget> children}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: children),
    );
  }

  Widget _buildEditableTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: colorScheme.primary),
      title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildActivityTile(
    BuildContext context,
    WidgetRef ref,
    int currentLevel,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    const labels = ['Sedentary', 'Light', 'Moderate', 'Active'];
    return ListTile(
      leading: Icon(Icons.directions_run_outlined, color: colorScheme.primary),
      title: Text(
        'Activity Level',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              labels[currentLevel.clamp(0, 3)],
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () => _showActivityDialog(context, ref, currentLevel),
    );
  }

  Widget _buildWakeTimeTile(
    BuildContext context,
    WidgetRef ref,
    UserProfileModel profile,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.wb_sunny_outlined, color: colorScheme.primary),
      title: Text('Wake up', style: Theme.of(context).textTheme.bodyLarge),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _formatTime(profile.wakeHour, profile.wakeMinute),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () => _showAlarmTimePicker(
        context,
        title: 'Wake up time',
        currentHour: profile.wakeHour,
        currentMinute: profile.wakeMinute,
        onSelected: (h, m) =>
            ref.read(settingsNotifierProvider.notifier).updateWakeTime(h, m),
      ),
    );
  }

  Widget _buildSleepTimeTile(
    BuildContext context,
    WidgetRef ref,
    UserProfileModel profile,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.bedtime_outlined, color: colorScheme.primary),
      title: Text('Bedtime', style: Theme.of(context).textTheme.bodyLarge),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _formatTime(profile.sleepHour, profile.sleepMinute),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () => _showAlarmTimePicker(
        context,
        title: 'Bedtime',
        currentHour: profile.sleepHour,
        currentMinute: profile.sleepMinute,
        onSelected: (h, m) =>
            ref.read(settingsNotifierProvider.notifier).updateSleepTime(h, m),
      ),
    );
  }

  void _showAlarmTimePicker(
    BuildContext context, {
    required String title,
    required int currentHour,
    required int currentMinute,
    required void Function(int hour, int minute) onSelected,
  }) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: currentHour, minute: currentMinute),
      helpText: title,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onSelected(picked.hour, picked.minute);
    }
  }

  String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h = hour == 0
        ? 12
        : hour > 12
        ? hour - 12
        : hour;
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  Widget _buildGoalTile(
    BuildContext context,
    WidgetRef ref,
    UserProfileModel profile,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.flag_outlined, color: colorScheme.primary),
      title: Text('Daily Goal', style: Theme.of(context).textTheme.bodyLarge),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              profile.unit == 'oz'
                  ? profile.dailyGoalMl.toDouble().toWholeOzString()
                  : '${profile.dailyGoalMl} ml',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: () => _showGoalDialog(context, ref, profile),
    );
  }

  Widget _buildUnitToggleTile(
    BuildContext context,
    WidgetRef ref,
    String currentUnit,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.straighten_outlined, color: colorScheme.primary),
      title: Text('Unit', style: Theme.of(context).textTheme.bodyLarge),
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'ml', label: Text('ml')),
          ButtonSegment(value: 'oz', label: Text('oz')),
        ],
        selected: {currentUnit},
        onSelectionChanged: (val) {
          ref.read(settingsNotifierProvider.notifier).updateUnit(val.first);
        },
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
  }

  Widget _buildGoalBreakdownTile(
    BuildContext context,
    UserProfileModel profile,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.calculate_outlined, color: colorScheme.primary),
      title: Text('How is this calculated?', style: theme.textTheme.bodyLarge),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: () => _showGoalBreakdown(context, profile),
    );
  }

  void _showGoalBreakdown(BuildContext context, UserProfileModel profile) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final unit = profile.unit;

    final base = profile.weightKg * 35;

    const activityLabels = ['Sedentary', 'Light', 'Moderate', 'Active'];
    const activityMultipliers = [1.0, 1.1, 1.2, 1.4];
    final activityMult = activityMultipliers[profile.activityLevel.clamp(0, 3)];
    final afterActivity = base * activityMult;

    final genderMult = profile.gender == 'female' ? 0.92 : 1.0;
    final afterGender = afterActivity * genderMult;

    final pregnancyExtraRaw = (profile.isPregnant && profile.gender == 'female')
        ? (profile.weightKg * 3.5).clamp(0.0, 300.0)
        : 0.0;
    final pregnancyExtra = ((pregnancyExtraRaw / 5).round() * 5).toDouble();
    final afterPregnancy = afterGender + pregnancyExtra;

    final climateMults = {
      'cold': 0.9,
      'moderate': 1.0,
      'hot': 1.15,
      'very_hot': 1.30,
    };
    final climateMult = climateMults[profile.climateType] ?? 1.0;
    final afterClimate = afterPregnancy * climateMult;
    final finalGoal = HydrationCalculator.calculateDailyGoalMl(
      weightKg: profile.weightKg,
      activityLevel: profile.activityLevel,
      gender: profile.gender,
      isPregnant: profile.isPregnant,
      climateType: profile.climateType,
    );

    final weightUnit = profile.weightUnit;
    final isOz = unit == 'oz';
    String baseFormula;
    if (weightUnit == 'lbs' && isOz) {
      baseFormula =
          '${profile.weightKg.kgToLbs.toStringAsFixed(1)}'
          'lbs × 0.54 fl oz/lb';
    } else if (weightUnit == 'lbs' && !isOz) {
      baseFormula =
          '${profile.weightKg.kgToLbs.toStringAsFixed(1)}'
          'lbs × 15.9ml/lb';
    } else if (weightUnit == 'kg' && isOz) {
      baseFormula =
          '${profile.weightKg.toStringAsFixed(1)}'
          'kg × 1.18 fl oz/kg';
    } else {
      baseFormula =
          '${profile.weightKg.toStringAsFixed(1)}'
          'kg × 35ml/kg';
    }

    String fmt(double ml) {
      if (unit == 'oz') {
        return ml.toWholeOzString();
      }
      return ml >= 1000
          ? '${(ml / 1000).toStringAsFixed(1)} L'
          : '${ml.round()} ml';
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Goal Calculation'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Your daily goal is based on:',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...[
                  _breakdownRow(context, '⚖️ Base', baseFormula, fmt(base)),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  _breakdownRow(
                    context,
                    '🏃 Activity (${activityLabels[profile.activityLevel.clamp(0, 3)]})',
                    '× ${activityMult.toStringAsFixed(1)}',
                    fmt(afterActivity),
                  ),
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  _breakdownRow(
                    context,
                    '${profile.gender == 'female' ? '👩' : '👨'} Gender',
                    profile.gender == 'female'
                        ? '× 0.92 (female adjustment)'
                        : '',
                    profile.gender == 'female' ? fmt(afterGender) : 'No change',
                  ),
                  if (profile.isPregnant && profile.gender == 'female') ...[
                    Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    _breakdownRow(
                      context,
                      '🤰 Pregnancy',
                      unit == 'oz'
                          ? '+ ${(pregnancyExtra * 0.033814).toStringAsFixed(1)}'
                                ' fl oz (max 10.1 fl oz)'
                          : '+ ${pregnancyExtra.toInt()}ml (max 300ml)',
                      fmt(afterPregnancy),
                    ),
                  ],
                  Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                  _breakdownRow(
                    context,
                    '${HydrationCalculator.climateEmoji(profile.climateType)} Climate'
                        ' (${HydrationCalculator.climateLabel(profile.climateType)})',
                    '× $climateMult',
                    fmt(afterClimate),
                  ),
                  if (afterClimate.round() != finalGoal) ...[
                    Divider(
                      height: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    _breakdownRow(
                      context,
                      '📊 Adjusted',
                      'Based on recommended guidelines for your profile',
                      fmt(finalGoal.toDouble()),
                    ),
                  ],
                ],
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      flex: 2,
                      child: Text(
                        'Your daily goal',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 3,
                      child: Text(
                        fmt(finalGoal.toDouble()),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'General guideline based on established hydration research. '
                    'Individual needs vary. Consult a doctor for a personalised recommendation.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Got it'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(
    BuildContext context,
    String label,
    String formula,
    String result,
  ) {
    final theme = Theme.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (formula.isNotEmpty)
                  Text(
                    formula,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            result,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderIntervalTile(
    BuildContext context,
    WidgetRef ref,
    UserProfileModel profile,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);

    return ListTile(
      leading: Icon(Icons.timer_outlined, color: colorScheme.primary),
      title: Text(
        'Remind me every',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      subtitle: FutureBuilder<ReminderPreview>(
        future: NotificationService().getReminderPreview(
          wakeHour: profile.wakeHour,
          wakeMinute: profile.wakeMinute,
          sleepHour: profile.sleepHour,
          sleepMinute: profile.sleepMinute,
          intervalMinutes: profile.reminderIntervalMinutes,
          notificationsEnabled: profile.notificationsEnabled,
        ),
        builder: (context, snapshot) {
          final intervalText = _formatInterval(profile.reminderIntervalMinutes);
          final preview = snapshot.data;
          if (preview == null) {
            return Text(
              '$intervalText\nNext reminder: calculating...',
              style: textStyle,
            );
          }

          return Text(
            _buildReminderPreviewText(intervalText, preview),
            style: textStyle,
          );
        },
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: () =>
          _showReminderPicker(context, ref, profile.reminderIntervalMinutes),
    );
  }

  void _showEditNameDialog(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Edit Name',
                    style: Theme.of(dialogContext).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Cancel'),
                      ),
                    ),
                    FilledButton(
                      onPressed: () {
                        final name = controller.text.trim();
                        if (name.isEmpty) return;
                        Navigator.pop(dialogContext);
                        ref
                            .read(settingsNotifierProvider.notifier)
                            .updateName(name);
                      },
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleEditWeightTap(
    BuildContext context,
    WidgetRef ref,
    UserProfileModel profile,
  ) async {
    final result = await showWeightPickerDialog(
      context: context,
      currentWeightKg: profile.weightKg,
      currentUnit: profile.weightUnit,
    );
    if (result == null) return;

    final (weightKg, unit) = result;
    final weightInUnit = unit == AppConstants.unitLbs
        ? weightKg.kgToLbs
        : weightKg;
    ref
        .read(settingsNotifierProvider.notifier)
        .updateWeight(weightInUnit, unit);
    ref.read(settingsNotifierProvider.notifier).updateWeightUnit(unit);
  }

  void _showActivityDialog(
    BuildContext context,
    WidgetRef ref,
    int currentLevel,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Activity Level'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: RadioGroup<int>(
              groupValue: currentLevel,
              onChanged: (val) {
                if (val == null) return;
                Navigator.pop(dialogContext);
                ref
                    .read(settingsNotifierProvider.notifier)
                    .updateActivityLevel(val);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<int>(
                    value: 0,
                    title: const Text('Sedentary'),
                    secondary: const Icon(Icons.chair),
                  ),
                  RadioListTile<int>(
                    value: 1,
                    title: const Text('Light'),
                    secondary: const Icon(Icons.directions_walk),
                  ),
                  RadioListTile<int>(
                    value: 2,
                    title: const Text('Moderate'),
                    secondary: const Icon(Icons.directions_run),
                  ),
                  RadioListTile<int>(
                    value: 3,
                    title: const Text('Active'),
                    secondary: const Icon(Icons.fitness_center),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  void _showGoalDialog(
    BuildContext context,
    WidgetRef ref,
    UserProfileModel profile,
  ) {
    final isOz = profile.unit == 'oz';

    final smallStep = isOz ? 30 : 50;
    final largeStep = isOz ? 148 : 250;

    final smallLabel = isOz ? '1 oz' : '50 ml';
    final largeLabel = isOz ? '5 oz' : '250 ml';

    const minMl = 1500;
    const maxMl = 4500;

    showDialog(
      context: context,
      builder: (dialogContext) {
        int currentMl = profile.dailyGoalMl;
        Timer? holdTimer;

        String displayValue(int ml) {
          if (isOz) {
            return ml.toDouble().toWholeOzString();
          }
          return '${ml.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} ml';
        }

        void startHold(StateSetter setState, int stepMl, bool isAdd) {
          holdTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
            setState(() {
              currentMl = isAdd
                  ? (currentMl + stepMl).clamp(minMl, maxMl)
                  : (currentMl - stepMl).clamp(minMl, maxMl);
            });
          });
        }

        void stopHold() {
          holdTimer?.cancel();
          holdTimer = null;
        }

        return StatefulBuilder(
          builder: (ctx, setState) {
            final colorScheme = Theme.of(ctx).colorScheme;
            final theme = Theme.of(ctx);

            Widget stepButton({
              required String label,
              required int stepMl,
              required bool isAdd,
              required IconData icon,
            }) {
              final atLimit = isAdd ? currentMl >= maxMl : currentMl <= minMl;

              return GestureDetector(
                onTap: atLimit
                    ? null
                    : () {
                        setState(() {
                          currentMl = isAdd
                              ? (currentMl + stepMl).clamp(minMl, maxMl)
                              : (currentMl - stepMl).clamp(minMl, maxMl);
                        });
                      },
                onLongPressStart: atLimit
                    ? null
                    : (_) => startHold(setState, stepMl, isAdd),
                onLongPressEnd: (_) => stopHold(),
                onLongPressCancel: stopHold,
                child: AnimatedOpacity(
                  opacity: atLimit ? 0.35 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    clipBehavior: Clip.hardEdge,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 18,
                          color: isAdd
                              ? colorScheme.primary
                              : colorScheme.error,
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${isAdd ? '+' : '−'}$label',
                            maxLines: 1,
                            softWrap: false,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isAdd
                                  ? colorScheme.primary
                                  : colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              title: const FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Daily Goal'),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            displayValue(currentMl),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: stepButton(
                              label: largeLabel,
                              stepMl: largeStep,
                              isAdd: false,
                              icon: Icons.remove_circle_outline,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: stepButton(
                              label: smallLabel,
                              stepMl: smallStep,
                              isAdd: false,
                              icon: Icons.remove,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: stepButton(
                              label: smallLabel,
                              stepMl: smallStep,
                              isAdd: true,
                              icon: Icons.add,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: stepButton(
                              label: largeLabel,
                              stepMl: largeStep,
                              isAdd: true,
                              icon: Icons.add_circle_outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              isOz ? '51 oz min' : '1,500 ml min',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              isOz ? '152 oz max' : '4,500 ml max',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Hold a button to change quickly',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    stopHold();
                    Navigator.pop(dialogContext);
                  },
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Cancel'),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    stopHold();
                    Navigator.pop(dialogContext);
                    ref
                        .read(settingsNotifierProvider.notifier)
                        .updateGoal(currentMl);
                  },
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Save'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showReminderPicker(
    BuildContext context,
    WidgetRef ref,
    int currentMinutes,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    int selectedHours = (currentMinutes ~/ 60).clamp(0, 8);
    int selectedQuarter = ((currentMinutes % 60) ~/ 15).clamp(0, 3);

    final hourController = FixedExtentScrollController(
      initialItem: selectedHours,
    );
    final minuteController = FixedExtentScrollController(
      initialItem: selectedQuarter,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            int totalMinutes() => selectedHours * 60 + selectedQuarter * 15;

            String formatSelected() {
              final t = totalMinutes();
              if (t == 0) return 'Off';
              final h = t ~/ 60;
              final m = t % 60;
              if (h == 0) return '$m min';
              if (m == 0) return h == 1 ? '1 hr' : '$h hrs';
              return '$h hr $m min';
            }

            return Container(
              padding: const EdgeInsets.only(
                top: 20,
                left: 24,
                right: 24,
                bottom: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Reminder every',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Remind you to drink when you haven't logged",
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 200,
                      child: Row(
                        children: [
                          // Hours wheel (0–8)
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                CupertinoPicker(
                                  scrollController: hourController,
                                  itemExtent: 44,
                                  selectionOverlay: const SizedBox.shrink(),
                                  onSelectedItemChanged: (i) =>
                                      setState(() => selectedHours = i),
                                  children: List.generate(
                                    9,
                                    (i) => Center(
                                      child: Text(
                                        '$i hr',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Minutes wheel (:00, :15, :30, :45)
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                CupertinoPicker(
                                  scrollController: minuteController,
                                  itemExtent: 44,
                                  selectionOverlay: const SizedBox.shrink(),
                                  onSelectedItemChanged: (i) =>
                                      setState(() => selectedQuarter = i),
                                  children: [
                                    Center(
                                      child: Text(
                                        ':00 min',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: Text(
                                        ':15 min',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: Text(
                                        ':30 min',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: Text(
                                        ':45 min',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (totalMinutes() == 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Reminder interval cannot be 0. Choose at least 15 minutes.',
                          style: TextStyle(
                            color: colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      Text(
                        'Remind me every ${formatSelected()}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: totalMinutes() == 0
                            ? null
                            : () {
                                Navigator.pop(dialogContext);
                                ref
                                    .read(settingsNotifierProvider.notifier)
                                    .updateReminderInterval(totalMinutes());
                              },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          totalMinutes() == 0
                              ? 'Choose a valid interval'
                              : 'Confirm — every ${formatSelected()}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatInterval(int minutes) {
    if (minutes == 0) return 'Off';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return hours == 1 ? '1 hr' : '$hours hrs';
    return '$hours hr $mins min';
  }

  String _buildReminderPreviewText(
    String intervalText,
    ReminderPreview preview,
  ) {
    final nextReminderAt = preview.nextReminderAt;
    if (nextReminderAt == null) {
      return '$intervalText\nNo reminder scheduled today';
    }

    final suggestion = preview.targetComplete
        ? 'Goal complete'
        : 'Suggested add: ${preview.suggestedAmountMl} ml';
    return '$intervalText\nNext: ${_formatReminderDateTime(nextReminderAt)} • $suggestion';
  }

  String _formatReminderDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final dayLabel = date == today
        ? 'Today'
        : date == today.add(const Duration(days: 1))
        ? 'Tomorrow'
        : '${local.day}/${local.month}/${local.year}';
    return '$dayLabel, ${_formatTime(local.hour, local.minute)}';
  }

  Widget _buildSoundToggleTile(BuildContext context) {
    return FutureBuilder<bool>(
      future: SharedPreferences.getInstance().then(
        (prefs) => prefs.getBool(AppConstants.prefNotificationSound) ?? true,
      ),
      builder: (context, snapshot) {
        final soundEnabled = snapshot.data ?? true;
        return SwitchListTile(
          secondary: const Icon(Icons.volume_up_outlined),
          title: Text(
            'Notification sound',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          value: soundEnabled,
          onChanged: (val) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(AppConstants.prefNotificationSound, val);
            setState(() {});

            final profile = ref.read(settingsNotifierProvider).valueOrNull;
            if (profile == null || !profile.notificationsEnabled) return;

            await NotificationService().scheduleReminders(
              wakeHour: profile.wakeHour,
              wakeMinute: profile.wakeMinute,
              sleepHour: profile.sleepHour,
              sleepMinute: profile.sleepMinute,
              intervalMinutes: profile.reminderIntervalMinutes,
              notificationsEnabled: true,
              soundEnabled: val,
            );
          },
        );
      },
    );
  }

  String _genderEmoji(String gender) {
    switch (gender) {
      case 'male':
        return '👨';
      case 'female':
        return '👩';
      case 'other':
        return '🧑';
      default:
        return '👨';
    }
  }

  void _showGenderDialog(
    BuildContext context,
    WidgetRef ref,
    UserProfileModel profile,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Gender'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: RadioGroup<String>(
              groupValue: profile.gender,
              onChanged: (val) {
                if (val == null) return;
                Navigator.pop(dialogContext);
                ref.read(settingsNotifierProvider.notifier).updateGender(val);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'male',
                    title: Row(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text('👨', style: TextStyle(fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Male',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'female',
                    title: Row(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text('👩', style: TextStyle(fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Female',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  void _showClimateDialog(
    BuildContext context,
    WidgetRef ref,
    UserProfileModel profile,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Climate'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: RadioGroup<String>(
              groupValue: profile.climateType,
              onChanged: (val) {
                if (val == null) return;
                Navigator.pop(dialogContext);
                ref
                    .read(settingsNotifierProvider.notifier)
                    .updateClimateType(val);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    value: 'cold',
                    title: Row(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text('🥶', style: TextStyle(fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Cold',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                    subtitle: const Text('Cool or cold weather'),
                  ),
                  RadioListTile<String>(
                    value: 'moderate',
                    title: Row(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text('🌤️', style: TextStyle(fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Moderate',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                    subtitle: const Text('Mild everyday conditions'),
                  ),
                  RadioListTile<String>(
                    value: 'hot',
                    title: Row(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text('☀️', style: TextStyle(fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Hot',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                    subtitle: const Text('Warm and sunny weather'),
                  ),
                  RadioListTile<String>(
                    value: 'very_hot',
                    title: Row(
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text('🔥', style: TextStyle(fontSize: 20)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Very Hot',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ],
                    ),
                    subtitle: const Text('Hot, humid or desert conditions'),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  void _showBatteryOptimizationDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Getting reminders late?'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Some phones aggressively manage battery '
                  'to save power, which can delay or block '
                  'notifications from apps like Hydrate '
                  'Yourself.',
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'To fix this:',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildStep(context, '1.', 'Tap "Open settings" below'),
                const SizedBox(height: 6),
                _buildStep(context, '2.', 'Find Hydrate Yourself in the list'),
                const SizedBox(height: 6),
                _buildStep(context, '3.', "Select \"Don't optimize\""),
                const SizedBox(height: 16),
                Text(
                  'This has minimal battery impact — '
                  'the app only wakes briefly to show '
                  'a notification.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Close')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openBatteryOptimizationSettings();
            },
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Open settings'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAlarmsRowTap(BuildContext context) async {
    final isGranted = await NotificationService()
        .isExactAlarmPermissionGranted();
    if (!context.mounted) return;
    if (isGranted) {
      _showAlarmsAlreadyEnabledDialog(context);
    } else {
      _showExactAlarmsDialog(context);
    }
  }

  void _showAlarmsAlreadyEnabledDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Exact reminders enabled'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              'Hydrate Yourself already has permission to set '
              'precise alarms, so your reminders will fire on '
              'time.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Close')),
          ),
        ],
      ),
    );
  }

  void _showExactAlarmsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Enable exact reminders'),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To receive reminders at exactly the right '
                  'time, Hydrate Yourself needs permission to '
                  'set precise alarms.',
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'To fix this:',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildStep(context, '1.', 'Tap "Open settings" below'),
                const SizedBox(height: 6),
                _buildStep(
                  context,
                  '2.',
                  'Enable "Allow setting alarms and reminders"',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const FittedBox(fit: BoxFit.scaleDown, child: Text('Close')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final android = FlutterLocalNotificationsPlugin()
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >();
              await android?.requestExactAlarmsPermission();
            },
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Open settings'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context, String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            number,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
      ],
    );
  }
}
