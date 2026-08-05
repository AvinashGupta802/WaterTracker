import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/double_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../onboarding/domain/user_profile_model.dart';
import '../../reminders/data/notification_service.dart';
import '../../reminders/presentation/reminders_provider.dart';
import '../domain/today_override.dart';
import '../domain/today_summary.dart';
import '../domain/water_log_model.dart';
import 'home_provider.dart';
import 'widgets/celebration_overlay.dart';
import 'widgets/cup_size_sheet.dart';
import 'widgets/drink_type_sheet.dart';
import 'widgets/jumbo_widget.dart';
import 'widgets/water_wave.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  late DateTime _lastKnownDate;

  // JumboWidget's natural (unscaled) size before its outer FittedBox would
  // start shrinking it: 160 mascot (fixed per CLAUDE.md) + 6 spacer +
  // 30 label pill (14 vertical padding + ~16 line height at fontSize 13)
  // = 196. Giving it at least this height means it renders at full design
  // size instead of being scaled down by FittedBox(fit: BoxFit.scaleDown).
  static const double _compactJumboHeight = 196;

  // Sum of every other section's real height, using Material 3's default
  // type-scale line heights (this app's ThemeData doesn't override font
  // sizes, only the font family via GoogleFonts.nunitoTextTheme):
  //   _buildHeader:         24 (padding) + 20 (bodyMedium) + 32 (headlineSmall) = 76
  //   _buildProgressText:   8 (padding) + 40 (displaySmall line) + 16 (bodySmall)
  //                         + 8 (spacer) + 16 (labelSmall) + 2 (spacer)
  //                         + 8 (progress bar) + 3 (spacer) + 12 (tick marks) = 113
  //   _buildBottomControls: max(60 left zone, 91 right zone [10 padding +
  //                         40 + 0.5 divider + 40, rounded up]) = 91
  //   trailing SizedBox:    16
  //   subtotal = 76 + 113 + 91 + 16 = 296
  // Plus _compactJumboHeight (196) plus a ~24px safety margin:
  //   296 + 196 + 24 = 516
  static const double _compactLayoutThreshold = 516;

  // 16px outer padding each side (32 total) + 196px left zone (two 60px
  // _GlassButtons + one 60px undo box + two 8px gaps) + 50px right zone
  // (5px padding each side + 40px icon column) = 278px absolute minimum
  // before this Row hard-overflows horizontally. Plus a safety margin so
  // buttons aren't pixel-perfect-tight right at the boundary: 320.
  static const double _compactButtonRowThreshold = 320;

  // 48 is Android's documented minimum comfortable tap-target size — the
  // floor this shrinks to never makes these buttons uncomfortable to press.
  static const double _compactButtonSize = 48;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastKnownDate = DateTime.now();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (!DateUtils.isSameDay(now, _lastKnownDate)) {
        _lastKnownDate = now;
        ref.invalidate(todayTotalMlProvider);
        ref.invalidate(todaySummaryProvider);
        ref.invalidate(lastLogProvider);
        ref.invalidate(todayOverrideNotifierProvider);
        ref.read(goalPreviouslyAchievedProvider.notifier).state = false;
      }
      final processedNotificationIntakes =
          await NotificationService().processPendingNotificationIntakes();
      if (processedNotificationIntakes > 0) {
        ref.invalidate(todayTotalMlProvider);
        ref.invalidate(todaySummaryProvider);
        ref.invalidate(lastLogProvider);
      }
      await NotificationService().dismissActiveNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationSetupNotifierProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final summaryAsync = ref.watch(todaySummaryProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final unit = profile?.unit ?? AppConstants.unitMl;
    final showCelebration = ref.watch(showCelebrationProvider);
    final jumboAmountAsync = ref.watch(jumboTapAmountProvider);
    final jumboAmount = jumboAmountAsync.valueOrNull ?? 250;
    final selectedDrinkTypeId = ref.watch(selectedDrinkTypeIdProvider);
    final lastLogAsync = ref.watch(lastLogProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // LAYER 1: Full screen wave
          if (summaryAsync.valueOrNull != null)
            Positioned.fill(
              child: WaterWave(
                fillPercent: summaryAsync.valueOrNull!.percentage,
                waveColor: colorScheme.primary,
              ),
            ),

          // LAYER 2: Content
          SafeArea(
            child: Builder(
              builder: (context) {
                if (summaryAsync.isLoading &&
                    summaryAsync.valueOrNull == null) {
                  return _buildSkeleton(context);
                }
                if (summaryAsync.hasError &&
                    summaryAsync.valueOrNull == null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Error: ${summaryAsync.error}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        softWrap: true,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final summary = summaryAsync.valueOrNull!;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxHeight >= _compactLayoutThreshold) {
                      return _buildContent(
                        context, ref, summary, unit, jumboAmount,
                        profile, selectedDrinkTypeId, lastLogAsync,
                      );
                    }
                    return _buildCompactContent(
                      context, ref, summary, unit, jumboAmount,
                      profile, selectedDrinkTypeId, lastLogAsync,
                    );
                  },
                );
              },
            ),
          ),

          // LAYER 3: Celebration (topmost — above Jumbo and all content)
          if (showCelebration)
            CelebrationOverlay(
              isVisible: showCelebration,
              unit: unit,
            ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    TodaySummary summary,
    String unit,
    int jumboAmount,
    UserProfileModel? profile,
    int? selectedDrinkTypeId,
    AsyncValue<WaterLogModel?> lastLogAsync,
  ) {
    return Column(
      children: [
        _buildHeader(context, profile),
        _buildProgressText(context, summary, unit),
        Expanded(
          child: ClipRect(
            child: Center(
              child: JumboWidget(
                tapAmount: jumboAmount,
                unit: unit,
                onTap: () => ref
                    .read(homeActionProvider.notifier)
                    .addQuickLog(jumboAmount.toDouble()),
              ),
            ),
          ),
        ),
        _buildBottomControls(
          context, ref, unit, selectedDrinkTypeId, lastLogAsync,
          jumboAmount, profile,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCompactContent(
    BuildContext context,
    WidgetRef ref,
    TodaySummary summary,
    String unit,
    int jumboAmount,
    UserProfileModel? profile,
    int? selectedDrinkTypeId,
    AsyncValue<WaterLogModel?> lastLogAsync,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(context, profile),
          _buildProgressText(context, summary, unit),
          SizedBox(
            height: _compactJumboHeight,
            child: Center(
              child: JumboWidget(
                tapAmount: jumboAmount,
                unit: unit,
                onTap: () => ref
                    .read(homeActionProvider.notifier)
                    .addQuickLog(jumboAmount.toDouble()),
              ),
            ),
          ),
          _buildBottomControls(
            context, ref, unit, selectedDrinkTypeId,
            lastLogAsync, jumboAmount, profile,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, UserProfileModel? profile) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getGreeting(),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  profile?.name ?? 'there',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress text + bar ──────────────────────────────────────────────────────

  Widget _buildProgressText(
    BuildContext context,
    TodaySummary summary,
    String unit,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: unit == 'oz'
                        ? '${(summary.totalMl * 0.033814).round()}'
                        : _formatMl(summary.totalMl.round()),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                      letterSpacing: -1,
                    ),
                  ),
                  TextSpan(
                    text: unit == 'oz' ? ' oz' : ' ml',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            summary.isGoalAchieved
                ? '🎉 Goal achieved!'
                : unit == 'oz'
                    ? '${(summary.remainingMl * 0.033814).round()} oz to go · '
                        'goal ${(summary.goalMl * 0.033814).round()} oz'
                    : '${_formatMl(summary.remainingMl.round())} ml to go · '
                        'goal ${_formatMl(summary.goalMl)} ml',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: theme.textTheme.bodySmall?.copyWith(
              color: summary.isGoalAchieved
                  ? AppColors.goalAchieved
                  : colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              final pct = summary.percentage.clamp(0.0, 1.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${(pct * 100).round()}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getProgressColor(context, summary.percentage),
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    height: 12,
                    child: Stack(
                      children: [
                        for (final t in [0.25, 0.50, 0.75])
                          Positioned(
                            left: barWidth * t - 0.75,
                            top: 0,
                            bottom: 0,
                            child: SizedBox(
                              width: 1.5,
                              child: ColoredBox(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Bottom controls ──────────────────────────────────────────────────────────

  Widget _buildBottomControls(
    BuildContext context,
    WidgetRef ref,
    String unit,
    int? selectedDrinkTypeId,
    AsyncValue<WaterLogModel?> lastLogAsync,
    int jumboAmount,
    UserProfileModel? profile,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final lastLog = lastLogAsync.valueOrNull;

    final drinkTypesAsync = ref.watch(drinkTypesProvider);
    final drinkTypes = drinkTypesAsync.valueOrNull ?? [];
    final selectedDrinkType = drinkTypes.isNotEmpty
        ? (selectedDrinkTypeId != null
            ? drinkTypes.firstWhere(
                (d) => d.id == selectedDrinkTypeId,
                orElse: () => drinkTypes.first,
              )
            : drinkTypes.first)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact =
            constraints.maxWidth < _compactButtonRowThreshold;
        final boxSize = isCompact ? _compactButtonSize : 60.0;
        final iconBarSize = isCompact ? _compactButtonSize - 8 : 40.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ── LEFT ZONE: two square glass buttons ───────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _GlassButton(
                    icon: Icons.local_drink_outlined,
                    label: unit == 'oz'
                        ? jumboAmount.toDouble().toHalfOzString()
                        : '$jumboAmount ml',
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (dialogContext) => Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.of(context).viewInsets.bottom,
                        ),
                        child: CupSizeSheet(
                          currentSizeMl: jumboAmount,
                          unit: unit,
                          onSizeSelected: (ml) {
                            ref
                                .read(jumboTapAmountProvider.notifier)
                                .setAmount(ml);
                          },
                        ),
                      ),
                    ),
                    boxSize: boxSize,
                  ),
                  const SizedBox(width: 8),
                  _GlassButton(
                    iconWidget: selectedDrinkType != null &&
                            selectedDrinkType.iconName.isNotEmpty
                        ? Text(
                            _emojiForDrink(selectedDrinkType.iconName),
                            style: const TextStyle(fontSize: 18),
                          )
                        : null,
                    icon: selectedDrinkType == null ||
                            selectedDrinkType.iconName.isEmpty
                        ? Icons.water_drop_outlined
                        : null,
                    iconColor: colorScheme.tertiary,
                    label: selectedDrinkType?.name ?? 'Drink',
                    onTap: drinkTypes.isEmpty
                        ? null
                        : () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(24)),
                              ),
                              builder: (dialogContext) => DrinkTypeSheet(
                                selectedDrinkTypeId:
                                    selectedDrinkTypeId ?? drinkTypes.first.id,
                                onDrinkSelected: (drink) {
                                  ref
                                      .read(
                                          selectedDrinkTypeIdProvider.notifier)
                                      .state = drink.id;
                                },
                              ),
                            ),
                    boxSize: boxSize,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: boxSize,
                    height: boxSize,
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.undo_outlined,
                        color: colorScheme.error,
                      ),
                      onPressed: lastLog != null
                          ? () => ref
                              .read(homeActionProvider.notifier)
                              .deleteLastLog()
                          : null,
                    ),
                  ),
                ],
              ),

              // ── RIGHT ZONE: vertical icon bar ────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.all(5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Climate — FIX B: opaque so full tap area is tappable
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showClimateDialog(context, ref, profile),
                      child: SizedBox(
                        width: iconBarSize,
                        height: iconBarSize,
                        child: const Center(
                          child: Icon(
                            Icons.wb_sunny_outlined,
                            size: 20,
                            color: Color.fromRGBO(255, 255, 255, 0.85),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 0.5,
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    // Activity — opaque so full tap area is tappable
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showActivityDialog(context, ref, profile),
                      child: SizedBox(
                        width: iconBarSize,
                        height: iconBarSize,
                        child: const Center(
                          child: Icon(
                            Icons.directions_run_outlined,
                            size: 20,
                            color: Color.fromRGBO(255, 255, 255, 0.85),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showClimateDialog(
      BuildContext context, WidgetRef ref, UserProfileModel? profile) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ClimateDialog(profile: profile),
    );
  }

  void _showActivityDialog(
      BuildContext context, WidgetRef ref, UserProfileModel? profile) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _ActivityDialog(profile: profile),
    );
  }

  // ── Skeleton ────────────────────────────────────────────────────────────────

  Widget _buildSkeleton(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(height: 60),
        Center(
          child: Container(
            width: 190,
            height: 160,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: List.generate(
              3,
              (i) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: i == 0 ? 0 : 5,
                    right: i == 2 ? 0 : 5,
                  ),
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _formatMl(int ml) {
    if (ml >= 1000) {
      final thousands = ml ~/ 1000;
      final remainder = ml % 1000;
      return '$thousands,${remainder.toString().padLeft(3, '0')}';
    }
    return ml.toString();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  Color _getProgressColor(BuildContext context, double pct) {
    if (pct >= 1.0) return AppColors.goalAchieved;
    if (pct >= 0.5) return Theme.of(context).colorScheme.primary;
    return AppColors.goalWarning;
  }

  String _emojiForDrink(String iconName) {
    return switch (iconName) {
      'water_drop' => '💧',
      'coffee' => '☕',
      'emoji_food_beverage' => '🍵',
      'local_drink' => '🥤',
      'sports_bar' => '🫧',
      _ => iconName,
    };
  }
}

// ── Glass button (left zone) ──────────────────────────────────────────────────

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.boxSize = 60,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;
  final double boxSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final double fontScale = MediaQuery.textScalerOf(context).scale(1.0);
    final bool isFontTooLarge = fontScale > 1.2;

    // 2. Check Physical Screen Width (Standard phones are 375-430dp, small screens are <= 360dp)
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final bool isScreenTooSmall = screenWidth <= 360;
    final bool shouldHideLabel =
        isFontTooLarge || isScreenTooSmall || boxSize < 60;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: boxSize,
        height: boxSize,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.35),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (iconWidget != null)
              iconWidget!
            else
              Icon(
                icon!,
                size: 20,
                color: iconColor ?? colorScheme.onPrimaryContainer,
              ),
              if (!shouldHideLabel) ...[
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child:Text(
                    label,
                    style: TextStyle(
                      fontSize: 8,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),
              ]
          ],
        ),
      ),
    );
  }
}

// ── Shared option tile (used by both dialogs) ─────────────────────────────────

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.emoji,
    required this.label,
    required this.multiplier,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final String multiplier;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primaryContainer
                : colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.tertiary.withValues(alpha: 0.5),
              width: isSelected ? 2.0 : 0.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Text(
                multiplier,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Climate dialog ────────────────────────────────────────────────────────────

class _ClimateDialog extends ConsumerStatefulWidget {
  const _ClimateDialog({required this.profile});
  final UserProfileModel? profile;

  @override
  ConsumerState<_ClimateDialog> createState() => _ClimateDialogState();
}

class _ClimateDialogState extends ConsumerState<_ClimateDialog> {
  late ClimateType _selected;
  bool _applyPermanently = false;

  static const _multipliers = {
    'cold': '×0.9',
    'moderate': '×1.0',
    'hot': '×1.15',
    'very_hot': '×1.30',
  };

  @override
  void initState() {
    super.initState();
    final override = ref.read(todayOverrideNotifierProvider);
    _selected = override?.climate ??
        ClimateType.fromRaw(widget.profile?.climateType ?? 'moderate');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final types = ClimateType.values;

    return AlertDialog(
      title: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          "Today's Weather",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 2×2 grid
              Row(
                children: [
                  _OptionTile(
                    emoji: types[0].emoji,
                    label: types[0].label,
                    multiplier: _multipliers[types[0].rawValue]!,
                    isSelected: _selected == types[0],
                    onTap: () => setState(() => _selected = types[0]),
                  ),
                  const SizedBox(width: 8),
                  _OptionTile(
                    emoji: types[1].emoji,
                    label: types[1].label,
                    multiplier: _multipliers[types[1].rawValue]!,
                    isSelected: _selected == types[1],
                    onTap: () => setState(() => _selected = types[1]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _OptionTile(
                    emoji: types[2].emoji,
                    label: types[2].label,
                    multiplier: _multipliers[types[2].rawValue]!,
                    isSelected: _selected == types[2],
                    onTap: () => setState(() => _selected = types[2]),
                  ),
                  const SizedBox(width: 8),
                  _OptionTile(
                    emoji: types[3].emoji,
                    label: types[3].label,
                    multiplier: _multipliers[types[3].rawValue]!,
                    isSelected: _selected == types[3],
                    onTap: () => setState(() => _selected = types[3]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Permanent toggle
              Row(
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Apply to profile permanently',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Changes your default, not just today',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _applyPermanently,
                    onChanged: (v) => setState(() => _applyPermanently = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Cancel'),
          ),
        ),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final notifier = ref.read(todayOverrideNotifierProvider.notifier);
            if (_applyPermanently) {
              await notifier.makeClimatePermanent(_selected);
            } else {
              await notifier.setClimate(_selected);
            }
            nav.pop();
          },
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Apply'),
          ),
        ),
      ],
    );
  }
}

// ── Activity dialog ───────────────────────────────────────────────────────────

class _ActivityDialog extends ConsumerStatefulWidget {
  const _ActivityDialog({required this.profile});
  final UserProfileModel? profile;

  @override
  ConsumerState<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends ConsumerState<_ActivityDialog> {
  late ActivityLevel _selected;
  bool _applyPermanently = false;

  static const _multipliers = {
    0: '×1.0',
    1: '×1.1',
    2: '×1.2',
    3: '×1.4',
  };

  static const _labels = {
    0: 'Sedentary',
    1: 'Light',
    2: 'Moderate',
    3: 'Active',
  };

  @override
  void initState() {
    super.initState();
    final override = ref.read(todayOverrideNotifierProvider);
    _selected = override?.activity ??
        ActivityLevel.fromRaw(widget.profile?.activityLevel ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final levels = ActivityLevel.values;

    return AlertDialog(
      title: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          "Today's activity",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 2×2 grid
              Row(
                children: [
                  _OptionTile(
                    emoji: levels[0].emoji,
                    label: _labels[levels[0].rawValue]!,
                    multiplier: _multipliers[levels[0].rawValue]!,
                    isSelected: _selected == levels[0],
                    onTap: () => setState(() => _selected = levels[0]),
                  ),
                  const SizedBox(width: 8),
                  _OptionTile(
                    emoji: levels[1].emoji,
                    label: _labels[levels[1].rawValue]!,
                    multiplier: _multipliers[levels[1].rawValue]!,
                    isSelected: _selected == levels[1],
                    onTap: () => setState(() => _selected = levels[1]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _OptionTile(
                    emoji: levels[2].emoji,
                    label: _labels[levels[2].rawValue]!,
                    multiplier: _multipliers[levels[2].rawValue]!,
                    isSelected: _selected == levels[2],
                    onTap: () => setState(() => _selected = levels[2]),
                  ),
                  const SizedBox(width: 8),
                  _OptionTile(
                    emoji: levels[3].emoji,
                    label: _labels[levels[3].rawValue]!,
                    multiplier: _multipliers[levels[3].rawValue]!,
                    isSelected: _selected == levels[3],
                    onTap: () => setState(() => _selected = levels[3]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Permanent toggle
              Row(
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Apply to profile permanently',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Changes your default, not just today',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _applyPermanently,
                    onChanged: (v) => setState(() => _applyPermanently = v),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Cancel'),
          ),
        ),
        FilledButton(
          onPressed: () async {
            final nav = Navigator.of(context);
            final notifier = ref.read(todayOverrideNotifierProvider.notifier);
            if (_applyPermanently) {
              await notifier.makeActivityPermanent(_selected);
            } else {
              await notifier.setActivity(_selected);
            }
            nav.pop();
          },
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Apply'),
          ),
        ),
      ],
    );
  }
}
