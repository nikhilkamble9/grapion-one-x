// //Added By Nikhil 21Nov26 21:00 For approved user's own modules (only what they subscribed to)
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import '../../widgets/module_card.dart';
import '../auth/login_screen.dart'; //Added By Nikhil 21Nov26 21:16 For sign out from home
import '../profile/profile_screen.dart'; //Added By Nikhil 21Nov26 22:36 For avatar → Profile Settings
import 'store_screen.dart'; //Added By Nikhil 21Nov26 22:36 For Renew

class MyModulesScreen extends StatefulWidget {
  //Modified By Nikhil 21Nov26 21:16 For subscribed users landing here after login. Old: const MyModulesScreen({super.key});
  const MyModulesScreen({super.key, this.asHome = false});

  /// true = the user's home after login (avatar menu instead of a back button).
  final bool asHome;

  @override
  State<MyModulesScreen> createState() => _MyModulesScreenState();
}

class _MyModulesScreenState extends State<MyModulesScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _modules = [];
  List<dynamic> _expired = []; //Added By Nikhil 21Nov26 22:36 For "ended on … Renew"
  String _initials = ''; //Added By Nikhil 21Nov26 21:16 For avatar on home

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // The API filters by the signed-in user, so only this user's active modules come back.
      final res = await apiClient.get('/subscriptions/my-modules');
      if (!mounted) return;
      //Added By Nikhil 21Nov26 21:16 For avatar initials + expired-token handling START
      if (res.statusCode == 401) {
        await _signOut();
        return;
      }
      if (widget.asHome && _initials.isEmpty) {
        final me = await apiClient.get('/auth/me');
        if (me.statusCode == 200 && mounted) {
          final m = jsonDecode(me.body);
          _initials = initialsOf(m['first_name'] ?? '', m['last_name'] ?? '');
        }
      }
      if (!mounted) return;
      //Added By Nikhil 21Nov26 21:16 For avatar initials + expired-token handling END
      if (res.statusCode == 200) {
        setState(() {
          final body = jsonDecode(res.body);
          _modules = body['modules'] ?? [];
          _expired = body['expired_modules'] ?? []; //Added By Nikhil 21Nov26 22:36 For "ended on … Renew"
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Could not load your modules';
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Connection error';
          _loading = false;
        });
      }
    }
  }

  //Added By Nikhil 21Nov26 21:16 For home avatar menu START
  Future<void> _signOut() async {
    await apiClient.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(docRoute(const LoginScreen()), (_) => false);
  }

  //Modified By Nikhil 21Nov26 22:36 For avatar opening Profile Settings directly (old bottom-sheet menu kept below, unused)
  Future<void> _openProfile() async {
    await Navigator.of(context).push(docRoute(const ProfileScreen()));
    if (mounted) _load();
  }

  Future<void> _renew(String code) async {
    await Navigator.of(context).push(docRoute(StoreScreen(preselectCodes: [code])));
    if (mounted) _load();
  }

  // ignore: unused_element
  void _openAccountMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppTheme.borderSubtle, borderRadius: BorderRadius.circular(4)),
              ),
              PillButton(
                label: 'Profile & Subscription Settings',
                variant: PillVariant.secondary,
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile settings are coming in the next update')),
                  );
                },
              ),
              const SizedBox(height: 10),
              PillButton(label: 'Sign Out', foreground: AppTheme.errorRed, variant: PillVariant.secondary, onPressed: _signOut),
            ],
          ),
        ),
      ),
    );
  }
  //Added By Nikhil 21Nov26 21:16 For home avatar menu END

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: _load,
          child: ListView(
            padding: kScreenPadding,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ScreenTitle(
                      title: 'My Modules',
                      subtitle: 'Modules active on your subscription',
                      trailing: _loading
                          ? null
                          : StatusChip(
                              '${_modules.length} Active',
                              bg: AppTheme.primary,
                              fg: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            ),
                    ),
                  ),
                  //Modified By Nikhil 21Nov26 21:16 For avatar on home. Old: SmallPill(label: '← Back', onTap: () => Navigator.pop(context)),
                  if (widget.asHome)
                    Semantics(
                      button: true,
                      label: 'Account menu',
                      child: GestureDetector(
                        onTap: _openProfile, //Modified By Nikhil 21Nov26 22:36 For avatar → Profile. Old: onTap: _openAccountMenu,
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppTheme.chipBg, shape: BoxShape.circle),
                          child: Text(_initials, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    )
                  else
                    SmallPill(label: '← Back', onTap: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 14),
              if (_error != null) MessageBanner(_error!),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                ),
              //Added By Nikhil 21Nov26 22:36 For ended modules with Renew START
              if (!_loading)
                for (final m in _expired)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.errorLight,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      children: [
                        Text(m['icon'] ?? '📦', style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your subscription for ${m['name']} ended on ${formatServerDateTime(m['expires_at'] as String?, withTime: false)}. Do you want to renew?',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.errorRed),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 74,
                          child: PillButton(
                            label: 'Renew',
                            variant: PillVariant.accent,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            fontSize: 11,
                            onPressed: () => _renew(m['code'] as String),
                          ),
                        ),
                      ],
                    ),
                  ),
              //Added By Nikhil 21Nov26 22:36 For ended modules with Renew END
              if (_loading)
                const SizedBox.shrink()
              else if (_modules.isEmpty && _error == null)
                const DocCard(
                  child: Center(
                    child: Text('No active modules on your account.', style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                  ),
                )
              else
                for (final m in _modules)
                  ModuleCard(
                    module: Map<String, dynamic>.from(m as Map),
                    footer: 'Active until ${formatServerDateTime(m['expires_at'] as String?, withTime: false)}',
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
