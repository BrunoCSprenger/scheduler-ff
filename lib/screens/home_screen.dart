import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:scheduler/models/group_summary.dart';
import 'package:scheduler/services/availability_service.dart';
import 'package:scheduler/services/group_repository.dart';
import 'package:scheduler/screens/group_detail_screen.dart';

// Shows upcoming scheduled meetings from groups

/// Main landing tab — scheduling UI comes later.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = GroupRepository();
    final availabilityService = AvailabilityService();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overview',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your schedule and shared availability will live here. '
                  'Use the menu to switch groups.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Upcoming meetings',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverToBoxAdapter(
            child: StreamBuilder<String>(
              stream: availabilityService.watchCurrentUserTimezone(),
              builder: (context, timezoneSnap) {
                final timezone = timezoneSnap.data;
                if (timezone == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                return StreamBuilder<List<GroupSummary>>(
                  stream: repo.watchMyGroups(viewerTimezone: timezone),
                  builder: (context, groupsSnap) {
                    final list = groupsSnap.data ?? const <GroupSummary>[];
                    final meetings =
                        list.where((g) => g.meetingStart != null).toList()
                          ..sort(
                            (a, b) =>
                                a.meetingStart!.compareTo(b.meetingStart!),
                          );

                    if (meetings.isEmpty) {
                      return Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'No upcoming meetings scheduled.',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }

                    return Card(
                      elevation: 0,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reminder',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...meetings.map((g) {
                              final dt = g.meetingStart!;
                              final dur = g.meetingDurationMinutes ?? 0;
                              final end = dt.add(Duration(minutes: dur));
                              final meetingText = g.role == 'owner'
                                  ? '${DateFormat.yMMMd().format(dt)} ${DateFormat.jm().format(dt)}–${DateFormat.jm().format(end)}'
                                  : '${DateFormat.yMMMd().add_jm().format(dt)} • $dur minutes';

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            GroupDetailScreen(group: g),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 4,
                                    ),
                                    child: Text(
                                      '${g.name}: $meetingText',
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor:
                                                theme.colorScheme.primary,
                                          ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
