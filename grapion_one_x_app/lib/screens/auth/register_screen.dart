// //Added By Nikhil 18Nov26 21:35 For Registration with Flag & Dial Code Picker
//Modified By Nikhil 21Nov26 21:00 For Create Account matching ui_prototype_docspot. Old: full file backed up at D:\AI Agents Temp\grapion-one-x\GrapionOneX_DocSpot_CleanUI\21Nov26\backup\allscreens_2100_DesignMatch\ START
import 'dart:convert';

import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import '../subscription/receipt_gate_screen.dart';

class Country {
  final String code;
  final String name;
  final String dial;
  final String currency;
  final String symbol;

  const Country({
    required this.code,
    required this.name,
    required this.dial,
    required this.currency,
    required this.symbol,
  });

  factory Country.fromJson(Map<String, dynamic> j) => Country(
        code: j['code'] as String,
        name: j['name'] as String,
        dial: j['dial'] as String,
        currency: j['currency'] as String,
        symbol: (j['symbol'] as String).trim(),
      );
}

// Used only until GET /meta/countries answers (or if it fails), so registration is never blocked.
const _fallbackCountry = Country(code: 'IN', name: 'India', dial: '+91', currency: 'INR', symbol: '₹');

/// Bundled flag image (no network) — country_flags package.
Widget flagOf(String code) => CountryFlag.fromCountryCode(
      code,
      theme: const ImageTheme(width: 24, height: 16, shape: RoundedRectangle(3)),
    );

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  List<Country> _countries = const [_fallbackCountry];
  Country _selectedCountry = _fallbackCountry;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  @override
  void dispose() {
    for (final c in [_firstNameCtrl, _lastNameCtrl, _emailCtrl, _userCtrl, _passCtrl, _pass2Ctrl, _phoneCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCountries() async {
    try {
      final res = await apiClient.get('/meta/countries');
      if (res.statusCode != 200) return;
      final list = (jsonDecode(res.body)['countries'] as List)
          .map((e) => Country.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted || list.isEmpty) return;
      setState(() {
        _countries = list;
        _selectedCountry = list.firstWhere((c) => c.code == _selectedCountry.code, orElse: () => list.first);
      });
    } catch (_) {
      // Keep the fallback list; the picker still works with India.
    }
  }

  void _showCountryPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x730F172A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => CountryPickerSheet(
        countries: _countries,
        onSelected: (c) {
          setState(() => _selectedCountry = c);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _handleRegister() async {
    final fn = _firstNameCtrl.text.trim();
    final ln = _lastNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final username = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    final pass2 = _pass2Ctrl.text;
    final phone = _phoneCtrl.text.replaceAll(' ', '').trim();

    if ([fn, ln, email, username, pass, pass2, phone].any((v) => v.isEmpty)) {
      setState(() => _error = 'Please fill all required fields');
      return;
    }
    if (pass != pass2) {
      setState(() => _error = 'Passwords do not match');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await apiClient.post('/auth/register', {
        'first_name': fn,
        'last_name': ln,
        'email': email,
        'username': username,
        'password': pass,
        'country_code': _selectedCountry.code,
        'dial_code': _selectedCountry.dial,
        'mobile_number': phone,
      });

      final data = jsonDecode(res.body);
      if (res.statusCode == 201) {
        await apiClient.saveToken(data['access_token']);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          docRoute(const ReceiptGateScreen(isSubscribed: false)),
          (_) => false,
        );
      } else {
        final detail = data['detail'];
        setState(() => _error = detail is String ? detail : 'Registration failed. Please check the details.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Connection error. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: kScreenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SmallPill(label: '← Sign In', onTap: () => Navigator.pop(context)),
              ),
              const SizedBox(height: 18),
              const ScreenTitle(
                title: 'Create Account',
                subtitle: 'Country determines dynamic currency & pricing',
              ),
              const SizedBox(height: 16),

              if (_error != null) MessageBanner(_error!),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: DocField(label: 'First Name', controller: _firstNameCtrl, hint: 'e.g. Aarav')), //Modified By Nikhil 22Nov26 12:22 For neutral placeholder. Old: 'Nikhil'
                  const SizedBox(width: 10),
                  Expanded(child: DocField(label: 'Last Name', controller: _lastNameCtrl, hint: 'e.g. Sharma')), //Modified By Nikhil 22Nov26 12:22 For neutral placeholder. Old: 'Kamble'
                ],
              ),
              DocField(
                label: 'Gmail / Email Address',
                controller: _emailCtrl,
                hint: 'name@gmail.com',
                keyboardType: TextInputType.emailAddress,
              ),

              // Country & Mobile Number
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
                      onTap: _showCountryPicker,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            flagOf(_selectedCountry.code),
                            const SizedBox(width: 8),
                            Text(
                              _selectedCountry.dial,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                            ),
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
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(15)],
                      style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                      decoration: const InputDecoration(hintText: '98234 11223'),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 14),
                child: Text(
                  '✓ Currency: ${_selectedCountry.name} (${_selectedCountry.symbol} ${_selectedCountry.currency})',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary),
                ),
              ),

              DocField(label: 'Username (Used for login)', controller: _userCtrl, hint: 'e.g. aarav_sharma'), //Modified By Nikhil 22Nov26 12:22 For neutral placeholder. Old: 'nikhil_kamble'
              DocField(label: 'Password', controller: _passCtrl, hint: 'Enter secure password', obscure: true),
              DocField(label: 'Repeat Password', controller: _pass2Ctrl, hint: 'Re-enter password', obscure: true),

              const SizedBox(height: 10),
              PillButton(
                label: 'Register Account',
                variant: PillVariant.accent,
                loading: _loading,
                onPressed: _handleRegister,
              ),
              const SizedBox(height: 14),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Already have an account? ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
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
}

//Modified By Nikhil 21Nov26 22:36 For reuse in Profile (was private _CountryPickerSheet)
/// .country-modal-sheet — 70% height, search, flag + name + currency chip + dial code.
class CountryPickerSheet extends StatefulWidget {
  const CountryPickerSheet({super.key, required this.countries, required this.onSelected});

  final List<Country> countries;
  final ValueChanged<Country> onSelected;

  @override
  State<CountryPickerSheet> createState() => CountryPickerSheetState();
}

class CountryPickerSheetState extends State<CountryPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.countries
        .where((c) => c.name.toLowerCase().contains(q) || c.dial.contains(q) || c.code.toLowerCase().contains(q))
        .toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 10 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.borderSubtle, borderRadius: BorderRadius.circular(4)),
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select Country & Code',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Text('×', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textMuted)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              autofocus: false,
              onChanged: (v) => setState(() => _q = v.trim()),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '🔍 Search country name or code...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: const BorderSide(color: AppTheme.borderSubtle)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: const BorderSide(color: AppTheme.borderSubtle)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: const BorderSide(color: AppTheme.textPrimary)),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('No country matches your search', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (ctx, i) {
                        final c = list[i];
                        return InkWell(
                          onTap: () => widget.onSelected(c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.cardBorder))),
                            child: Row(
                              children: [
                                flagOf(c.code),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(c.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                                ),
                                StatusChip(
                                  c.currency,
                                  bg: AppTheme.successLight,
                                  fg: AppTheme.primary,
                                  radius: 4,
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    c.dial,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
//Modified By Nikhil 21Nov26 21:00 For Create Account matching ui_prototype_docspot END
