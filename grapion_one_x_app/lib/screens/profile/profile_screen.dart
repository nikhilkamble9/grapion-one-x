// //Added By Nikhil 21Nov26 22:36 For Profile Settings (details, password, subscriptions, add modules, renew)
import 'dart:convert';

import 'package:flutter/material.dart';
//Removed By Nikhil 22Nov26 17:36 For mobile field moved to Edit Profile: import 'package:flutter/services.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import '../auth/register_screen.dart' show Country; //Modified By Nikhil 22Nov26 17:36 For country picker moved to Edit Profile. Old: show Country, CountryPickerSheet, flagOf
import '../auth/login_screen.dart';
import '../subscription/store_screen.dart';
import '../../widgets/announcement_banner.dart'; //Added By Nikhil 22Nov26 08:35 For Help & support card
import 'edit_profile_screen.dart'; //Added By Nikhil 22Nov26 17:36 For Edit Profile page + initials avatar

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _periodLabel = {'weekly': 'Weekly', 'monthly': 'Monthly', 'quarterly': 'Quarterly', 'yearly': 'Yearly'};

  // Personal details
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  //Removed By Nikhil 22Nov26 16:52 For password asked in a dialog on Save: final _detailsPwdCtrl = TextEditingController();
  //Removed By Nikhil 22Nov26 16:52 For Change Password on its own page: final _curPwdCtrl, _newPwdCtrl, _newPwd2Ctrl = TextEditingController();
  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page: String _savedDetails = '';
  List<Map<String, dynamic>> _entries = []; //Added By Nikhil 22Nov26 17:36 For My Gym / My Gym Membership
  final Map<String, Map<String, dynamic>> _memberHome = {}; //Added By Nikhil 22Nov26 17:36 For member expiry (workspace id → /me/member)

  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page: List<Country> _countries = const [];
  Country? _country;
  String _username = '';

  List<dynamic> _active = [];
  List<dynamic> _expired = [];
  Map<String, dynamic>? _pending;
  List<Map<String, dynamic>> _openCancels = []; //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription
  bool _cancelBusy = false; //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription

  bool _loading = true;
  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page: bool _savingDetails = false;
  //Removed By Nikhil 22Nov26 16:52 For Change Password on its own page: bool _savingPassword = false;
  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page: String? _detailsMsg; bool _detailsOk = false;
  //Removed By Nikhil 22Nov26 16:52 For Change Password on its own page: String? _passwordMsg; bool _passwordOk = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_firstCtrl, _lastCtrl, _emailCtrl, _mobileCtrl]) { //Modified By Nikhil 22Nov26 16:52 For password fields moved out. Old: [..., _detailsPwdCtrl, _curPwdCtrl, _newPwdCtrl, _newPwd2Ctrl]
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final r = await Future.wait([
        apiClient.get('/auth/me/profile'),
        apiClient.get('/meta/countries'),
        apiClient.get('/subscriptions/my-modules'),
        apiClient.get('/subscriptions/my-status'),
        apiClient.get('/subscriptions/cancellations'), //Added By Nikhil 21Nov26 22:44 For open cancellations
        apiClient.get('/workspaces/my-entries'), //Added By Nikhil 22Nov26 17:36 For My Gym / My Gym Membership
      ]);
      if (!mounted) return;
      if (r[0].statusCode != 200) throw Exception('profile');
      final p = jsonDecode(r[0].body);
      final countries = r[1].statusCode == 200
          ? (jsonDecode(r[1].body)['countries'] as List).map((e) => Country.fromJson(e as Map<String, dynamic>)).toList()
          : <Country>[];
      final mine = r[2].statusCode == 200 ? jsonDecode(r[2].body) : {};
      final status = r[3].statusCode == 200 ? jsonDecode(r[3].body) : {};
      setState(() {
        _firstCtrl.text = p['first_name'] ?? '';
        _lastCtrl.text = p['last_name'] ?? '';
        _emailCtrl.text = p['email'] ?? '';
        _mobileCtrl.text = p['mobile_number'] ?? '';
        _username = p['username'] ?? '';
        //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page: _countries = countries;
        _country = countries.where((c) => c.code == p['country_code']).firstOrNull ??
            Country(code: p['country_code'] ?? 'IN', name: p['country_code'] ?? 'IN', dial: p['dial_code'] ?? '+91', currency: 'INR', symbol: '₹');
        _active = mine['modules'] ?? [];
        _expired = mine['expired_modules'] ?? [];
        _pending = status['pending_request'];
        //Added By Nikhil 21Nov26 22:44 For open cancellations
        _openCancels = r[4].statusCode == 200
            ? ((jsonDecode(r[4].body)['open'] as List?) ?? []).cast<Map<String, dynamic>>()
            : [];
        //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page: _savedDetails = _detailsKey();
        _entries = r[5].statusCode == 200 ? ((jsonDecode(r[5].body)['entries'] as List?) ?? []).cast<Map<String, dynamic>>() : []; //Added By Nikhil 22Nov26 17:36 For My Gym
        _loading = false;
      });
      //Added By Nikhil 22Nov26 17:36 For member membership expiry on the profile START
      for (final e in _entries.where((e) => e['role_code'] == 'member' && e['active'] != false && e['workspace_id'] != null)) {
        final res = await apiClient.get('/gym/${e['workspace_id']}/me/member');
        if (res.statusCode == 200 && mounted) setState(() => _memberHome[e['workspace_id'] as String] = jsonDecode(res.body) as Map<String, dynamic>);
      }
      //Added By Nikhil 22Nov26 17:36 For member membership expiry on the profile END
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadError = 'Could not load your profile. Pull down to retry.';
          _loading = false;
        });
      }
    }
  }

  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page START
  //String _detail(String body, String fallback) {
  //  try {
  //    final d = jsonDecode(body)['detail'];
  //    return d is String ? d : fallback;
  //  } catch (_) {
  //    return fallback;
  //  }
  //}
  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page END

  //Added By Nikhil 22Nov26 16:52 For "No changes to save" START
  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page: String _detailsKey() => [first, last, email, country, mobile].join('|');
  //Added By Nikhil 22Nov26 16:52 For "No changes to save" END

  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page START
  //Future<void> _saveDetails() async {
  //  //Modified By Nikhil 22Nov26 16:52 For password asked in a dialog on Save. Old: if (_detailsPwdCtrl.text.isEmpty) { _detailsMsg = 'Enter your current password to save changes.'; return; }
  //  if (_detailsKey() == _savedDetails) {
  //    setState(() {
  //      _detailsMsg = 'No changes to save.';
  //      _detailsOk = false;
  //    });
  //    return;
  //  }
  //  final password = await showDialog<String>(context: context, builder: (_) => const _ConfirmPasswordDialog());
  //  if (password == null || password.isEmpty || !mounted) return;
  //  setState(() {
  //    _savingDetails = true;
  //    _detailsMsg = null;
  //  });
  //  try {
  //    final res = await apiClient.put('/auth/me/profile', {
  //      'current_password': password, //Modified By Nikhil 22Nov26 16:52 For password from the dialog. Old: _detailsPwdCtrl.text,
  //      'first_name': _firstCtrl.text.trim(),
  //      'last_name': _lastCtrl.text.trim(),
  //      'email': _emailCtrl.text.trim(),
  //      'country_code': _country?.code,
  //      'dial_code': _country?.dial,
  //      'mobile_number': _mobileCtrl.text.replaceAll(' ', ''),
  //    });
  //    if (!mounted) return;
  //    final ok = res.statusCode == 200;
  //    setState(() {
  //      _detailsOk = ok;
  //      _detailsMsg = ok ? 'Profile updated.' : _detail(res.body, 'Could not update profile. Check the details.');
  //      if (ok) _savedDetails = _detailsKey(); //Modified By Nikhil 22Nov26 16:52 For "No changes to save". Old: if (ok) _detailsPwdCtrl.clear();
  //    });
  //  } catch (e) { //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: catch (_)
  //    if (mounted) setState(() => _detailsMsg = friendlyError(e)); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: 'Connection error'
  //  } finally {
  //    if (mounted) setState(() => _savingDetails = false);
  //  }
  //}
  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page END

  //Removed By Nikhil 22Nov26 16:52 For Change Password on its own page START
  //Future<void> _changePassword() async {
  //  if (_curPwdCtrl.text.isEmpty || _newPwdCtrl.text.isEmpty) {
  //    setState(() {
  //      _passwordMsg = 'Fill in all password fields.';
  //      _passwordOk = false;
  //    });
  //    return;
  //  }
  //  if (_newPwdCtrl.text != _newPwd2Ctrl.text) {
  //    setState(() {
  //      _passwordMsg = 'New passwords do not match.';
  //      _passwordOk = false;
  //    });
  //    return;
  //  }
  //  setState(() {
  //    _savingPassword = true;
  //    _passwordMsg = null;
  //  });
  //  try {
  //    final res = await apiClient.put('/auth/me/password', {
  //      'current_password': _curPwdCtrl.text,
  //      'new_password': _newPwdCtrl.text,
  //    });
  //    if (!mounted) return;
  //    final ok = res.statusCode == 200;
  //    setState(() {
  //      _passwordOk = ok;
  //      _passwordMsg = ok ? 'Password changed.' : _detail(res.body, 'Could not change password (minimum 6 characters).');
  //      if (ok) {
  //        _curPwdCtrl.clear();
  //        _newPwdCtrl.clear();
  //        _newPwd2Ctrl.clear();
  //      }
  //    });
  //  } catch (e) { //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: catch (_)
  //    if (mounted) setState(() => _passwordMsg = friendlyError(e)); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: 'Connection error'
  //  } finally {
  //    if (mounted) setState(() => _savingPassword = false);
  //  }
  //}
  //Removed By Nikhil 22Nov26 16:52 For Change Password on its own page END

  //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription START
  Map<String, dynamic>? get _pendingCancel => _openCancels.where((c) => c['cancel_type'] == 'pending_request').firstOrNull;

  Map<String, dynamic>? _moduleCancel(String code) =>
      _openCancels.where((c) => c['cancel_type'] == 'active_module' && c['module_code'] == code).firstOrNull;

  Future<void> _cancel({required String target, String? moduleCode, String? moduleName}) async {
    final reason = await showReasonDialog(
      context,
      title: moduleName == null ? 'Cancel subscription request?' : 'Cancel $moduleName?',
      message: moduleName == null
          ? 'The admin will see your reason. You can keep the subscription until the admin reviews it.'
          : 'We refund the unused days of this module (what you paid after discount × unused days ÷ total days, today counts as used). '
              'The admin settles the refund through the back office. If the admin rejects, the module runs until its end date.',
      label: 'Cancellation reason',
      confirmLabel: 'Cancel Subscription',
    );
    if (reason == null || !mounted) return;
    setState(() => _cancelBusy = true);
    try {
      final res = await apiClient.post('/subscriptions/cancellations', {
        'target': target,
        'module_code': ?moduleCode,
        'reason': reason,
      });
      if (!mounted) return;
      String msg = apiDetail(res.body, 'Could not cancel');
      if (res.statusCode == 201) {
        final refund = jsonDecode(res.body)['refund_amount'];
        msg = refund == null ? 'Cancellation sent to the admin' : 'Cancellation sent • refund of ${formatMoney(refund as num)} to be settled by admin';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) { //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: catch (_)
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)))); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: const SnackBar(content: Text('Connection error'))
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
      await _load();
    }
  }

  Future<void> _keep(String cancellationId) async {
    setState(() => _cancelBusy = true);
    try {
      final res = await apiClient.post('/subscriptions/cancellations/$cancellationId/withdraw', {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.statusCode == 200 ? 'Cancellation withdrawn — your subscription continues' : apiDetail(res.body, 'Could not update')),
      ));
    } catch (e) { //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: catch (_)
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)))); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: const SnackBar(content: Text('Connection error'))
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
      await _load();
    }
  }

  Widget _smallPill(String label, VoidCallback? onTap, {bool danger = false}) => SizedBox(
        width: 84,
        child: PillButton(
          label: label,
          variant: danger ? PillVariant.secondary : PillVariant.accent,
          foreground: danger ? AppTheme.errorRed : null,
          padding: const EdgeInsets.symmetric(vertical: 8),
          fontSize: 11,
          onPressed: _cancelBusy ? null : onTap,
        ),
      );
  //Added By Nikhil 21Nov26 22:44 For cancel / keep subscription END

  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page START
  //void _pickCountry() {
  //  if (_countries.isEmpty) return;
  //  showModalBottomSheet<void>(
  //    context: context,
  //    isScrollControlled: true,
  //    backgroundColor: Colors.white,
  //    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
  //    builder: (ctx) => CountryPickerSheet(
  //      countries: _countries,
  //      onSelected: (c) {
  //        setState(() => _country = c);
  //        Navigator.pop(ctx);
  //      },
  //    ),
  //  );
  //}
  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page END

  Future<void> _openStore({List<String> preselect = const []}) async {
    await Navigator.of(context).push(docRoute(StoreScreen(preselectCodes: preselect)));
    if (mounted) _load();
  }

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
                      title: 'Profile Settings',
                      subtitle: _username.isEmpty ? 'Manage your account & subscriptions' : '@$_username',
                    ),
                  ),
                  SmallPill(label: '← Back', onTap: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              if (_loadError != null) MessageBanner(_loadError!),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                )
              else ...[
                //Modified By Nikhil 22Nov26 17:36 For avatar + Edit Profile, modules only for owners, gym membership for members. Old: MY SUBSCRIPTIONS (always) + PERSONAL DETAILS form
                _profileHeader(),
                if (_isGymPersonOnly) ..._gymSections() else ...[
                  _sectionLabel('MY SUBSCRIPTIONS'),
                  _buildSubscriptions(),
                  const SizedBox(height: 6),
                ],
                //Modified By Nikhil 22Nov26 16:52 For Change Password as a menu row. Old: _sectionLabel('CHANGE PASSWORD'), _buildPassword(),
                _sectionLabel('SECURITY'),
                DocCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  onTap: () => Navigator.of(context).push(docRoute(const ChangePasswordScreen())),
                  child: const Row(
                    children: [
                      Text('🔒', style: TextStyle(fontSize: 18)),
                      SizedBox(width: 12),
                      Expanded(child: Text('Change Password', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                      Icon(Icons.chevron_right, color: AppTheme.textSubtle),
                    ],
                  ),
                ),
                const SupportCard(), //Added By Nikhil 22Nov26 08:35 For Help & support from Platform Settings
                Center(
                  child: TextButton(
                    onPressed: () async {
                      await apiClient.clearToken();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(docRoute(const LoginScreen()), (_) => false);
                    },
                    child: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.errorRed,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.errorRed,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  //Added By Nikhil 22Nov26 17:36 For avatar header, Edit Profile, My Gym / My Gym Membership START
  /// Someone added to a gym (member / staff) who has no G.One.X modules of their own → no "Add Modules" section.
  bool get _isGymPersonOnly =>
      _active.isEmpty && _expired.isEmpty && _pending == null && _entries.isNotEmpty && _entries.every((e) => e['role_code'] != 'owner');

  Widget _profileHeader() {
    final name = '${_firstCtrl.text} ${_lastCtrl.text}'.trim();
    return DocCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              InitialsAvatar(first: _firstCtrl.text, last: _lastCtrl.text),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    if (_username.isNotEmpty) Text('@$_username', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    if (!isPlaceholderEmail(_emailCtrl.text))
                      Text(_emailCtrl.text, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                    Text('${_country?.dial ?? ''} ${_mobileCtrl.text}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PillButton(
            label: '✏️  Edit Profile',
            variant: PillVariant.secondary,
            padding: const EdgeInsets.all(11),
            fontSize: 13,
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(docRoute(const EditProfileScreen()));
              if (saved == true && mounted) _load();
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _gymSections() {
    final members = _entries.where((e) => e['role_code'] == 'member').toList();
    final staff = _entries.where((e) => e['role_code'] != 'member' && e['role_code'] != 'owner').toList();
    return [
      if (members.isNotEmpty) ...[
        _sectionLabel('MY GYM MEMBERSHIP'),
        for (final e in members) _membershipCard(e),
        const SizedBox(height: 6),
      ],
      if (staff.isNotEmpty) ...[
        _sectionLabel('MY GYM'),
        for (final e in staff)
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Text(e['icon'] as String? ?? '🏋️', style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e['workspace_name'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      Text([if (e['branch_name'] != null) e['branch_name'], e['module_name']].join(' • '),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                StatusChip('${e['role_name'] ?? ''}', bg: AppTheme.successLight, fg: AppTheme.primaryDark, fontSize: 10),
              ],
            ),
          ),
        const SizedBox(height: 6),
      ],
    ];
  }

  Widget _membershipCard(Map<String, dynamic> e) {
    final h = _memberHome[e['workspace_id']];
    final ms = h?['membership'] as Map<String, dynamic>?;
    final last = h?['last_expired'] as Map<String, dynamic>?;
    final gym = '${e['workspace_name'] ?? 'your gym'}';
    final days = (ms?['days_left'] as num?)?.toInt();
    final soon = days != null && days <= 7;
    final String line;
    if (h == null) {
      line = 'Loading…';
    } else if (ms != null) {
      line = 'Your ${ms['plan_name']} membership expires on ${niceDay(ms['expiry_date'] as String)}. Contact $gym to renew.';
    } else if (last != null) {
      line = 'Your ${last['plan_name']} membership ended on ${niceDay(last['expiry_date'] as String)}. Contact $gym to renew.';
    } else {
      line = 'No membership plan yet. Contact $gym to start one.';
    }
    return DocCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      borderColor: ms == null || soon ? const Color(0xFFFDE68A) : AppTheme.cardBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text([gym, if (e['branch_name'] != null) e['branch_name']].join(' • '),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              if (ms != null)
                StatusChip(days == 1 ? '1 day left' : '$days days left',
                    bg: soon ? AppTheme.warningLight : AppTheme.successLight, fg: soon ? AppTheme.warningOrange : AppTheme.primaryDark, fontSize: 10)
              else if (h != null)
                const StatusChip('Not active', bg: AppTheme.errorLight, fg: AppTheme.errorRed, fontSize: 10),
            ],
          ),
          if (ms != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${ms['plan_name']} • ${niceDay(ms['start_date'] as String)} → ${niceDay(ms['expiry_date'] as String)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.label)),
            ),
          const SizedBox(height: 6),
          Text(line, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4)),
        ],
      ),
    );
  }

  /// "2026-12-22" → "22 Dec 2026".
  static String niceDay(String iso) => formatServerDateTime('${iso.substring(0, 10)}T00:00:00', withTime: false);
  //Added By Nikhil 22Nov26 17:36 For avatar header, Edit Profile, My Gym / My Gym Membership END

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.5)),
      );

  Widget _buildSubscriptions() {
    return DocCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_pending != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.warningLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                '⏳ Request ${_pending!['request_number']} is awaiting admin approval • ${formatMoney(_pending!['final_amount'] as num)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
              ),
            ),
          //Added By Nikhil 21Nov26 22:44 For cancel / keep on the pending request START
          if (_pending != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _pendingCancel == null
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: _smallPill('Cancel', () => _cancel(target: 'pending_request'), danger: true),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            '🛑 Cancellation requested • ${_pendingCancel!['reason']}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.errorRed),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _smallPill('Keep', () => _keep(_pendingCancel!['id'] as String)),
                      ],
                    ),
            ),
          //Added By Nikhil 21Nov26 22:44 For cancel / keep on the pending request END
          if (_active.isEmpty && _expired.isEmpty && _pending == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('You have no subscriptions yet.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            ),
          for (final m in _active) _subscriptionRow(m, expired: false),
          for (final m in _expired) _subscriptionRow(m, expired: true),
          const SizedBox(height: 4),
          PillButton(
            label: '+ Add Modules',
            variant: PillVariant.accent,
            padding: const EdgeInsets.all(12),
            fontSize: 13,
            onPressed: _pending != null
                ? () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please wait until your pending request is reviewed')),
                    )
                : () => _openStore(),
          ),
          const SizedBox(height: 6),
          const Text(
            'Each module has its own start and end date.',
            style: TextStyle(fontSize: 10, color: AppTheme.textSubtle),
          ),
        ],
      ),
    );
  }

  Widget _subscriptionRow(dynamic m, {required bool expired}) {
    final period = _periodLabel[m['billing_period']] ?? '';
    final start = formatServerDateTime(m['starts_at'] as String?, withTime: false);
    final end = formatServerDateTime(m['expires_at'] as String?, withTime: false);
    final daysLeft = (m['days_left'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: expired ? const Color(0xFFFECACA) : AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Text(m['icon'] ?? '📦', style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${m['name']}${period.isEmpty ? '' : ' • $period'}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
                Text(
                  expired ? 'Your subscription ended on $end' : '$start → $end',
                  style: TextStyle(fontSize: 11, color: expired ? AppTheme.errorRed : AppTheme.textMuted),
                ),
                //Added By Nikhil 21Nov26 22:44 For open module cancellation + refund
                if (!expired && _moduleCancel(m['code'] as String) != null)
                  Text(
                    '🛑 Cancellation requested • refund ${formatMoney((_moduleCancel(m['code'] as String)!['refund_amount'] as num?) ?? 0)} awaiting admin',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.errorRed),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (expired)
            SizedBox(
              width: 74,
              child: PillButton(
                label: 'Renew',
                variant: PillVariant.accent,
                padding: const EdgeInsets.symmetric(vertical: 8),
                fontSize: 11,
                onPressed: _pending != null ? null : () => _openStore(preselect: [m['code'] as String]),
              ),
            )
          else
            //Modified By Nikhil 21Nov26 22:44 For per-module cancel / keep. Old: StatusChip(days left) only
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusChip(
                  daysLeft == 1 ? '1 day left' : '$daysLeft days left',
                  bg: daysLeft <= 3 ? AppTheme.warningLight : AppTheme.successLight,
                  fg: daysLeft <= 3 ? AppTheme.warningOrange : AppTheme.primaryDark,
                ),
                const SizedBox(height: 6),
                if (_moduleCancel(m['code'] as String) == null)
                  _smallPill('Cancel', () => _cancel(target: 'active_module', moduleCode: m['code'] as String, moduleName: m['name'] as String?), danger: true)
                else
                  _smallPill('Keep', () => _keep(_moduleCancel(m['code'] as String)!['id'] as String)),
              ],
            ),
        ],
      ),
    );
  }

  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page START
  //Widget _buildDetails() {
  //  return DocCard(
  //    padding: const EdgeInsets.all(16),
  //    child: Column(
  //      crossAxisAlignment: CrossAxisAlignment.start,
  //      children: [
  //        if (_detailsMsg != null) MessageBanner(_detailsMsg!, success: _detailsOk),
  //        Row(
  //          crossAxisAlignment: CrossAxisAlignment.start,
  //          children: [
  //            Expanded(child: DocField(label: 'First Name', controller: _firstCtrl)),
  //            const SizedBox(width: 10),
  //            Expanded(child: DocField(label: 'Last Name', controller: _lastCtrl)),
  //          ],
  //        ),
  //        DocField(label: 'Registered Email', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
  //        const FieldLabel('Country & Mobile Number'),
  //        Row(
  //          children: [
  //            Material(
  //              color: Colors.white,
  //              shape: RoundedRectangleBorder(
  //                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
  //                side: const BorderSide(color: AppTheme.borderSubtle),
  //              ),
  //              child: InkWell(
  //                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
  //                onTap: _pickCountry,
  //                child: Padding(
  //                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
  //                  child: Row(
  //                    mainAxisSize: MainAxisSize.min,
  //                    children: [
  //                      if (_country != null) flagOf(_country!.code),
  //                      const SizedBox(width: 8),
  //                      Text(_country?.dial ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
  //                      const SizedBox(width: 8),
  //                      const Text('▼', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
  //                    ],
  //                  ),
  //                ),
  //              ),
  //            ),
  //            const SizedBox(width: 8),
  //            Expanded(
  //              child: TextField(
  //                controller: _mobileCtrl,
  //                keyboardType: TextInputType.phone,
  //                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(15)],
  //                decoration: const InputDecoration(hintText: '98234 11223'),
  //              ),
  //            ),
  //          ],
  //        ),
  //        const SizedBox(height: 14),
  //        //Removed By Nikhil 22Nov26 16:52 For password asked in a dialog on Save: DocField(label: 'Current Password (required to save)', controller: _detailsPwdCtrl, obscure: true, hint: 'Enter current password'),
  //        PillButton(label: 'Save Changes', loading: _savingDetails, onPressed: _saveDetails),
  //      ],
  //    ),
  //  );
  //}
  //Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page END

  //Removed By Nikhil 22Nov26 16:52 For Change Password on its own page START
  //Widget _buildPassword() {
  //  return DocCard(
  //    padding: const EdgeInsets.all(16),
  //    child: Column(
  //      crossAxisAlignment: CrossAxisAlignment.start,
  //      children: [
  //        if (_passwordMsg != null) MessageBanner(_passwordMsg!, success: _passwordOk),
  //        DocField(label: 'Current Password', controller: _curPwdCtrl, obscure: true),
  //        DocField(label: 'New Password', controller: _newPwdCtrl, obscure: true),
  //        DocField(label: 'Type Again New Password', controller: _newPwd2Ctrl, obscure: true),
  //        PillButton(label: 'Change Password', loading: _savingPassword, onPressed: _changePassword),
  //      ],
  //    ),
  //  );
  //}
  //Removed By Nikhil 22Nov26 16:52 For Change Password on its own page END
}

//Added By Nikhil 22Nov26 16:52 For password asked only when saving profile changes START
/// "Confirm it's you" — returns the typed password, or null when cancelled. Owns its controller (disposed with the dialog).
//Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page START
//class _ConfirmPasswordDialog extends StatefulWidget {
//  const _ConfirmPasswordDialog();
//
//  @override
//  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
//}
//Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page END

//Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page START
//class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
//  final _pwd = TextEditingController();
//
//  @override
//  void dispose() {
//    _pwd.dispose();
//    super.dispose();
//  }
//
//  void _ok() {
//    if (_pwd.text.isNotEmpty) Navigator.pop(context, _pwd.text);
//  }
//
//  @override
//  Widget build(BuildContext context) {
//    return AlertDialog(
//      backgroundColor: Colors.white,
//      title: const Text("Confirm it's you", style: TextStyle(fontWeight: FontWeight.w800)),
//      content: Column(
//        mainAxisSize: MainAxisSize.min,
//        crossAxisAlignment: CrossAxisAlignment.start,
//        children: [
//          const Text('Enter your current password to save these changes.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
//          const SizedBox(height: 12),
//          DocField(label: 'Current password', controller: _pwd, obscure: true, onSubmitted: (_) => _ok()),
//        ],
//      ),
//      actions: [
//        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
//        TextButton(onPressed: _ok, child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800))),
//      ],
//    );
//  }
//}
//Removed By Nikhil 22Nov26 17:36 For Edit Profile on its own page END
//Added By Nikhil 22Nov26 16:52 For password asked only when saving profile changes END

//Added By Nikhil 22Nov26 16:52 For Change Password on its own page (opened from Profile → Security) START
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  bool _saving = false;
  String? _msg;
  bool _ok = false;

  @override
  void dispose() {
    for (final c in [_cur, _new, _new2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    String? problem;
    if (_cur.text.isEmpty || _new.text.isEmpty) problem = 'Fill in all password fields.';
    if (problem == null && _new.text != _new2.text) problem = 'New passwords do not match.';
    if (problem != null) {
      setState(() {
        _msg = problem;
        _ok = false;
      });
      return;
    }
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final res = await apiClient.put('/auth/me/password', {'current_password': _cur.text, 'new_password': _new.text});
      if (!mounted) return;
      final ok = res.statusCode == 200;
      String detail = 'Could not change password (minimum 6 characters).';
      try {
        final d = jsonDecode(res.body)['detail'];
        if (d is String) detail = d;
      } catch (_) {}
      setState(() {
        _ok = ok;
        _msg = ok ? 'Password changed.' : detail;
        if (ok) {
          _cur.clear();
          _new.clear();
          _new2.clear();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _msg = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
                const Expanded(child: ScreenTitle(title: 'Change Password', subtitle: 'Use at least 6 characters')),
                SmallPill(label: '← Back', onTap: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            DocCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_msg != null) MessageBanner(_msg!, success: _ok),
                  DocField(label: 'Current Password', controller: _cur, obscure: true),
                  DocField(label: 'New Password', controller: _new, obscure: true),
                  DocField(label: 'Type Again New Password', controller: _new2, obscure: true),
                  PillButton(label: 'Change Password', loading: _saving, onPressed: _save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
//Added By Nikhil 22Nov26 16:52 For Change Password on its own page (opened from Profile → Security) END
