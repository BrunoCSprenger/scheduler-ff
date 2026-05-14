import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:scheduler/services/availability_service.dart';
import 'package:scheduler/services/group_repository.dart';
import 'package:scheduler/services/timezone_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _availabilityService = AvailabilityService();
  final _timezoneSearchController = TextEditingController();
  List<String> _timezones = const [];
  String? _selectedTimezone;
  bool _loadingTimezone = true;
  bool _savingTimezone = false;

  @override
  void initState() {
    super.initState();
    _loadTimezoneSettings();
  }

  Future<void> _loadTimezoneSettings() async {
    await TimezoneService.ensureInitialized();
    final zones = TimezoneService.allTimezoneNames();
    final current = await _availabilityService.getCurrentUserTimezone();
    if (!mounted) return;
    setState(() {
      _timezones = zones;
      _selectedTimezone = current;
      _loadingTimezone = false;
    });
  }

  Future<void> _saveTimezone(String timezone) async {
    setState(() => _savingTimezone = true);
    try {
      await _availabilityService.saveUserTimezone(timezone);
      if (!mounted) return;
      setState(() => _selectedTimezone = timezone);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Timezone saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save timezone: $e')));
    } finally {
      if (mounted) setState(() => _savingTimezone = false);
    }
  }

  @override
  void dispose() {
    _timezoneSearchController.dispose();
    super.dispose();
  }

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Signed out')));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This will remove your account data from the app and leave all groups you are in. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (firstConfirm != true || !context.mounted) return;

    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Really delete account?'),
        content: const Text(
          'Press delete one more time to permanently remove this account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );

    if (secondConfirm != true || !context.mounted) return;

    try {
      await GroupRepository().deleteCurrentUserAccount();
      await FirebaseAuth.instance.currentUser?.delete();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account deleted')));
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete account: ${e.message ?? e.code}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete account: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final searchQuery = _timezoneSearchController.text.trim().toLowerCase();
    final filteredTimezones = searchQuery.isEmpty
        ? _timezones
        : _timezones.where((zone) {
            final label = TimezoneService.formatTimezoneLabel(
              zone,
            ).toLowerCase();
            return zone.toLowerCase().contains(searchQuery) ||
                label.contains(searchQuery);
          }).toList();
    final selectedTimezone = filteredTimezones.contains(_selectedTimezone)
        ? _selectedTimezone
        : null;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.person_rounded, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Account',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          user?.email ?? 'Not signed in',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Timezone',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _timezoneSearchController,
          decoration: InputDecoration(
            labelText: 'Search timezones',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _timezoneSearchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _timezoneSearchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear_rounded),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        if (_loadingTimezone)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          )
        else
          DropdownButtonFormField<String>(
            value: selectedTimezone,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Select timezone',
            ),
            items: filteredTimezones
                .map(
                  (zone) => DropdownMenuItem<String>(
                    value: zone,
                    child: Text(TimezoneService.formatTimezoneLabel(zone)),
                  ),
                )
                .toList(),
            hint: Text(
              filteredTimezones.isEmpty
                  ? 'No timezones match your search'
                  : 'Choose timezone',
            ),
            onChanged: _savingTimezone || _timezones.isEmpty
                ? null
                : (value) {
                    if (value == null) return;
                    _saveTimezone(value);
                  },
          ),
        const SizedBox(height: 8),
        Text(
          'Your availability and meeting times will be shown in this timezone.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => _signOut(context),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _deleteAccount(context),
          icon: const Icon(Icons.delete_forever_rounded),
          label: const Text('Delete account'),
        ),
      ],
    );
  }
}
