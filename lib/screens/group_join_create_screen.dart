import 'package:flutter/material.dart';
import 'package:scheduler/services/group_repository.dart';
import 'package:scheduler/utils/invite_code.dart';

class GroupJoinCreateScreen extends StatefulWidget {
  const GroupJoinCreateScreen({super.key});

  @override
  State<GroupJoinCreateScreen> createState() => _GroupJoinCreateScreenState();
}

class _GroupJoinCreateScreenState extends State<GroupJoinCreateScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _repo = GroupRepository();

  final _joinCode = TextEditingController();
  final _createName = TextEditingController();
  final _createCode = TextEditingController();

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _joinCode.dispose();
    _createName.dispose();
    _createCode.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await _repo.joinGroup(_joinCode.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final code = normalizeInviteCode(_joinCode.text);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('Joined group $code')),
      );
    } on GroupNotFoundException {
      _toast('No group found for that code.');
    } on AlreadyMemberException {
      _toast('You are already in that group.');
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    final name = _createName.text.trim();
    if (name.isEmpty) {
      _toast('Enter a group name.');
      return;
    }

    final code = normalizeInviteCode(_createCode.text);
    if (!isValidInviteCodeFormat(code)) {
      _toast(
        'Enter a valid 6-character code (1–9, A–Z except O), or generate one.',
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await _repo.createGroup(name: name, inviteCode: code);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('Created "$name" · invite $code')),
      );
    } on GroupInviteTakenException {
      _toast('That invite code is already taken — generate another.');
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateCode() async {
    FocusScope.of(context).unfocus();
    final name = _createName.text.trim();
    if (name.isEmpty) {
      _toast('Enter a group name before generating a code.');
      return;
    }

    setState(() => _busy = true);
    try {
      final code = await _repo.createGroupWithGeneratedCode(name: name);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(content: Text('Created "$name" · invite $code')),
      );
    } catch (e) {
      _toast(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Join'),
            Tab(text: 'Create'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [
              _JoinTab(
                controller: _joinCode,
                busy: _busy,
                onSubmit: _join,
              ),
              _CreateTab(
                nameController: _createName,
                codeController: _createCode,
                busy: _busy,
                onSubmitManual: _create,
                onGenerate: _generateCode,
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: AbsorbPointer(
                child: Container(
                  color: const Color(0x33000000),
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _JoinTab extends StatelessWidget {
  const _JoinTab({
    required this.controller,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Enter the 6-character invite code.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          enabled: !busy,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: kInviteCodeLength,
          decoration: const InputDecoration(
            labelText: 'Invite code',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          inputFormatters: [
            InviteCodeTextFormatter(stripInvalid: true),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : onSubmit,
          child: const Text('Join group'),
        ),
      ],
    );
  }
}

class _CreateTab extends StatelessWidget {
  const _CreateTab({
    required this.nameController,
    required this.codeController,
    required this.busy,
    required this.onSubmitManual,
    required this.onGenerate,
  });

  final TextEditingController nameController;
  final TextEditingController codeController;
  final bool busy;
  final VoidCallback onSubmitManual;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Pick a name and either type a custom invite code or generate one.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: nameController,
          enabled: !busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Group name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: codeController,
          enabled: !busy,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: kInviteCodeLength,
          decoration: InputDecoration(
            labelText: 'Invite code (optional if you generate)',
            border: const OutlineInputBorder(),
            counterText: '',
            suffixIcon: IconButton(
              tooltip: 'Generate random code',
              onPressed: busy ? null : onGenerate,
              icon: const Icon(Icons.casino_rounded),
            ),
          ),
          inputFormatters: [
            InviteCodeTextFormatter(stripInvalid: true),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Characters: 1–9 and A–Z except O. Tap the dice to generate and create.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : onSubmitManual,
          child: const Text('Create with typed code'),
        ),
      ],
    );
  }
}
