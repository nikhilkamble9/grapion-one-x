// //Added By Nikhil 22Nov26 14:41 For admin "View as Owner / Member" (admins try the Gym module in their own demo business)
import 'package:flutter/material.dart';

import '../../screens/home/entry_router.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import 'gym_common.dart';
import 'gym_home_screen.dart';

/// Admin / super admin only (opened from the admin Modules tab).
/// Uses the admin's OWN demo business — real customer businesses are never opened from here.
class GymViewAsScreen extends StatefulWidget {
  const GymViewAsScreen({super.key});

  @override
  State<GymViewAsScreen> createState() => _GymViewAsScreenState();
}

class _GymViewAsScreenState extends State<GymViewAsScreen> {
  Map<String, dynamic>? _demo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await gymGet(context, '/workspaces/demo?module_code=gym');
    if (!mounted) return;
    setState(() {
      _demo = d;
      _loading = false;
    });
  }

  bool get _needsSetup => _demo?['needs_setup'] == true;

  void _setUp() {
    Navigator.of(context).push(docRoute(BusinessSetupScreen(
      entry: _demo!,
      initialName: 'Demo Gym',
      onCreated: () {
        Navigator.of(context).pop();
        _load();
      },
    )));
  }

  void _asOwner() {
    if (_needsSetup) return _setUp();
    Navigator.of(context).push(docRoute(GymHomeScreen(entry: _demo!)));
  }

  void _asMember() {
    if (_needsSetup) {
      gymToast(context, 'Set up your demo gym first (View as Owner).');
      return;
    }
    Navigator.of(context).push(docRoute(GymHomeScreen(entry: {..._demo!, 'role_code': 'member', 'role_name': 'Member'})));
  }

  @override
  Widget build(BuildContext context) {
    return GymPage(
      title: 'Grapion Gym',
      subtitle: 'See the module the way your customers do',
      onRefresh: _load,
      children: [
        if (_loading)
          gymLoading
        else if (_demo == null)
          gymEmpty('Could not load. Pull down to try again.')
        else ...[
          DocCard(
            padding: const EdgeInsets.all(14),
            gradient: const LinearGradient(colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)]),
            borderColor: const Color(0xFFBFDBFE),
            child: Text(
              _needsSetup
                  ? '🧪 You get your own demo gym. It is separate from every customer business and needs no subscription.'
                  : '🧪 Demo business: ${_demo!['workspace_name']}. Separate from every customer business.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
          _option('👑', 'View as Owner', _needsSetup ? 'Set up the demo gym, then use the owner dashboard' : 'Dashboard, members, staff, shifts, payments', _asOwner),
          _option('🏋️', 'View as Member', 'What a gym member sees', _asMember, dim: _needsSetup),
        ],
      ],
    );
  }

  Widget _option(String icon, String title, String sub, VoidCallback onTap, {bool dim = false}) => Opacity(
        opacity: dim ? 0.55 : 1,
        child: DocCard(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 10),
          onTap: onTap,
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    Text(sub, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSubtle),
            ],
          ),
        ),
      );
}
