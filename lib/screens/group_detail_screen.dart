import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:scheduler/models/group_summary.dart';
import 'package:scheduler/services/availability_service.dart';
import 'package:scheduler/services/group_repository.dart';
import 'package:scheduler/services/timezone_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({required this.group, super.key});

  final GroupSummary group;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final _availabilityService = AvailabilityService();
  final _groupRepository = GroupRepository();
  final _auth = FirebaseAuth.instance;

  DateTime? _currentWeekStart;
  String? _viewerTimezone;
  late String _groupName;
  DateTime? _groupMeetingStart;
  int? _groupMeetingDurationMinutes;
  StreamSubscription<Map<String, Map<int, List<RangeValues>>>?>? _myAvailSub;
  StreamSubscription<String>? _timezoneSub;
  Map<int, List<RangeValues>> _dayChunks = {
    for (var day = 0; day < 7; day++) day: <RangeValues>[],
  };
  int? _expandedDay;
  bool _saving = false;
  bool _leaving = false;
  bool _renaming = false;
  bool _isSlidingChunk = false;
  bool _overlapWarnedThisSlide = false;

  static const List<int> _meetingMinuteChunks = [
    0,
    5,
    10,
    15,
    20,
    25,
    30,
    35,
    40,
    45,
    50,
    55,
  ];

  @override
  void initState() {
    super.initState();
    _groupName = widget.group.name;
    _loadViewerTimezone();
    _loadGroupMeta();
  }

  DateTime get _currentWeekStartValue =>
      _currentWeekStart ??= _viewerTimezone == null
      ? _normalizeToMonday(DateTime.now())
      : TimezoneService.currentWeekMonday(_viewerTimezone!);

  String get _currentWeekId => _getWeekId(_currentWeekStartValue);

  Future<void> _loadViewerTimezone() async {
    _timezoneSub?.cancel();
    _timezoneSub = _availabilityService.watchCurrentUserTimezone().listen((
      timezone,
    ) {
      if (!mounted) return;
      setState(() {
        final previousTimezone = _viewerTimezone;
        _viewerTimezone = timezone;
        if (_currentWeekStart == null || previousTimezone == null) {
          _currentWeekStart = TimezoneService.currentWeekMonday(timezone);
        }
      });
      _subscribeToMyAvailability();
    });
  }

  void _subscribeToMyAvailability() {
    final viewerTimezone = _viewerTimezone;
    if (viewerTimezone == null) return;
    _myAvailSub?.cancel();
    _myAvailSub = _availabilityService
        .watchGroupAvailability(
          inviteCode: widget.group.inviteCode,
          weekId: _currentWeekId,
          viewerTimezone: viewerTimezone,
        )
        .listen((map) {
          final uid = _auth.currentUser?.uid;
          if (uid == null) return;
          final myChunks = map[uid] ?? <int, List<RangeValues>>{};
          setState(() {
            _dayChunks = {
              for (var day = 0; day < 7; day++)
                day: List<RangeValues>.from(myChunks[day] ?? <RangeValues>[]),
            };
          });
        }, onError: (_) {});
  }

  Future<void> _loadGroupMeta() async {
    try {
      final doc = await _groupRepository.getGroupDoc(widget.group.inviteCode);
      if (!doc.exists) return;
      final raw = doc.data()?['meeting'];
      if (raw is Map<String, dynamic>) {
        final ts = raw['start'];
        DateTime? start;
        if (ts is Timestamp) start = ts.toDate();
        setState(() {
          _groupMeetingStart = start;
          _groupMeetingDurationMinutes = (raw['durationMinutes'] as num?)
              ?.toInt();
        });
      }
    } catch (_) {}
  }

  bool _isCurrentUserOwner(List<GroupMember> members) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    return members.any((m) => m.uid == uid && m.role == 'owner');
  }

  Future<void> _renameGroup() async {
    final controller = TextEditingController(text: _groupName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Do not dispose controller here — disposing while the dialog's
    // widget tree may still reference it can trigger framework assertions.
    // The controller will be garbage-collected after this function exits
    // and the dialog is removed.

    if (nextName == null) return;
    final trimmed = nextName.trim();
    if (trimmed.isEmpty || trimmed == _groupName) return;

    setState(() => _renaming = true);
    try {
      await _groupRepository.renameGroup(
        rawCode: widget.group.inviteCode,
        newName: trimmed,
      );
      if (!mounted) return;
      setState(() {
        _groupName = trimmed;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group renamed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not rename group: $e')));
    } finally {
      if (mounted) setState(() => _renaming = false);
    }
  }

  String _getWeekId(DateTime date) {
    final weekStart = _normalizeToMonday(date);
    final weekNum =
        ((weekStart.difference(DateTime(weekStart.year, 1, 4)).inDays) ~/ 7) +
        1;
    return '${weekStart.year}-W${weekNum.toString().padLeft(2, '0')}';
  }

  DateTime _normalizeToMonday(DateTime date) {
    final localDate = DateTime(date.year, date.month, date.day);
    return localDate.subtract(
      Duration(days: localDate.weekday - DateTime.monday),
    );
  }

  DateTime _shiftDateByDays(DateTime date, int days) {
    return DateTime(date.year, date.month, date.day + days);
  }

  DateTime _meetingStartLocal() {
    final start = _groupMeetingStart;
    if (start == null) return DateTime.now();
    return start.isUtc ? start.toLocal() : start;
  }

  void _resetWeek(DateTime monday) {
    _currentWeekStart = _normalizeToMonday(monday);
    _dayChunks = {for (var day = 0; day < 7; day++) day: <RangeValues>[]};
    _expandedDay = null;
    _subscribeToMyAvailability();
  }

  String _formatTime(double value) {
    final h = value.floor();
    final minute = ((value - h) * 60).round();
    final mm = minute == 0 ? '00' : minute.toString().padLeft(2, '0');
    return '${h.toString().padLeft(2, '0')}:$mm';
  }

  String _formatRange(RangeValues range) {
    if ((range.start - 0.0).abs() < 0.001 && (range.end - 24.0).abs() < 0.001) {
      return 'All day';
    }
    return '${_formatTime(range.start)}-${_formatTime(range.end)}';
  }

  String _formatRanges(List<RangeValues> ranges) {
    if (ranges.isEmpty) return 'No availability';
    final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
    return sorted.map(_formatRange).join(' + ');
  }

  RangeValues _snapHalfHourRange(RangeValues values) {
    double snap(double v) => (v * 2).round() / 2.0;
    var start = snap(values.start.clamp(0.0, 24.0));
    var end = snap(values.end.clamp(0.0, 24.0));
    if (end <= start) {
      end = (start + 0.5).clamp(0.5, 24.0);
      start = (end - 0.5).clamp(0.0, 23.5);
    }
    return RangeValues(start, end);
  }

  Map<int, List<RangeValues>> _mergeConnectedChunks(
    Map<int, List<RangeValues>> chunksByDay,
  ) {
    const epsilon = 0.0001;
    final mergedByDay = <int, List<RangeValues>>{};

    for (var day = 0; day < 7; day++) {
      final source = [...(chunksByDay[day] ?? const <RangeValues>[])];
      source.sort((a, b) => a.start.compareTo(b.start));

      if (source.isEmpty) {
        mergedByDay[day] = <RangeValues>[];
        continue;
      }

      final merged = <RangeValues>[];
      var current = _snapHalfHourRange(source.first);

      for (final raw in source.skip(1)) {
        final next = _snapHalfHourRange(raw);
        if (next.start <= current.end + epsilon) {
          current = RangeValues(
            current.start,
            next.end > current.end ? next.end : current.end,
          );
        } else {
          merged.add(current);
          current = next;
        }
      }

      merged.add(current);
      mergedByDay[day] = merged;
    }

    return mergedByDay;
  }

  bool _rangesOverlap(RangeValues a, RangeValues b) {
    return a.start < b.end && b.start < a.end;
  }

  bool _canPlaceChunk({
    required int dayIndex,
    required RangeValues candidate,
    int? ignoreIndex,
  }) {
    final existing = _dayChunks[dayIndex] ?? const <RangeValues>[];
    for (var i = 0; i < existing.length; i++) {
      if (ignoreIndex != null && i == ignoreIndex) continue;
      if (_rangesOverlap(candidate, existing[i])) {
        return false;
      }
    }
    return true;
  }

  void _updateChunkNoOverlap(int dayIndex, int chunkIndex, RangeValues values) {
    final candidate = _snapHalfHourRange(values);
    if (!_canPlaceChunk(
      dayIndex: dayIndex,
      candidate: candidate,
      ignoreIndex: chunkIndex,
    )) {
      final shouldWarn = !_isSlidingChunk || !_overlapWarnedThisSlide;
      if (shouldWarn) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chunks cannot overlap on the same day.'),
          ),
        );
        if (_isSlidingChunk) {
          _overlapWarnedThisSlide = true;
        }
      }
      return;
    }

    setState(() {
      _dayChunks[dayIndex]![chunkIndex] = candidate;
    });
  }

  void _addChunkNoOverlap(int dayIndex) {
    for (var slot = 0.0; slot <= 23.0; slot += 0.5) {
      final candidate = RangeValues(slot, slot + 1.0);
      if (_canPlaceChunk(dayIndex: dayIndex, candidate: candidate)) {
        setState(() {
          _dayChunks[dayIndex]!.add(candidate);
        });
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No non-overlapping slot left on this day.'),
      ),
    );
  }

  String _memberInitials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    final first = parts.first.isNotEmpty ? parts.first[0] : '?';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  String _dayName(int index) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[index];
  }

  String _dayShortName(int index) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[index];
  }

  int _dayMemberCount(
    Map<String, Map<int, List<RangeValues>>> availability,
    int dayIndex,
    int halfHourIndex,
  ) {
    // halfHourIndex: 0..47 where each bin represents [i*0.5, (i+1)*0.5)
    final start = halfHourIndex * 0.5;
    final end = start + 0.5;
    var count = 0;
    for (final entry in availability.entries) {
      final rangesForDay = entry.value[dayIndex] ?? const <RangeValues>[];
      final intersects = rangesForDay.any((range) {
        return range.start < end && range.end > start;
      });
      if (intersects) count++;
    }
    return count;
  }

  bool _isMeetingCell(DateTime weekMonday, int dayIndex, int halfHourIndex) {
    final start = _groupMeetingStart == null ? null : _meetingStartLocal();
    final duration = _groupMeetingDurationMinutes;
    if (start == null || duration == null || duration <= 0) return false;

    final cellDay = weekMonday.add(Duration(days: dayIndex));
    if (cellDay.year != start.year ||
        cellDay.month != start.month ||
        cellDay.day != start.day) {
      return false;
    }

    final cellStartMinutes = halfHourIndex * 30;
    final cellEndMinutes = cellStartMinutes + 30;
    final meetingStartMinutes = (start.hour * 60) + start.minute;
    final meetingEndMinutes = meetingStartMinutes + duration;

    return meetingStartMinutes < cellEndMinutes &&
        meetingEndMinutes > cellStartMinutes;
  }

  Widget _buildAvailabilityTable(
    BuildContext context,
    Map<String, Map<int, List<RangeValues>>> availability,
    int totalMembers,
    DateTime weekMonday,
  ) {
    final theme = Theme.of(context);
    final members = totalMembers <= 0 ? 1 : totalMembers;

    final rows = <TableRow>[
      TableRow(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        children: [
          Container(
            height: 28,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Time',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (var day = 0; day < 7; day++)
            Container(
              height: 28,
              alignment: Alignment.center,
              child: Text(
                _dayShortName(day),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    ];

    for (var halfHour = 0; halfHour < 48; halfHour++) {
      final isHourStart = halfHour % 2 == 0;
      final timeValue = halfHour * 0.5;
      final borderColor = isHourStart
          ? theme.colorScheme.outline
          : theme.colorScheme.outlineVariant;

      rows.add(
        TableRow(
          children: [
            Container(
              height: 14,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: borderColor,
                    width: isHourStart ? 1.2 : 0.7,
                  ),
                ),
              ),
              child: Text(
                isHourStart ? _formatTime(timeValue) : '',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (var day = 0; day < 7; day++)
              Builder(
                builder: (context) {
                  final count = _dayMemberCount(availability, day, halfHour);
                  final ratio = (count / members).clamp(0.0, 1.0);
                  final isMeeting = _isMeetingCell(weekMonday, day, halfHour);
                  final color = isMeeting
                      ? const Color(0xFFD32F2F)
                      : Color.lerp(
                              const Color(0xFFE8F5E9),
                              const Color(0xFF2E7D32),
                              ratio,
                            ) ??
                            const Color(0xFFE8F5E9);

                  return Tooltip(
                    message:
                        '${_dayName(day)} ${_formatTime(timeValue)} · $count/$members members',
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        border: Border(
                          top: BorderSide(
                            color: borderColor,
                            width: isHourStart ? 1.2 : 0.7,
                          ),
                          left: BorderSide(
                            color: isMeeting
                                ? const Color(0xFFB71C1C)
                                : theme.colorScheme.outlineVariant,
                            width: isMeeting ? 1.2 : 0.7,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final timeWidth = (totalWidth * 0.18).clamp(52.0, 72.0);
        final dayWidth = (totalWidth - timeWidth) / 7;

        return Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            0: FixedColumnWidth(timeWidth),
            for (var i = 1; i <= 7; i++) i: FixedColumnWidth(dayWidth),
          },
          children: rows,
        );
      },
    );
  }

  // Simple table visualizer: 7 day columns, 48 half-hour rows.

  Future<void> _saveAvailability() async {
    setState(() => _saving = true);
    try {
      final merged = _mergeConnectedChunks(_dayChunks);
      setState(() {
        _dayChunks = merged;
      });

      await _availabilityService.saveAvailability(
        inviteCode: widget.group.inviteCode,
        weekId: _currentWeekId,
        dayChunks: merged,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Availability saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leaveGroup() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave group?'),
        content: const Text(
          'You will be removed from this group. If you are the last member, the group will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (shouldLeave != true) return;

    setState(() => _leaving = true);
    try {
      final deleted = await _groupRepository.leaveGroup(
        widget.group.inviteCode,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text(deleted ? 'Group deleted' : 'Left group')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not leave group: $e')));
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _setMeeting() async {
    final initialMeetingStart = _meetingStartLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(
        initialMeetingStart.year,
        initialMeetingStart.month,
        initialMeetingStart.day,
      ),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: _groupMeetingStart != null
          ? TimeOfDay.fromDateTime(_meetingStartLocal())
          : TimeOfDay(hour: 12, minute: 0),
    );
    if (time == null) return;

    final chosen = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final duration = await showDialog<int>(
      context: context,
      builder: (context) => _MeetingDurationDialog(
        initialHours: _groupMeetingDurationMinutes == null
            ? 1
            : (_groupMeetingDurationMinutes! ~/ 60).clamp(0, 23),
        initialMinutes: _groupMeetingDurationMinutes == null
            ? 0
            : _meetingMinuteChunks.contains(_groupMeetingDurationMinutes! % 60)
            ? _groupMeetingDurationMinutes! % 60
            : ((_groupMeetingDurationMinutes! % 60) ~/ 5) * 5,
      ),
    );
    if (duration == null) return;

    setState(() => _renaming = true);
    try {
      await _groupRepository.setGroupMeeting(
        rawCode: widget.group.inviteCode,
        start: chosen.toUtc(),
        durationMinutes: duration,
      );
      if (!mounted) return;
      setState(() {
        _groupMeetingStart = chosen.toUtc();
        _groupMeetingDurationMinutes = duration;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Meeting set')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not set meeting: $e')));
    } finally {
      if (mounted) setState(() => _renaming = false);
    }
  }

  Future<void> _clearMeeting() async {
    setState(() => _renaming = true);
    try {
      await _groupRepository.clearGroupMeeting(
        rawCode: widget.group.inviteCode,
      );
      if (!mounted) return;
      setState(() {
        _groupMeetingStart = null;
        _groupMeetingDurationMinutes = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Meeting cleared')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not clear meeting: $e')));
    } finally {
      if (mounted) setState(() => _renaming = false);
    }
  }

  void _previousWeek() {
    final monday = _shiftDateByDays(_currentWeekStartValue, -7);
    setState(() => _resetWeek(monday));
  }

  void _nextWeek() {
    final monday = _shiftDateByDays(_currentWeekStartValue, 7);
    setState(() => _resetWeek(monday));
  }

  @override
  void dispose() {
    _timezoneSub?.cancel();
    _myAvailSub?.cancel();
    super.dispose();
  }

  Drawer _buildMembersDrawer(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.35,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Members',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.group.inviteCode,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<GroupMember>>(
                stream: _availabilityService.watchGroupMembers(
                  inviteCode: widget.group.inviteCode,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Could not load members:\n${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final members = snapshot.data!;
                  if (members.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No members yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final member = members[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Text(
                            _memberInitials(member.displayName),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        title: Text(member.displayName),
                        subtitle: Text(member.role),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StreamBuilder<List<GroupMember>>(
                    stream: _availabilityService.watchGroupMembers(
                      inviteCode: widget.group.inviteCode,
                    ),
                    builder: (context, snapshot) {
                      final members = snapshot.data ?? const <GroupMember>[];
                      final isOwner = _isCurrentUserOwner(members);
                      if (!isOwner) return const SizedBox.shrink();

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: OutlinedButton.icon(
                              onPressed: _renaming ? null : _renameGroup,
                              icon: _renaming
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.edit_rounded),
                              label: const Text('Rename group'),
                            ),
                          ),
                          // Meeting controls
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_groupMeetingStart != null) ...[
                                  Builder(
                                    builder: (context) {
                                      final dtLocal = _meetingStartLocal();
                                      final dur =
                                          _groupMeetingDurationMinutes ?? 0;
                                      final end = dtLocal.add(
                                        Duration(minutes: dur),
                                      );
                                      final meetingText =
                                          '${DateFormat.yMMMd().format(dtLocal)} ${DateFormat.jm().format(dtLocal)}–${DateFormat.jm().format(end)}';
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Scheduled: $meetingText',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                                OutlinedButton.icon(
                                  onPressed: _setMeeting,
                                  icon: const Icon(Icons.schedule_rounded),
                                  label: const Text('Set meeting'),
                                ),
                                if (_groupMeetingStart != null)
                                  TextButton.icon(
                                    onPressed: _clearMeeting,
                                    icon: const Icon(Icons.clear_rounded),
                                    label: const Text('Clear meeting'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _leaving ? null : _leaveGroup,
                    icon: _leaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                    label: const Text('Leave group'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(BuildContext context, int dayIndex, DateTime date) {
    final theme = Theme.of(context);
    final isExpanded = _expandedDay == dayIndex;
    final chunks = _dayChunks[dayIndex] ?? const <RangeValues>[];
    final summary = _formatRanges(chunks);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _expandedDay = isExpanded ? null : dayIndex;
            });
          },
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _dayName(dayIndex),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          DateFormat('MMM d').format(date),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (chunks.isEmpty) ...[
                        Text(
                          'No chunks yet. Add one and drag it to size.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      for (var i = 0; i < chunks.length; i++) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Chunk ${i + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove chunk',
                              onPressed: () {
                                setState(() {
                                  _dayChunks[dayIndex]!.removeAt(i);
                                });
                              },
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '00:00',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '24:00',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        RangeSlider(
                          min: 0,
                          max: 24,
                          divisions: 48,
                          values: chunks[i],
                          labels: RangeLabels(
                            _formatTime(chunks[i].start),
                            _formatTime(chunks[i].end),
                          ),
                          onChangeStart: (_) {
                            _isSlidingChunk = true;
                            _overlapWarnedThisSlide = false;
                          },
                          onChanged: (values) {
                            _updateChunkNoOverlap(dayIndex, i, values);
                          },
                          onChangeEnd: (_) {
                            _isSlidingChunk = false;
                            _overlapWarnedThisSlide = false;
                          },
                        ),
                        Text(
                          _formatRange(chunks[i]),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (i < chunks.length - 1) const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _addChunkNoOverlap(dayIndex),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add chunk'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_viewerTimezone == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final monday = _currentWeekStartValue;

    return Scaffold(
      appBar: AppBar(
        title: Text(_groupName),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              tooltip: 'Members',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _buildMembersDrawer(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Tap a day, then drag one or more chunks to set your availability.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: _previousWeek,
                ),
                Column(
                  children: [
                    Text(
                      'Week of ${DateFormat('MMM d').format(monday)}',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      _currentWeekId,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: _nextWeek,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: List.generate(
                7,
                (dayIndex) => _buildDayCard(
                  context,
                  dayIndex,
                  monday.add(Duration(days: dayIndex)),
                ),
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Group Availability',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: StreamBuilder<List<GroupMember>>(
              stream: _availabilityService.watchGroupMembers(
                inviteCode: widget.group.inviteCode,
              ),
              builder: (context, membersSnapshot) {
                final members = membersSnapshot.data ?? const <GroupMember>[];
                final membersById = {
                  for (final member in members) member.uid: member,
                };

                return StreamBuilder<Map<String, Map<int, List<RangeValues>>>>(
                  stream: _availabilityService.watchGroupAvailability(
                    inviteCode: widget.group.inviteCode,
                    weekId: _currentWeekId,
                    viewerTimezone: _viewerTimezone!,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final availability = snapshot.data!;
                    if (availability.isEmpty) {
                      return Text(
                        'No availability submitted yet',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAvailabilityTable(
                          context,
                          availability,
                          members.length,
                          monday,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Member Availability',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...availability.entries.map((entry) {
                          final member = membersById[entry.key];
                          final displayName = member?.displayName ?? entry.key;
                          final dayChunks = entry.value;
                          final dayLines = List<String>.generate(7, (day) {
                            final ranges =
                                dayChunks[day] ?? const <RangeValues>[];
                            return '${_dayShortName(day)}: ${_formatRanges(ranges)}';
                          });

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                child: Text(
                                  _memberInitials(displayName),
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              title: Text(displayName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final line in dayLines) Text(line),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _saveAvailability,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save My Availability'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingDurationDialog extends StatefulWidget {
  const _MeetingDurationDialog({
    required this.initialHours,
    required this.initialMinutes,
  });

  final int initialHours;
  final int initialMinutes;

  @override
  State<_MeetingDurationDialog> createState() => _MeetingDurationDialogState();
}

class _MeetingDurationDialogState extends State<_MeetingDurationDialog> {
  int _hours = 0;
  int _minutes = 0;

  static const List<int> _minuteChunks = [
    0,
    5,
    10,
    15,
    20,
    25,
    30,
    35,
    40,
    45,
    50,
    55,
  ];

  @override
  void initState() {
    super.initState();
    _hours = widget.initialHours;
    _minutes = _minuteChunks.contains(widget.initialMinutes)
        ? widget.initialMinutes
        : ((_minuteChunks.firstWhere(
            (m) => m >= widget.initialMinutes,
            orElse: () => 0,
          )));
  }

  @override
  Widget build(BuildContext context) {
    final totalMinutes = (_hours * 60) + _minutes;

    return AlertDialog(
      title: const Text('Meeting duration'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _hours,
                  decoration: const InputDecoration(
                    labelText: 'Hours',
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(24, (index) => index)
                      .map(
                        (value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value h'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _hours = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _minutes,
                  decoration: const InputDecoration(
                    labelText: 'Minutes',
                    border: OutlineInputBorder(),
                  ),
                  items: _minuteChunks
                      .map(
                        (value) => DropdownMenuItem<int>(
                          value: value,
                          child: Text('$value m'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _minutes = value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Total: ${totalMinutes ~/ 60}h ${totalMinutes % 60}m',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: totalMinutes <= 0
              ? null
              : () => Navigator.of(context).pop(totalMinutes),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
