import 'package:flutter/material.dart';
import 'package:scheduler/services/availability_service.dart';

/// Availability tab — edit your base (global) availability that will be used
/// as the default availability for any group you join. This is a single-week
/// template that repeats for all weeks.
class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  final _service = AvailabilityService();

  Map<int, List<RangeValues>> _dayChunks = {
    for (var day = 0; day < 7; day++) day: <RangeValues>[],
  };

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _service.watchBaseAvailability().listen((chunks) {
      setState(() {
        _dayChunks = {
          for (var day = 0; day < 7; day++)
            day: List<RangeValues>.from(chunks[day] ?? <RangeValues>[]),
        };
      });
    });
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
    return '${_formatTime(range.start)}–${_formatTime(range.end)}';
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

  Future<void> _addRange(int day) async {
    final startTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (startTime == null) return;
    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (startTime.hour + 1) % 24,
        minute: startTime.minute,
      ),
    );
    if (endTime == null) return;

    final start = startTime.hour + startTime.minute / 60.0;
    final end = endTime.hour + endTime.minute / 60.0;
    setState(() {
      _dayChunks[day] = [...(_dayChunks[day] ?? []), RangeValues(start, end)];
    });
    await _saveBase();
  }

  Future<void> _removeRange(int day, int index) async {
    setState(() {
      final list = List<RangeValues>.from(_dayChunks[day] ?? <RangeValues>[]);
      list.removeAt(index);
      _dayChunks[day] = list;
    });
    await _saveBase();
  }

  Future<void> _saveBase() async {
    setState(() => _saving = true);
    try {
      await _service.saveBaseAvailability(dayChunks: _dayChunks);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Base availability saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Base availability (applies to all groups and weeks)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (var day = 0; day < 7; day++)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_dayName(day), style: theme.textTheme.titleSmall),
                      TextButton.icon(
                        onPressed: () => _addRange(day),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if ((_dayChunks[day] ?? []).isEmpty)
                    Text(
                      'No availability set',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (var i = 0; i < (_dayChunks[day] ?? []).length; i++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(_formatRange(_dayChunks[day]![i])),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => _removeRange(day, i),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _saveBase,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_rounded),
          label: const Text('Save base availability'),
        ),
      ],
    );
  }
}
