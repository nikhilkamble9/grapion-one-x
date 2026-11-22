// //Added By Nikhil 22Nov26 01:22 For Super Admin pages (admins, module pricing, sales & discounts, audit history)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';

// ---------------- Control tab (inside the admin dashboard) ----------------

class SuperAdminHomeTab extends StatelessWidget {
  const SuperAdminHomeTab({super.key, required this.header, this.bottomPadding = 100});
  final Widget header;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, String, Widget?)>[
      ('🛡️', 'Admins', 'Make or remove admins, disable accounts', const AdminsScreen()),
      ('💳', 'Module Pricing', 'Weekly, monthly, quarterly & yearly prices', const ModulePricingScreen()),
      ('🎉', 'Sales & Discounts', 'Create sales like Black Friday', const DiscountsScreen()),
      ('📜', 'Audit History', 'Every important action, who and when', const AuditScreen()),
      //Modified By Nikhil 22Nov26 08:35 For Platform Settings + announcements screens. Old: ('⚙️', 'Platform Settings', 'Coming next', null),
      ('⚙️', 'Platform Settings', 'Support contact & default reminder days', const PlatformSettingsScreen()),
      ('📣', 'Announcements', 'Banners shown inside the app', const AnnouncementsScreen()), //Added By Nikhil 22Nov26 08:35 For announcement banners
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(22, 16, 22, bottomPadding),
      children: [
        header,
        for (final (icon, title, sub, screen) in items)
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            onTap: () => screen == null ? showDevModuleDialog(context, title) : Navigator.of(context).push(docRoute(screen)),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      Text(sub, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                if (screen == null)
                  const StatusChip('🚧', bg: Color(0xFFFFFBEB), fg: AppTheme.warningOrange)
                else
                  const Icon(Icons.chevron_right, color: AppTheme.textSubtle),
              ],
            ),
          ),
      ],
    );
  }
}

/// Shared page frame: title + back pill + pull to refresh.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.subtitle, required this.onRefresh, required this.children, this.action});
  final String title;
  final String subtitle;
  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: action,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 90),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ScreenTitle(title: title, subtitle: subtitle)),
                  SmallPill(label: '← Back', onTap: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

void _toast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

const _loading = Padding(
  padding: EdgeInsets.symmetric(vertical: 60),
  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
);

// ---------------- Admins ----------------

class AdminsScreen extends StatefulWidget {
  const AdminsScreen({super.key});
  @override
  State<AdminsScreen> createState() => _AdminsScreenState();
}

class _AdminsScreenState extends State<AdminsScreen> {
  List<dynamic>? _admins;
  final _userCtrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await apiClient.get('/superadmin/admins');
    if (!mounted) return;
    setState(() => _admins = res.statusCode == 200 ? jsonDecode(res.body)['admins'] : []);
  }

  Future<void> _do(Future<dynamic> Function() call, String ok) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      if (!mounted) return;
      _toast(context, res.statusCode == 200 ? ok : apiDetail(res.body, 'Could not update'));
      await _load();
    } catch (_) {
      if (mounted) _toast(context, 'Connection error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Admins',
      subtitle: 'Only you (Super Admin) can change this list',
      onRefresh: _load,
      children: [
        DocCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DocField(label: 'Make a registered user an admin', controller: _userCtrl, hint: 'Exact username'),
              PillButton(
                label: 'Make Admin',
                variant: PillVariant.accent,
                loading: _busy,
                onPressed: () {
                  final u = _userCtrl.text.trim();
                  if (u.length < 3) return _toast(context, 'Enter the exact username');
                  _do(() => apiClient.post('/superadmin/admins/promote', {'username': u}), '@$u is now an admin');
                  _userCtrl.clear();
                },
              ),
            ],
          ),
        ),
        if (_admins == null) _loading,
        for (final a in _admins ?? [])
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(a['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                    StatusChip(
                      a['role'] == 'super_admin' ? 'Super Admin' : (a['is_active'] == true ? 'Admin' : 'Disabled'),
                      bg: a['role'] == 'super_admin'
                          ? AppTheme.pillDark
                          : (a['is_active'] == true ? AppTheme.successLight : AppTheme.errorLight),
                      fg: a['role'] == 'super_admin'
                          ? Colors.white
                          : (a['is_active'] == true ? AppTheme.primaryDark : AppTheme.errorRed),
                      fontSize: 10,
                    ),
                  ],
                ),
                Text('@${a['username']} • ${a['mobile']}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                if (a['role'] == 'admin') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: PillButton(
                          label: a['is_active'] == true ? 'Disable' : 'Enable',
                          variant: PillVariant.secondary,
                          padding: const EdgeInsets.all(9),
                          fontSize: 12,
                          onPressed: _busy
                              ? null
                              : () => _do(
                                    () => apiClient.post('/superadmin/admins/${a['id']}/active', {'is_active': a['is_active'] != true}),
                                    a['is_active'] == true ? 'Admin disabled' : 'Admin enabled',
                                  ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PillButton(
                          label: 'Remove Admin',
                          variant: PillVariant.secondary,
                          foreground: AppTheme.errorRed,
                          padding: const EdgeInsets.all(9),
                          fontSize: 12,
                          onPressed: _busy
                              ? null
                              : () => _do(() => apiClient.post('/superadmin/admins/${a['id']}/demote', {}), 'Admin removed — now a normal user'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------- Module pricing ----------------

class ModulePricingScreen extends StatefulWidget {
  const ModulePricingScreen({super.key});
  @override
  State<ModulePricingScreen> createState() => _ModulePricingScreenState();
}

class _ModulePricingScreenState extends State<ModulePricingScreen> {
  static const _periods = ['weekly', 'monthly', 'quarterly', 'yearly'];
  List<dynamic>? _modules;
  final Map<String, Map<String, TextEditingController>> _ctrls = {};
  String? _saving;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final m in _ctrls.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await apiClient.get('/superadmin/modules');
    if (!mounted) return;
    final mods = res.statusCode == 200 ? jsonDecode(res.body)['modules'] as List : [];
    for (final m in mods) {
      final map = _ctrls.putIfAbsent(m['code'], () => {for (final p in _periods) p: TextEditingController()});
      for (final p in _periods) {
        map[p]!.text = '${(m['prices'] as Map)[p] ?? 0}';
      }
    }
    setState(() => _modules = mods);
  }

  Future<void> _save(String code) async {
    final body = {for (final p in _periods) p: int.tryParse(_ctrls[code]![p]!.text) ?? -1};
    if (body.values.any((v) => v < 0)) return _toast(context, 'Enter whole-rupee prices (0 or more)');
    setState(() => _saving = code);
    try {
      final res = await apiClient.put('/superadmin/modules/$code/prices', body);
      if (!mounted) return;
      _toast(context, res.statusCode == 200 ? 'Prices saved — new requests use them' : apiDetail(res.body, 'Could not save'));
    } catch (_) {
      if (mounted) _toast(context, 'Connection error');
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Module Pricing',
      subtitle: 'Prices in ₹ (INR). Existing requests keep their old price.',
      onRefresh: _load,
      children: [
        if (_modules == null) _loading,
        for (final m in _modules ?? [])
          DocCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(m['icon'] ?? '📦', style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Text(m['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 12),
                //Modified By Nikhil 22Nov26 10:47 For 2×2 price grid, one-line labels, full amounts visible. Old: one Row of 4 fields, label '<Period> ₹' START
                for (final pair in [_periods.take(2).toList(), _periods.skip(2).toList()])
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in pair) ...[
                        if (p != pair.first) const SizedBox(width: 10),
                        Expanded(
                          child: DocField(
                            label: '${p[0].toUpperCase()}${p.substring(1)} (₹)',
                            controller: _ctrls[m['code']]![p]!,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                          ),
                        ),
                      ],
                    ],
                  ),
                //Modified By Nikhil 22Nov26 10:47 For 2×2 price grid END
                PillButton(
                  label: 'Save ${m['name']} Prices',
                  loading: _saving == m['code'],
                  padding: const EdgeInsets.all(11),
                  fontSize: 13,
                  onPressed: _saving == null ? () => _save(m['code'] as String) : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------- Sales & discounts ----------------

class DiscountsScreen extends StatefulWidget {
  const DiscountsScreen({super.key});
  @override
  State<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends State<DiscountsScreen> {
  List<dynamic>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await apiClient.get('/superadmin/discounts');
    if (!mounted) return;
    setState(() => _items = res.statusCode == 200 ? jsonDecode(res.body)['discounts'] : []);
  }

  Future<void> _edit([Map<String, dynamic>? d]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _DiscountEditor(existing: d),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Sales & Discounts',
      subtitle: 'Shown in the store during the sale dates (IST)',
      onRefresh: _load,
      action: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Sale', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      children: [
        if (_items == null) _loading,
        if (_items != null && _items!.isEmpty)
          const DocCard(child: Center(child: Text('No sales yet.', style: TextStyle(color: AppTheme.textMuted)))),
        for (final d in _items ?? [])
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            onTap: () => _edit(Map<String, dynamic>.from(d)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('🎉 ${d['title']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                    StatusChip(
                      d['is_live'] == true ? 'Live' : (d['is_active'] == true ? 'Scheduled / ended' : 'Off'),
                      bg: d['is_live'] == true ? AppTheme.successLight : AppTheme.chipBg,
                      fg: d['is_live'] == true ? AppTheme.primaryDark : AppTheme.textMuted,
                      fontSize: 10,
                    ),
                  ],
                ),
                Text(
                  '${formatServerDateTime('${d['start_date']}T00:00:00', withTime: false)} – ${formatServerDateTime('${d['end_date']}T00:00:00', withTime: false)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  'Weekly ${(d['period_percent_off'] as Map)['weekly']}% • Monthly ${(d['period_percent_off'] as Map)['monthly']}% • '
                  'Quarterly ${(d['period_percent_off'] as Map)['quarterly']}% • Yearly ${(d['period_percent_off'] as Map)['yearly']}%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.label),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DiscountEditor extends StatefulWidget {
  const _DiscountEditor({this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<_DiscountEditor> createState() => _DiscountEditorState();
}

class _DiscountEditorState extends State<_DiscountEditor> {
  static const _periods = ['weekly', 'monthly', 'quarterly', 'yearly'];
  late final _title = TextEditingController(text: widget.existing?['title'] ?? '');
  late final Map<String, TextEditingController> _pct = {
    for (final p in _periods)
      p: TextEditingController(text: '${(widget.existing?['period_percent_off'] as Map?)?[p] ?? ''}'.replaceAll('.0', '')),
  };
  late DateTime _start = DateTime.tryParse(widget.existing?['start_date'] ?? '') ?? DateTime.now();
  late DateTime _end = DateTime.tryParse(widget.existing?['end_date'] ?? '') ?? DateTime.now().add(const Duration(days: 4));
  late bool _active = widget.existing?['is_active'] ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    for (final c in _pct.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    final body = {
      'title': _title.text.trim(),
      for (final p in _periods) p: double.tryParse(_pct[p]!.text.trim()) ?? 0,
      'start_date': _d(_start),
      'end_date': _d(_end),
      'is_active': _active,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.existing?['id'];
      final res = id == null ? await apiClient.post('/superadmin/discounts', body) : await apiClient.put('/superadmin/discounts/$id', body);
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        Navigator.pop(context, true);
      } else {
        String msg = apiDetail(res.body, '');
        if (msg.isEmpty) {
          msg = 'Check the title (min 2 letters), percentages (0–100, at least one above 0) and that the end date is not before the start.';
        }
        setState(() => _error = msg);
      }
    } catch (_) {
      setState(() => _error = 'Connection error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppTheme.borderSubtle, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Text(widget.existing == null ? 'New Sale' : 'Edit Sale', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (_error != null) MessageBanner(_error!),
            DocField(label: 'Sale title', controller: _title, hint: 'e.g. Black Friday Sale'),
            const FieldLabel('Discount % per period'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in _periods) ...[
                  if (p != 'weekly') const SizedBox(width: 6),
                  Expanded(
                    child: DocField(
                      label: '${p[0].toUpperCase()}${p.substring(1)}',
                      controller: _pct[p]!,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), LengthLimitingTextInputFormatter(5)],
                    ),
                  ),
                ],
              ],
            ),
            Row(
              children: [
                Expanded(child: _dateBox('Starts', _start, () => _pick(true))),
                const SizedBox(width: 8),
                Expanded(child: _dateBox('Ends (whole day)', _end, () => _pick(false))),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              activeThumbColor: AppTheme.primary,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Sale is on', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            PillButton(label: 'Save Sale', variant: PillVariant.accent, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }

  Widget _dateBox(String label, DateTime d, VoidCallback onTap) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label),
          Material(
            color: AppTheme.cardSubtle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              side: const BorderSide(color: AppTheme.borderSubtle),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.event, size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 8),
                    Text(formatServerDateTime('${_d(d)}T00:00:00', withTime: false), style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
}

// ---------------- Audit history ----------------

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final List<dynamic> _items = [];
  String? _next;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    setState(() => _loading = true);
    final cursor = reset ? null : _next;
    final res = await apiClient.get('/superadmin/audit?limit=50${cursor != null ? '&before=${Uri.encodeQueryComponent(cursor)}' : ''}');
    if (!mounted) return;
    setState(() {
      if (reset) _items.clear();
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        _items.addAll(d['items'] as List);
        _next = d['next_before'];
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Audit History',
      subtitle: 'Newest first • server time (IST)',
      onRefresh: () => _load(reset: true),
      children: [
        if (_items.isEmpty && _loading) _loading_,
        if (_items.isEmpty && !_loading)
          const DocCard(child: Center(child: Text('No actions recorded yet.', style: TextStyle(color: AppTheme.textMuted)))),
        for (final a in _items)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.cardSubtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(a['action'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                    Text(formatServerDateTime(a['when'] as String?), style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                  ],
                ),
                Text('${a['actor']} • ${a['entity']}', style: const TextStyle(fontSize: 11, color: AppTheme.label)),
                if (a['detail'] != null)
                  Text(
                    jsonEncode(a['detail']),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSubtle),
                  ),
              ],
            ),
          ),
        if (_next != null)
          PillButton(label: 'Load more', variant: PillVariant.secondary, loading: _loading, onPressed: () => _load()),
      ],
    );
  }

  static const _loading_ = Padding(
    padding: EdgeInsets.symmetric(vertical: 60),
    child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
  );
}

//Added By Nikhil 22Nov26 08:35 For Platform Settings + announcement banners START
// ---------------- Platform settings ----------------

class PlatformSettingsScreen extends StatefulWidget {
  const PlatformSettingsScreen({super.key});
  @override
  State<PlatformSettingsScreen> createState() => _PlatformSettingsScreenState();
}

class _PlatformSettingsScreenState extends State<PlatformSettingsScreen> {
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _whatsapp = TextEditingController();
  final _hours = TextEditingController();
  final _days = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_phone, _email, _whatsapp, _hours, _days]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await apiClient.get('/superadmin/settings');
    if (!mounted) return;
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      final s = d['support_contact'] as Map;
      _phone.text = s['phone'] ?? '';
      _email.text = s['email'] ?? '';
      _whatsapp.text = s['whatsapp'] ?? '';
      _hours.text = s['hours'] ?? '';
      _days.text = '${d['default_reminder_days']}';
    }
    setState(() => _loaded = true);
  }

  Future<void> _save() async {
    final days = int.tryParse(_days.text.trim());
    if (days == null || days < 1 || days > 60) return setState(() => _error = 'Reminder days must be between 1 and 60');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await apiClient.put('/superadmin/settings', {
        'support_contact': {
          'phone': _phone.text.trim(),
          'email': _email.text.trim(),
          'whatsapp': _whatsapp.text.trim(),
          'hours': _hours.text.trim(),
        },
        'default_reminder_days': days,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        _toast(context, 'Settings saved');
      } else {
        setState(() => _error = apiDetail(res.body, 'Check the phone numbers (digits, + and -) and the email format'));
      }
    } catch (_) {
      setState(() => _error = 'Connection error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Platform Settings',
      subtitle: 'Applies to every user of the app',
      onRefresh: _load,
      children: [
        if (!_loaded) _loading,
        if (_loaded) ...[
          if (_error != null) MessageBanner(_error!),
          DocCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🆘 Support contact', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const Text('Shown in Profile → Help & support. Leave a field empty to hide it.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(height: 12),
                DocField(label: 'Phone', controller: _phone, hint: '+91 98xxxxxxxx', keyboardType: TextInputType.phone),
                DocField(label: 'WhatsApp', controller: _whatsapp, hint: '+91 98xxxxxxxx', keyboardType: TextInputType.phone),
                DocField(label: 'Email', controller: _email, hint: 'support@…', keyboardType: TextInputType.emailAddress),
                DocField(label: 'Support hours', controller: _hours, hint: 'e.g. Mon–Sat, 10 AM – 7 PM'),
              ],
            ),
          ),
          DocCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⏰ Default reminder days', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                //Modified By Nikhil 22Nov26 10:47 For reminder days apply to every module. Old: '... New gym branches start with this value (owners can change it per branch).'
                const Text('How many days before an expiry the reminders start — for every module (Gym, Wedding, Medical, Academy). '
                    'Each new business starts with this value; owners can change it for their own business.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(height: 12),
                DocField(
                  label: 'Days (1–60)',
                  controller: _days,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                ),
              ],
            ),
          ),
          PillButton(label: 'Save Settings', variant: PillVariant.accent, loading: _saving, onPressed: _save),
        ],
      ],
    );
  }
}

// ---------------- Announcements ----------------

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<dynamic>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await apiClient.get('/superadmin/announcements');
    if (!mounted) return;
    setState(() => _items = res.statusCode == 200 ? jsonDecode(res.body)['announcements'] : []);
  }

  Future<void> _edit([Map<String, dynamic>? a]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _AnnouncementEditor(existing: a),
    );
    if (saved == true) _load();
  }

  static const _audience = {'all': 'Everyone', 'users': 'Users only', 'admins': 'Admins only'};

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'Announcements',
      subtitle: 'Banners at the top of the app during the dates (IST)',
      onRefresh: _load,
      action: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Banner', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      children: [
        if (_items == null) _loading,
        if (_items != null && _items!.isEmpty)
          const DocCard(child: Center(child: Text('No announcements yet.', style: TextStyle(color: AppTheme.textMuted)))),
        for (final a in _items ?? [])
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            onTap: () => _edit(Map<String, dynamic>.from(a)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('📣 ${a['title']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                    StatusChip(
                      a['is_live'] == true ? 'Live' : (a['is_active'] == true ? 'Scheduled / ended' : 'Off'),
                      bg: a['is_live'] == true ? AppTheme.successLight : AppTheme.chipBg,
                      fg: a['is_live'] == true ? AppTheme.primaryDark : AppTheme.textMuted,
                      fontSize: 10,
                    ),
                  ],
                ),
                Text(a['message'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  '${_audience[a['audience']] ?? a['audience']} • '
                  '${formatServerDateTime('${a['start_date']}T00:00:00', withTime: false)} – '
                  '${formatServerDateTime('${a['end_date']}T00:00:00', withTime: false)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AnnouncementEditor extends StatefulWidget {
  const _AnnouncementEditor({this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<_AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<_AnnouncementEditor> {
  late final _title = TextEditingController(text: widget.existing?['title'] ?? '');
  late final _message = TextEditingController(text: widget.existing?['message'] ?? '');
  late String _style = widget.existing?['style'] ?? 'info';
  late String _audience = widget.existing?['audience'] ?? 'all';
  late DateTime _start = DateTime.tryParse(widget.existing?['start_date'] ?? '') ?? DateTime.now();
  late DateTime _end = DateTime.tryParse(widget.existing?['end_date'] ?? '') ?? DateTime.now().add(const Duration(days: 3));
  late bool _active = widget.existing?['is_active'] ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    final body = {
      'title': _title.text.trim(),
      'message': _message.text.trim(),
      'style': _style,
      'audience': _audience,
      'start_date': _d(_start),
      'end_date': _d(_end),
      'is_active': _active,
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.existing?['id'];
      final res = id == null
          ? await apiClient.post('/superadmin/announcements', body)
          : await apiClient.put('/superadmin/announcements/$id', body);
      if (!mounted) return;
      if (res.statusCode == 200 || res.statusCode == 201) {
        Navigator.pop(context, true);
      } else {
        final msg = apiDetail(res.body, '');
        setState(() => _error = msg.isEmpty ? 'Title and message need at least 2 letters; end date not before start.' : msg);
      }
    } catch (_) {
      setState(() => _error = 'Connection error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dateBox(String label, DateTime d, VoidCallback onTap) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label),
          Material(
            color: AppTheme.cardSubtle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              side: const BorderSide(color: AppTheme.borderSubtle),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.event, size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 8),
                    Text(formatServerDateTime('${_d(d)}T00:00:00', withTime: false), style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppTheme.borderSubtle, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Text(widget.existing == null ? 'New Banner' : 'Edit Banner', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (_error != null) MessageBanner(_error!),
            DocField(label: 'Title', controller: _title, hint: 'e.g. Scheduled maintenance'),
            DocField(label: 'Message', controller: _message, hint: 'What users should know'),
            const FieldLabel('Style'),
            SegmentTabs(
              options: const {'info': 'ℹ️ Info', 'success': '✅ Good news', 'warning': '⚠️ Warning'},
              selected: _style,
              onChanged: (k) => setState(() => _style = k),
            ),
            const SizedBox(height: 12),
            const FieldLabel('Who sees it'),
            SegmentTabs(
              options: const {'all': 'Everyone', 'users': 'Users', 'admins': 'Admins'},
              selected: _audience,
              onChanged: (k) => setState(() => _audience = k),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _dateBox('Show from', _start, () => _pick(true))),
                const SizedBox(width: 8),
                Expanded(child: _dateBox('Until (whole day)', _end, () => _pick(false))),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              activeThumbColor: AppTheme.primary,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Banner is on', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            PillButton(label: 'Save Banner', variant: PillVariant.accent, loading: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
//Added By Nikhil 22Nov26 08:35 For Platform Settings + announcement banners END
