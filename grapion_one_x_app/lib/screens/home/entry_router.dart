// //Added By Nikhil 21Nov26 23:30 For login routing by module role (0 → gate, 1 → straight in, 2+ → picker), invites, business setup
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../modules/gym/gym_home_screen.dart';
import '../../services/api_client.dart';
import '../../services/push_service.dart'; //Added By Nikhil 22Nov26 00:10 For device registration
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import '../auth/login_screen.dart';
import '../profile/profile_screen.dart';
import '../subscription/receipt_gate_screen.dart';
import '../../widgets/announcement_banner.dart'; //Added By Nikhil 22Nov26 08:35 For announcement banners

/// Decides where a signed-in (non-admin) user lands. Call after login / when access changes.
Future<void> routeAfterLogin(BuildContext context) async {
  PushService.registerDevice(); //Added By Nikhil 22Nov26 00:10 For push notifications (fire-and-forget)
  final res = await apiClient.get('/workspaces/my-entries');
  if (!context.mounted) return;
  if (res.statusCode == 401) {
    await apiClient.clearToken();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(docRoute(const LoginScreen()), (_) => false);
    return;
  }
  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final entries = ((data['entries'] as List?) ?? []).cast<Map<String, dynamic>>();
  final invites = ((data['invites'] as List?) ?? []).cast<Map<String, dynamic>>();

  final Widget next;
  //Modified By Nikhil 22Nov26 08:41 For forcing a new password after a temporary one. Old: if (invites.isNotEmpty) {
  if (data['must_change_password'] == true) {
    next = const SetOwnPasswordScreen();
  } else if (invites.isNotEmpty) {
    next = InvitesScreen(invites: invites);
  } else if (entries.isEmpty) {
    next = const ReceiptGateScreen(isSubscribed: false);
  } else if (entries.length == 1) {
    next = entryScreen(entries.first, single: true);
  } else {
    next = ModulePickerScreen(entries: entries);
  }
  Navigator.of(context).pushAndRemoveUntil(docRoute(next), (_) => false);
}

/// Screen for one entry (module + business + role).
Widget entryScreen(Map<String, dynamic> e, {bool single = false}) {
  if (e['needs_setup'] == true) return BusinessSetupScreen(entry: e);
  if (e['active'] == false) return _InactiveBusinessScreen(entry: e);
  if (e['module_code'] == 'gym') return GymHomeScreen(entry: e, canSwitch: !single);
  return _ModuleInDevelopmentScreen(entry: e);
}

// ---------------- picker ----------------

class ModulePickerScreen extends StatelessWidget {
  const ModulePickerScreen({super.key, required this.entries});
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: kScreenPadding,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: ScreenTitle(title: 'Choose Workspace', subtitle: 'Where do you want to go today?')),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(docRoute(const ProfileScreen())),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppTheme.chipBg, shape: BoxShape.circle),
                    child: const Icon(Icons.person_outline, size: 18, color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const AnnouncementBanners(), //Added By Nikhil 22Nov26 08:35 For announcement banners
            for (final e in entries)
              DocCard(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 10),
                onTap: () => Navigator.of(context).push(docRoute(entryScreen(e))),
                child: Row(
                  children: [
                    Text(e['icon'] ?? '📦', style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e['module_name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          Text(
                            [
                              e['workspace_name'] ?? 'Set up your business',
                              if (e['branch_name'] != null) e['branch_name'],
                            ].join(' • '),
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(
                      e['role_name'] ?? '',
                      bg: e['role_code'] == 'owner' ? AppTheme.primary : AppTheme.chipBg,
                      fg: e['role_code'] == 'owner' ? Colors.white : AppTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------- invites ----------------

class InvitesScreen extends StatefulWidget {
  const InvitesScreen({super.key, required this.invites});
  final List<Map<String, dynamic>> invites;

  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  late final List<Map<String, dynamic>> _pending = [...widget.invites];
  String? _busyId;

  Future<void> _respond(Map<String, dynamic> inv, bool accept) async {
    setState(() => _busyId = inv['member_id'] as String);
    try {
      final res = await apiClient.post('/workspaces/invites/${inv['member_id']}/respond', {'accept': accept});
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _pending.remove(inv));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accept ? 'You joined ${inv['workspace_name']}' : 'Invite declined')),
        );
        if (_pending.isEmpty) await routeAfterLogin(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiDetail(res.body, 'Could not respond'))));
      }
    } catch (e) { //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: catch (_)
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)))); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: const SnackBar(content: Text('Connection error'))
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: kScreenPadding,
          children: [
            const ScreenTitle(title: 'You have been invited', subtitle: 'Accept to join, or decline if this is not you'),
            const SizedBox(height: 16),
            for (final inv in _pending)
              DocCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(inv['icon'] ?? '📦', style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${inv['workspace_name']} wants to add you as ${inv['role_name']}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${inv['module_name']}${inv['branch_name'] != null ? ' • ${inv['branch_name']}' : ''}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: PillButton(
                            label: 'Accept',
                            variant: PillVariant.accent,
                            padding: const EdgeInsets.all(10),
                            fontSize: 13,
                            loading: _busyId == inv['member_id'],
                            onPressed: _busyId == null ? () => _respond(inv, true) : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PillButton(
                            label: 'Decline',
                            variant: PillVariant.secondary,
                            foreground: AppTheme.errorRed,
                            padding: const EdgeInsets.all(10),
                            fontSize: 13,
                            onPressed: _busyId == null ? () => _respond(inv, false) : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => routeAfterLogin(context),
                child: const Text('Decide later', style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- first-time business setup (owner) ----------------

class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({super.key, required this.entry, this.onCreated, this.initialName}); //Modified By Nikhil 22Nov26 14:41 For admin demo setup. Old: ({super.key, required this.entry})
  final Map<String, dynamic> entry;
  final VoidCallback? onCreated; //Added By Nikhil 22Nov26 14:41 For admin demo setup: return to the chooser instead of login routing
  final String? initialName; //Added By Nikhil 22Nov26 14:41 For admin demo setup: prefilled "Demo Gym"

  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  late final _nameCtrl = TextEditingController(text: widget.initialName); //Modified By Nikhil 22Nov26 14:41 For prefilled demo name. Old: final _nameCtrl = TextEditingController();
  final _branchCtrl = TextEditingController(text: 'Main Branch');
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _branchCtrl, _addressCtrl, _phoneCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().length < 2 || _branchCtrl.text.trim().length < 2) {
      setState(() => _error = 'Enter your business name and first branch name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await apiClient.post('/workspaces', {
        'module_code': widget.entry['module_code'],
        'business_name': _nameCtrl.text.trim(),
        'branch_name': _branchCtrl.text.trim(),
        if (_addressCtrl.text.trim().isNotEmpty) 'address': _addressCtrl.text.trim(),
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
      });
      if (!mounted) return;
      if (res.statusCode == 201) {
        //Modified By Nikhil 22Nov26 14:41 For admin demo setup returning to the chooser. Old: await routeAfterLogin(context);
        if (widget.onCreated != null) {
          widget.onCreated!();
        } else {
          await routeAfterLogin(context);
        }
      } else {
        setState(() => _error = apiDetail(res.body, 'Could not set up your business'));
      }
    } catch (e) { //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: catch (_)
      if (mounted) setState(() => _error = friendlyError(e)); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: 'Connection error'
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGym = widget.entry['module_code'] == 'gym';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: kScreenPadding,
          children: [
            Row(
              children: [
                Text(widget.entry['icon'] ?? '📦', style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Expanded(
                  child: ScreenTitle(
                    title: 'Set up your ${isGym ? 'gym' : 'business'}',
                    subtitle: 'One-time setup — you can add more branches later',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null) MessageBanner(_error!),
            DocField(label: isGym ? 'Gym / business name' : 'Business name', controller: _nameCtrl, hint: 'e.g. Nishchay Fitness'),
            DocField(label: 'First branch name', controller: _branchCtrl, hint: 'e.g. Vijay Nagar'),
            DocField(label: 'Branch address (optional)', controller: _addressCtrl),
            DocField(label: 'Branch phone (optional)', controller: _phoneCtrl, keyboardType: TextInputType.phone),
            const SizedBox(height: 6),
            PillButton(label: 'Create & Continue →', variant: PillVariant.accent, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}

class _InactiveBusinessScreen extends StatelessWidget {
  const _InactiveBusinessScreen({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) => _MessageScreen(
        icon: '⏸️',
        title: '${entry['workspace_name']} is unavailable',
        message: "This business's account is currently inactive — please contact the gym.",
      );
}

class _ModuleInDevelopmentScreen extends StatelessWidget {
  const _ModuleInDevelopmentScreen({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) => _MessageScreen(
        icon: '🚧',
        title: '${entry['module_name']} (In Development)',
        message: 'This module is currently being developed. Contact administrator for further details.',
      );
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({required this.icon, required this.title, required this.message});
  final String icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: kScreenPadding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
              const SizedBox(height: 20),
              PillButton(
                label: 'Back',
                variant: PillVariant.secondary,
                onPressed: () => Navigator.of(context).canPop() ? Navigator.pop(context) : routeAfterLogin(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//Added By Nikhil 22Nov26 08:41 For first login with a temporary password (owner-created accounts) START
class SetOwnPasswordScreen extends StatefulWidget {
  const SetOwnPasswordScreen({super.key});
  @override
  State<SetOwnPasswordScreen> createState() => _SetOwnPasswordScreenState();
}

class _SetOwnPasswordScreenState extends State<SetOwnPasswordScreen> {
  final _temp = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _temp.dispose();
    _new.dispose();
    _new2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_new.text.length < 6) return setState(() => _error = 'New password needs at least 6 characters');
    if (_new.text != _new2.text) return setState(() => _error = 'The two new passwords do not match');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await apiClient.put('/auth/me/password', {'current_password': _temp.text, 'new_password': _new.text});
      if (!mounted) return;
      if (res.statusCode == 200) {
        await routeAfterLogin(context);
      } else {
        setState(() => _error = apiDetail(res.body, 'Could not change the password'));
      }
    } catch (e) { //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: catch (_)
      if (mounted) setState(() => _error = friendlyError(e)); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: 'Connection error'
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: kScreenPadding,
          children: [
            const ScreenTitle(title: 'Set your password', subtitle: 'Your account was created with a temporary password'),
            const SizedBox(height: 18),
            if (_error != null) MessageBanner(_error!),
            DocField(label: 'Temporary password', controller: _temp, obscure: true),
            DocField(label: 'New password', controller: _new, obscure: true),
            DocField(label: 'Repeat new password', controller: _new2, obscure: true),
            PillButton(label: 'Save & Continue', variant: PillVariant.accent, loading: _busy, onPressed: _save),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () async {
                  await apiClient.clearToken();
                  if (!context.mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(docRoute(const LoginScreen()), (_) => false);
                },
                child: const Text('Sign Out', style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
//Added By Nikhil 22Nov26 08:41 For first login with a temporary password (owner-created accounts) END
