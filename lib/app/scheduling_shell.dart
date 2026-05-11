import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:scheduler/models/group_summary.dart';
import 'package:scheduler/screens/availability_screen.dart';
import 'package:scheduler/screens/group_join_create_screen.dart';
import 'package:scheduler/screens/home_screen.dart';
import 'package:scheduler/screens/profile_screen.dart';
import 'package:scheduler/services/group_repository.dart';

/// Scaffold with drawer (groups), bottom navigation, and tab bodies.
class SchedulingShell extends StatefulWidget {
  const SchedulingShell({super.key});

  @override
  State<SchedulingShell> createState() => _SchedulingShellState();
}

class _SchedulingShellState extends State<SchedulingShell> {
  int _tabIndex = 0;
  String? _highlightedGroupId;
  final _groupsRepo = GroupRepository();

  static const _titles = ['Home', 'Availability', 'Profile'];

  late final List<Widget> _pages = [
    const HomeScreen(),
    const AvailabilityScreen(),
    const ProfileScreen(),
  ];

  void _openDrawerSelectGroup(GroupSummary group) {
    setState(() => _highlightedGroupId = group.inviteCode);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Selected: ${group.name}')),
    );
  }

  Future<void> _openGroupJoinCreate() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => const GroupJoinCreateScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tabIndex]),
      ),
      drawer: Drawer(
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
                      'Your groups',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<GroupSummary>>(
                  stream: _groupsRepo.watchMyGroups(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Could not load groups:\n${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final groups = snapshot.data!;
                    if (groups.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No groups yet.\nTap below to join or create one.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }

                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                            'JOINED',
                            style: theme.textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.2,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        ...groups.map(
                          (g) => ListTile(
                            leading: Icon(
                              Icons.group_rounded,
                              color: _highlightedGroupId == g.inviteCode
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                            title: Text(g.name),
                            subtitle: Text(
                              '${g.memberCount} members · ${g.inviteCode}',
                            ),
                            selected: _highlightedGroupId == g.inviteCode,
                            onTap: () => _openDrawerSelectGroup(g),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('Join or create group'),
                subtitle: const Text('Invite code'),
                onTap: _openGroupJoinCreate,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Availability',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
