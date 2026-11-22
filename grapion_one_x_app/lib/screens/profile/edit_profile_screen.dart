// //Added By Nikhil 22Nov26 17:36 For Edit Profile on its own page (name, username, email, mobile; password asked on Save)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import '../auth/register_screen.dart' show Country, CountryPickerSheet, flagOf;

/// Logins created by a gym owner without an email get `username@members.invalid` — never show it as a real email.
bool isPlaceholderEmail(String? e) => e == null || e.isEmpty || e.toLowerCase().endsWith('@members.invalid');

/// Round avatar with initials ("Nikhil Test" → "NT").
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.first, required this.last, this.size = 56});
  final String first;
  final String last;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.primaryDark]),
      ),
      child: Text(
        initialsOf(first, last),
        style: TextStyle(color: Colors.white, fontSize: size * 0.36, fontWeight: FontWeight.w800, letterSpacing: 1),
      ),
    );
  }
}

/// Pops `true` when the profile was saved, so the Profile page reloads.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  List<Country> _countries = const [];
  Country? _country;
  String _saved = '';
  bool _loading = true;
  bool _saving = false;
  String? _msg;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_first, _last]) {
      c.addListener(() => setState(() {})); // live initials
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _username, _email, _mobile]) {
      c.dispose();
    }
    super.dispose();
  }

  String _key() => [_first.text.trim(), _last.text.trim(), _username.text.trim().toLowerCase(), _email.text.trim().toLowerCase(),
        _country?.code ?? '', _mobile.text.replaceAll(' ', '')].join('|');

  Future<void> _load() async {
    try {
      final r = await Future.wait([apiClient.get('/auth/me/profile'), apiClient.get('/meta/countries')]);
      if (!mounted) return;
      if (r[0].statusCode != 200) throw Exception('profile');
      final p = jsonDecode(r[0].body);
      final countries = r[1].statusCode == 200
          ? (jsonDecode(r[1].body)['countries'] as List).map((e) => Country.fromJson(e as Map<String, dynamic>)).toList()
          : <Country>[];
      setState(() {
        _first.text = p['first_name'] ?? '';
        _last.text = p['last_name'] ?? '';
        _username.text = p['username'] ?? '';
        _email.text = isPlaceholderEmail(p['email'] as String?) ? '' : (p['email'] ?? ''); // owner-created logins get name@members.invalid
        _mobile.text = p['mobile_number'] ?? '';
        _countries = countries;
        _country = countries.where((c) => c.code == p['country_code']).firstOrNull ??
            Country(code: p['country_code'] ?? 'IN', name: p['country_code'] ?? 'IN', dial: p['dial_code'] ?? '+91', currency: 'INR', symbol: '₹');
        _saved = _key();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  void _pickCountry() {
    if (_countries.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => CountryPickerSheet(
        countries: _countries,
        onSelected: (c) {
          setState(() => _country = c);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _save() async {
    if (_key() == _saved) {
      setState(() {
        _msg = 'No changes to save.';
        _ok = false;
      });
      return;
    }
    final password = await showDialog<String>(context: context, builder: (_) => const ConfirmPasswordDialog());
    if (password == null || password.isEmpty || !mounted) return;
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final res = await apiClient.put('/auth/me/profile', {
        'current_password': password,
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'username': _username.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(), // blank = keep current
        'country_code': _country?.code,
        'dial_code': _country?.dial,
        'mobile_number': _mobile.text.replaceAll(' ', ''),
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
        Navigator.pop(context, true);
        return;
      }
      String detail = 'Could not update your profile. Check the details.';
      try {
        final d = jsonDecode(res.body)['detail'];
        if (d is String) detail = d;
        if (d is List && d.isNotEmpty) detail = 'Check ${(d.first['loc'] as List).last}: ${d.first['msg']}';
      } catch (_) {}
      setState(() {
        _msg = detail;
        _ok = false;
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
                const Expanded(child: ScreenTitle(title: 'Edit Profile', subtitle: 'Your password is asked when you save')),
                SmallPill(label: '← Back', onTap: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              )
            else ...[
              Center(child: InitialsAvatar(first: _first.text, last: _last.text, size: 76)),
              const SizedBox(height: 16),
              DocCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_msg != null) MessageBanner(_msg!, success: _ok),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: DocField(label: 'First Name', controller: _first)),
                        const SizedBox(width: 10),
                        Expanded(child: DocField(label: 'Last Name', controller: _last)),
                      ],
                    ),
                    DocField(label: 'Username', controller: _username, hint: 'letters, numbers, _ and .'),
                    DocField(label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress, hint: 'Add your email (optional)'),
                    const FieldLabel('Country & Mobile Number'),
                    Row(
                      children: [
                        Material(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                            side: const BorderSide(color: AppTheme.borderSubtle),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                            onTap: _pickCountry,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_country != null) flagOf(_country!.code),
                                  const SizedBox(width: 8),
                                  Text(_country?.dial ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 8),
                                  const Text('▼', style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _mobile,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(15)],
                            decoration: const InputDecoration(hintText: '98234 11223'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    PillButton(label: 'Save', loading: _saving, onPressed: _save),
                    const SizedBox(height: 8),
                    PillButton(label: 'Cancel', variant: PillVariant.secondary, onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Confirm it's you" — returns the typed password, or null when cancelled. Owns its controller (disposed with the dialog).
class ConfirmPasswordDialog extends StatefulWidget {
  const ConfirmPasswordDialog({super.key});

  @override
  State<ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<ConfirmPasswordDialog> {
  final _pwd = TextEditingController();

  @override
  void dispose() {
    _pwd.dispose();
    super.dispose();
  }

  void _ok() {
    if (_pwd.text.isNotEmpty) Navigator.pop(context, _pwd.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text("Confirm it's you", style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter your current password to save these changes.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          DocField(label: 'Current password', controller: _pwd, obscure: true, onSubmitted: (_) => _ok()),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _ok, child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800))),
      ],
    );
  }
}
