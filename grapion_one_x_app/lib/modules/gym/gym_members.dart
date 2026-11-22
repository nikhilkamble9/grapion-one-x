// //Added By Nikhil 22Nov26 08:41 For Grapion Gym members (list, add by exact search or new login, detail, plans, payments, check-in) + payments screen
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import 'gym_common.dart';

const _states = {'': 'All', 'active': 'Active', 'expiring': 'Expiring', 'expired': 'Expired', 'none': 'No plan', 'invited': 'Invited'};

(Color, Color, String) stateLook(String? s, int? daysLeft) => switch (s) {
      'active' => (AppTheme.successLight, AppTheme.primaryDark, 'Active'),
      'expiring' => (const Color(0xFFFFFBEB), AppTheme.warningOrange, daysLeft == 0 ? 'Ends today' : '$daysLeft days left'),
      'expired' => (AppTheme.errorLight, AppTheme.errorRed, 'Expired'),
      'invited' => (const Color(0xFFEFF6FF), AppTheme.accentBlue, 'Invite sent'),
      _ => (AppTheme.chipBg, AppTheme.textMuted, 'No plan'),
    };

// ======================= list =======================

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.ctx, this.branch, this.status});
  final GymCtx ctx;
  final String? branch;
  final String? status;
  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  late String? _branch = widget.branch;
  late String _status = widget.status ?? '';
  final _q = TextEditingController();
  Timer? _debounce;
  final List<dynamic> _items = [];
  int? _next = 0;
  bool _loading = false;
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _next = 0;
    if (_next == null) return;
    setState(() => _loading = true);
    final qs = <String, String>{
      'offset': '$_next',
      'branch_id': ?_branch,
      if (_status.isNotEmpty) 'status': _status,
      if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
    };
    final d = await gymGet(context, '${widget.ctx.base}/members?${Uri(queryParameters: qs).query}');
    if (!mounted) return;
    setState(() {
      if (reset) _items.clear();
      if (d != null) {
        _items.addAll(d['members'] as List);
        _next = d['next_offset'] as int?;
        _canAdd = d['can_add'] == true;
      }
      _loading = false;
    });
  }

  Future<void> _add() async {
    final ok = await Navigator.of(context).push<bool>(docRoute(AddMemberScreen(ctx: widget.ctx, branch: _branch)));
    if (ok == true) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    //Added By Nikhil 22Nov26 10:47 For title + empty message that follow the chosen filter START
    final (title, emptyText) = switch (_status) {
      'active' => ('Active members', 'No active members right now.'),
      'expiring' => ('Expiring soon', 'No memberships are ending soon.'),
      'expired' => ('Expired members', 'No expired members.'),
      'none' => ('Members without a plan', 'Every member has a plan.'),
      'invited' => ('Invited members', 'No invites waiting for an answer.'),
      _ => ('Members', 'No members yet.'),
    };
    final branchLabel = _branch == null ? (widget.ctx.branches.length > 1 ? 'All branches' : null) : widget.ctx.branchName(_branch!);
    //Added By Nikhil 22Nov26 10:47 For title + empty message that follow the chosen filter END
    return GymPage(
      title: title, //Modified By Nikhil 22Nov26 10:47 For filter-aware title. Old: title: 'Members',
      subtitle: [widget.ctx.name, ?branchLabel].join(' • '), //Modified By Nikhil 22Nov26 10:47 For branch in subtitle. Old: subtitle: widget.ctx.name,
      onRefresh: () => _load(reset: true),
      fab: _canAdd ? gymFab('Add Member', _add) : null,
      children: [
        //Modified By Nikhil 22Nov26 10:47 For branch + status dropdowns side by side (status tabs in a sideways scroll crashed the page). Old: BranchChips(...) then SegmentTabs in SingleChildScrollView START
        Row(
          children: [
            if (widget.ctx.branches.length > 1) ...[
              Expanded(
                child: BranchChips(ctx: widget.ctx, selected: _branch, onChanged: (b) {
                  setState(() => _branch = b);
                  _load(reset: true);
                }),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: GymPillDropdown<String>(
                icon: Icons.filter_list_rounded,
                value: _status,
                items: [for (final e in _states.entries) (e.key, e.key.isEmpty ? 'All members' : e.value)],
                onChanged: (k) {
                  setState(() => _status = k);
                  _load(reset: true);
                },
              ),
            ),
          ],
        ),
        //Modified By Nikhil 22Nov26 10:47 For branch + status dropdowns END
        const SizedBox(height: 10),
        DocField(
          label: 'Search',
          controller: _q,
          hint: 'Name, member code or mobile',
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(reset: true),
        ),
        //Removed By Nikhil 22Nov26 10:47 For status tabs replaced by the dropdown above: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SegmentTabs(options: _states, ...))
        const SizedBox(height: 4), //Modified By Nikhil 22Nov26 10:47 For spacing after dropdowns. Old: const SizedBox(height: 12),
        if (_items.isEmpty && _loading) gymLoading,
        //Modified By Nikhil 22Nov26 10:47 For empty state with Add Member. Old: gymEmpty(_canAdd ? 'No members here yet. Tap "Add Member".' : 'No members found.')
        if (_items.isEmpty && !_loading)
          gymEmptyAction(_q.text.trim().isNotEmpty ? 'No members match "${_q.text.trim()}".' : emptyText,
              emoji: '🏋️', actionLabel: _canAdd ? '+ Add Member' : null, onAction: _canAdd ? _add : null),
        for (final m in _items) _MemberTile(m: m, onTap: () async {
          await Navigator.of(context).push(docRoute(MemberDetailScreen(ctx: widget.ctx, id: m['id'] as String)));
          _load(reset: true);
        }),
        if (_next != null && _items.isNotEmpty)
          PillButton(label: 'Load more', variant: PillVariant.secondary, loading: _loading, onPressed: () => _load()),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.m, required this.onTap});
  final dynamic m;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = stateLook(m['state'] as String?, m['days_left'] as int?);
    final name = m['name'] as String? ?? '';
    final parts = name.split(' ');
    return DocCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: onTap,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.chipBg,
                child: Text(initialsOf(parts.first, parts.length > 1 ? parts.last : ''),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.label)),
              ),
              if (m['inside'] == true)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                Text(
                  [m['member_code'], m['plan_name'], m['batch_name']].whereType<String>().join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(label, bg: bg, fg: fg, fontSize: 10),
        ],
      ),
    );
  }
}

// ======================= add member =======================

class AddMemberScreen extends StatefulWidget {
  const AddMemberScreen({super.key, required this.ctx, this.branch});
  final GymCtx ctx;
  final String? branch;
  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  late String _branch = widget.branch ?? widget.ctx.branches.first['id'] as String;
  String _mode = 'search';
  String _searchBy = 'username';
  final _search = TextEditingController();
  List<dynamic> _found = const [];
  Map<String, dynamic>? _picked;
  bool _searching = false;

  final _first = TextEditingController();
  final _last = TextEditingController();
  final _username = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _emergency = TextEditingController();
  String? _gender;

  List<dynamic> _plans = const [];
  List<dynamic> _batches = const [];
  String? _plan;
  String? _batch;
  DateTime _start = DateTime.now();
  bool _pay = true;
  final _amount = TextEditingController();
  String _method = 'cash';
  final _ref = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadBranchData();
  }

  @override
  void dispose() {
    for (final c in [_search, _first, _last, _username, _mobile, _email, _emergency, _amount, _ref]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBranchData() async {
    final p = await gymGet(context, '${widget.ctx.base}/plans?branch_id=$_branch');
    if (!mounted) return;
    final b = await gymGet(context, '${widget.ctx.base}/batches?branch_id=$_branch');
    if (!mounted) return;
    setState(() {
      _plans = ((p?['plans'] as List?) ?? []).where((x) => x['status'] == 'active').toList();
      _batches = ((b?['batches'] as List?) ?? []).where((x) => x['status'] == 'active').toList();
      _plan = null;
      _batch = null;
    });
  }

  Future<void> _doSearch() async {
    final v = _search.text.trim();
    if (v.length < 3) return gymToast(context, 'Type the exact ${_searchBy == 'username' ? 'username' : 'mobile number'}');
    setState(() {
      _searching = true;
      _picked = null;
    });
    final d = await gymGet(context, '/workspaces/${widget.ctx.workspaceId}/people/search?${Uri(queryParameters: {_searchBy: v}).query}');
    if (!mounted) return;
    setState(() {
      _found = (d?['results'] as List?) ?? [];
      _searching = false;
    });
    if (_found.isEmpty) gymToast(context, 'No account with that exact ${_searchBy == 'username' ? 'username' : 'mobile'} — create a new login instead');
  }

  Future<void> _save() async {
    if (_mode == 'search' && _picked == null) return gymToast(context, 'Search and pick the person first');
    if (_mode == 'new' && (_first.text.trim().isEmpty || _last.text.trim().isEmpty || _username.text.trim().length < 3 || _mobile.text.trim().length < 6)) {
      return gymToast(context, 'Fill first & last name, username (3+) and mobile');
    }
    final amount = double.tryParse(_amount.text.trim());
    if (_plan != null && _pay && (amount == null || amount <= 0)) return gymToast(context, 'Enter the amount received, or switch off "Payment received"');
    final body = <String, dynamic>{
      'branch_id': _branch,
      if (_mode == 'search') 'user_id': _picked!['user_id'],
      if (_mode == 'new')
        'login': {
          'first_name': _first.text.trim(),
          'last_name': _last.text.trim(),
          'username': _username.text.trim(),
          'mobile_number': _mobile.text.trim(),
          if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
        },
      'profile': {'gender': ?_gender, 'batch_id': ?_batch, if (_emergency.text.trim().isNotEmpty) 'emergency_contact': _emergency.text.trim()},
      if (_plan != null) ...{
        'plan_id': _plan,
        'start_date': isoDate(_start),
        if (_pay) 'payment': {'amount': amount, 'method': _method, if (_ref.text.trim().isNotEmpty) 'reference_last_digits': _ref.text.trim()},
      },
    };
    setState(() => _saving = true);
    final r = await gymSend(context, 'POST', '${widget.ctx.base}/members', body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r == null) return;
    if (r['temporary_password'] != null) await showTempPassword(context, r['username'], r['temporary_password']);
    if (!mounted) return;
    gymToast(context, r['status'] == 'invited' ? 'Invite sent — they appear as Active once they accept' : 'Member ${r['member_code']} added');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlan = _plans.where((p) => p['id'] == _plan).firstOrNull;
    return GymPage(
      title: 'Add Member',
      subtitle: widget.ctx.name,
      onRefresh: _loadBranchData,
      children: [
        if (widget.ctx.branches.length > 1)
          DocDropdown<String>(
            label: 'Branch',
            value: _branch,
            items: [for (final b in widget.ctx.branches) (b['id'] as String, b['name'] as String)],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _branch = v);
              _loadBranchData();
            },
          ),
        SegmentTabs(
          options: const {'search': '🔎 Has an account', 'new': '➕ Create login'},
          selected: _mode,
          onChanged: (k) => setState(() => _mode = k),
        ),
        const SizedBox(height: 14),
        if (_mode == 'search') ..._searchPart() else ..._newPart(),
        const FieldLabel('Gender (optional)'),
        SegmentTabs(
          options: const {'male': 'Male', 'female': 'Female', 'other': 'Other'},
          selected: _gender ?? '',
          onChanged: (k) => setState(() => _gender = _gender == k ? null : k),
        ),
        const SizedBox(height: 12),
        DocField(label: 'Emergency contact (optional)', controller: _emergency, keyboardType: TextInputType.phone),
        if (_batches.isNotEmpty)
          DocDropdown<String?>(
            label: 'Batch (optional)',
            value: _batch,
            items: [(null, 'No batch'), for (final b in _batches) (b['id'] as String, '${b['name']} • ${time12(b['start_time'])}')],
            onChanged: (v) => setState(() => _batch = v),
          ),
        if (widget.ctx.can('memberships.edit')) ...[
          DocDropdown<String?>(
            label: 'Plan (optional)',
            value: _plan,
            items: [(null, 'No plan yet'), for (final p in _plans) (p['id'] as String, '${p['name']} • ${formatMoney(p['price'] as num)}')],
            onChanged: (v) => setState(() {
              _plan = v;
              final p = _plans.where((x) => x['id'] == v).firstOrNull;
              if (p != null) _amount.text = '${p['price']}';
            }),
          ),
          if (_plans.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('No plans in this branch yet — add them in Plans.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ),
          if (selectedPlan != null) ...[
            PickBox(
              label: 'Starts on',
              value: niceDate(isoDate(_start)),
              icon: Icons.event,
              onTap: () async {
                final d = await pickDate(context, _start, first: DateTime.now().subtract(const Duration(days: 60)));
                if (d != null) setState(() => _start = d);
              },
            ),
            if (widget.ctx.can('payments.record')) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _pay,
                activeThumbColor: AppTheme.primary,
                onChanged: (v) => setState(() => _pay = v),
                title: const Text('Payment received now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              if (_pay) ..._paymentFields(_amount, _method, (m) => setState(() => _method = m), _ref),
            ],
          ],
        ],
        const SizedBox(height: 6),
        PillButton(label: _mode == 'search' ? 'Send Invite' : 'Create Member', variant: PillVariant.accent, loading: _saving, onPressed: _save),
      ],
    );
  }

  List<Widget> _searchPart() => [
        SegmentTabs(
          options: const {'username': 'Exact username', 'mobile': 'Exact mobile'},
          selected: _searchBy,
          onChanged: (k) => setState(() {
            _searchBy = k;
            _found = const [];
            _picked = null;
          }),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DocField(
                label: _searchBy == 'username' ? 'Username' : 'Mobile number',
                controller: _search,
                keyboardType: _searchBy == 'mobile' ? TextInputType.phone : TextInputType.text,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _doSearch(),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: PillButton(label: 'Find', loading: _searching, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), onPressed: _doSearch),
            ),
          ],
        ),
        const Text('For privacy you can only find people by their exact username or mobile — there is no list of all users.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        const SizedBox(height: 10),
        for (final u in _found)
          DocCard(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            borderColor: _picked == u ? AppTheme.primary : AppTheme.cardBorder,
            onTap: () => setState(() => _picked = Map<String, dynamic>.from(u)),
            child: Row(
              children: [
                Icon(_picked == u ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: _picked == u ? AppTheme.primary : AppTheme.textSubtle),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('@${u['username']} • ${u['mobile']}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ];

  List<Widget> _newPart() => [
        Row(
          children: [
            Expanded(child: DocField(label: 'First name', controller: _first)),
            const SizedBox(width: 8),
            Expanded(child: DocField(label: 'Last name', controller: _last)),
          ],
        ),
        DocField(
          label: 'Username',
          controller: _username,
          hint: 'letters, numbers, _ or .',
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.]')), LengthLimitingTextInputFormatter(50)],
        ),
        DocField(
          label: 'Mobile (+91)',
          controller: _mobile,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(15)],
        ),
        DocField(label: 'Email (optional)', controller: _email, keyboardType: TextInputType.emailAddress),
        const Text('A temporary password is created. Give it to them in person — they set their own on first login.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        const SizedBox(height: 12),
      ];
}

/// Amount + method + reference fields shared by every payment form.
List<Widget> _paymentFields(TextEditingController amount, String method, ValueChanged<String> onMethod, TextEditingController ref) => [
      DocField(
        label: 'Amount received (₹)',
        controller: amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')), LengthLimitingTextInputFormatter(10)],
      ),
      SegmentTabs(
        options: const {'cash': '💵 Cash', 'upi': '📱 UPI', 'card': '💳 Card', 'other': 'Other'},
        selected: method,
        onChanged: onMethod,
      ),
      const SizedBox(height: 12),
      if (method != 'cash')
        DocField(
          label: 'Last 4–6 digits of the reference (optional)',
          controller: ref,
          hint: 'Never the full card or UPI number',
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')), LengthLimitingTextInputFormatter(6)],
        ),
    ];

// ======================= detail =======================

class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({super.key, required this.ctx, required this.id});
  final GymCtx ctx;
  final String id;
  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  Map<String, dynamic>? _m;
  bool _busy = false;

  String get _path => '${widget.ctx.base}/members/${widget.id}';
  Map get _can => (_m?['can'] as Map?) ?? const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, _path);
    if (!mounted) return;
    setState(() => _m = d);
  }

  Future<void> _act(String method, String path, Map<String, dynamic> body, String ok) async {
    setState(() => _busy = true);
    final r = await gymSend(context, method, path, body);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      gymToast(context, r['warning'] ?? ok);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    return GymPage(
      title: m?['name'] ?? 'Member',
      subtitle: m == null ? null : '${m['member_code']} • ${m['branch_name']}',
      onRefresh: _load,
      children: m == null ? [gymLoading] : _body(m),
    );
  }

  List<Widget> _body(Map<String, dynamic> m) {
    final ships = (m['memberships'] as List?) ?? [];
    final current = ships.where((s) => s['current'] == true).firstOrNull;
    final latest = ships.isNotEmpty ? ships.first : null;
    return [
      DocCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('@${m['username']} • ${m['mobile']}', style: const TextStyle(fontSize: 12, color: AppTheme.label))),
                if (m['status'] == 'invited')
                  const StatusChip('Invite pending', bg: Color(0xFFEFF6FF), fg: AppTheme.accentBlue, fontSize: 10)
                else if (m['inside'] == true)
                  const StatusChip('Inside now', bg: AppTheme.successLight, fg: AppTheme.primaryDark, fontSize: 10),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              current != null
                  ? '🎫 ${current['plan_name']} — until ${niceDate(current['expiry_date'])}'
                  : latest != null
                      ? '⚠️ Last plan ${latest['plan_name']} ended ${niceDate(latest['expiry_date'])}'
                      : 'No plan yet',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (m['status'] == 'active' && _can['checkin'] == true) ...[
              const SizedBox(height: 12),
              PillButton(
                label: m['inside'] == true ? 'Check Out' : 'Check In',
                variant: m['inside'] == true ? PillVariant.secondary : PillVariant.accent,
                loading: _busy,
                onPressed: () => _act('POST', '$_path/${m['inside'] == true ? 'checkout' : 'checkin'}', {},
                    m['inside'] == true ? 'Checked out' : 'Checked in'),
              ),
            ],
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_can['memberships'] == true) SmallPill(label: current != null ? '🔁 Renew plan' : '🎫 Assign plan', onTap: _assignPlan),
          if (_can['record_payment'] == true && ships.isNotEmpty) SmallPill(label: '💰 Record payment', onTap: _recordPayment),
          if (_can['edit'] == true) SmallPill(label: '✏️ Edit details', onTap: _editProfile),
          if (_can['edit'] == true) SmallPill(label: 'Remove', color: AppTheme.errorRed, onTap: _remove),
        ],
      ),
      const SizedBox(height: 16),
      _section('MEMBERSHIPS'),
      if (ships.isEmpty) gymEmpty('No plans assigned yet.'),
      for (final s in ships)
        DocCard(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 8),
          leftAccent: s['current'] == true ? AppTheme.primary : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['plan_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    Text('${niceDate(s['start_date'])} – ${niceDate(s['expiry_date'])}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    if (s['paid'] != null)
                      Text('Paid ${formatMoney(s['paid'] as num)} of ${formatMoney(s['amount'] as num)}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: (s['paid'] as num) >= (s['amount'] as num) ? AppTheme.primaryDark : AppTheme.warningOrange)),
                  ],
                ),
              ),
              if (s['status'] == 'cancelled')
                const StatusChip('Cancelled', bg: AppTheme.errorLight, fg: AppTheme.errorRed, fontSize: 10)
              else if (_can['memberships'] == true)
                IconButton(
                  tooltip: 'Cancel this plan',
                  icon: const Icon(Icons.more_horiz, color: AppTheme.textSubtle),
                  onPressed: () => _cancelMembership(s),
                ),
            ],
          ),
        ),
      if ((m['payments'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 8),
        _section('PAYMENTS'),
        for (final p in m['payments'] as List) PaymentTile(p: p, canVerify: _can['verify_payment'] == true, base: widget.ctx.base, onChanged: _load),
      ],
      const SizedBox(height: 8),
      _section('RECENT VISITS'),
      if ((m['visits'] as List).isEmpty) gymEmpty('No visits yet.'),
      for (final v in m['visits'] as List)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const Icon(Icons.login, size: 14, color: AppTheme.primaryDark),
              const SizedBox(width: 6),
              Text(formatServerDateTime(v['in'] as String), style: const TextStyle(fontSize: 12)),
              const Spacer(),
              Text(v['out'] == null ? 'inside' : 'out ${formatServerDateTime(v['out'] as String).split(', ').last}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            ],
          ),
        ),
    ];
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppTheme.textSubtle)),
      );

  Future<void> _assignPlan() async {
    final m = _m!;
    final plans = ((await gymGet(context, '${widget.ctx.base}/plans?branch_id=${m['branch_id']}'))?['plans'] as List? ?? [])
        .where((p) => p['status'] == 'active')
        .toList();
    if (!mounted) return;
    if (plans.isEmpty) return gymToast(context, 'Add a plan for this branch first (Plans)');
    String plan = plans.first['id'];
    DateTime? start; // null = server decides (today, or after the current plan)
    bool pay = widget.ctx.can('payments.record');
    final amount = TextEditingController(text: '${plans.first['price']}');
    final ref = TextEditingController();
    String method = 'cash';
    final ok = await showGymSheet<bool>(context, disposeAfter: [amount, ref], title: 'Assign / renew plan', builder: (sc) => StatefulBuilder(builder: (sc, set) { //Modified By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes. Old: no disposeAfter
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DocDropdown<String>(
                label: 'Plan',
                value: plan,
                items: [for (final p in plans) (p['id'] as String, '${p['name']} • ${p['duration_months']} mo • ${formatMoney(p['price'] as num)}')],
                onChanged: (v) => set(() {
                  plan = v ?? plan;
                  amount.text = '${plans.firstWhere((p) => p['id'] == plan)['price']}';
                }),
              ),
              PickBox(
                label: 'Starts on',
                value: start == null ? 'Automatic (today, or the day after the current plan ends)' : niceDate(isoDate(start!)),
                icon: Icons.event,
                onTap: () async {
                  final d = await pickDate(sc, start ?? DateTime.now(), first: DateTime.now().subtract(const Duration(days: 60)));
                  if (d != null) set(() => start = d);
                },
              ),
              if (widget.ctx.can('payments.record')) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pay,
                  activeThumbColor: AppTheme.primary,
                  onChanged: (v) => set(() => pay = v),
                  title: const Text('Payment received now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                if (pay) ..._paymentFields(amount, method, (x) => set(() => method = x), ref),
              ],
              PillButton(
                label: 'Save Plan',
                variant: PillVariant.accent,
                onPressed: () async {
                  final a = double.tryParse(amount.text.trim());
                  if (pay && (a == null || a <= 0)) return gymToast(sc, 'Enter the amount received');
                  final r = await gymSend(sc, 'POST', '$_path/memberships', {
                    'plan_id': plan,
                    if (start != null) 'start_date': isoDate(start!),
                    if (pay) 'payment': {'amount': a, 'method': method, if (ref.text.trim().isNotEmpty) 'reference_last_digits': ref.text.trim()},
                  });
                  if (r != null && sc.mounted) {
                    gymToast(sc, 'Plan set: ${niceDate(r['start_date'])} – ${niceDate(r['expiry_date'])}');
                    Navigator.pop(sc, true);
                  }
                },
              ),
            ],
          );
        }));
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: amount.dispose();
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: ref.dispose();
    if (ok == true) _load();
  }

  Future<void> _recordPayment() async {
    final ships = (_m!['memberships'] as List).where((s) => s['status'] == 'active').toList();
    String? ms = ships.isNotEmpty ? ships.first['id'] : null;
    final amount = TextEditingController();
    final ref = TextEditingController();
    String method = 'cash';
    DateTime paidOn = DateTime.now();
    final ok = await showGymSheet<bool>(context, disposeAfter: [amount, ref], title: 'Record payment', builder: (sc) => StatefulBuilder(builder: (sc, set) { //Modified By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes. Old: no disposeAfter
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DocDropdown<String?>(
                label: 'For plan',
                value: ms,
                items: [for (final s in ships) (s['id'] as String, '${s['plan_name']} (${niceDate(s['start_date'])})'), (null, 'Other / not linked')],
                onChanged: (v) => set(() => ms = v),
              ),
              ..._paymentFields(amount, method, (x) => set(() => method = x), ref),
              PickBox(
                label: 'Paid on',
                value: niceDate(isoDate(paidOn)),
                icon: Icons.event,
                onTap: () async {
                  final d = await pickDate(sc, paidOn, last: DateTime.now());
                  if (d != null) set(() => paidOn = d);
                },
              ),
              PillButton(
                label: 'Save Payment',
                variant: PillVariant.accent,
                onPressed: () async {
                  final a = double.tryParse(amount.text.trim());
                  if (a == null || a <= 0) return gymToast(sc, 'Enter the amount');
                  final r = await gymSend(sc, 'POST', '${widget.ctx.base}/payments', {
                    'member_profile_id': widget.id,
                    'membership_id': ?ms,
                    'amount': a,
                    'method': method,
                    'paid_on': isoDate(paidOn),
                    if (ref.text.trim().isNotEmpty) 'reference_last_digits': ref.text.trim(),
                  });
                  if (r != null && sc.mounted) {
                    gymToast(sc, r['status'] == 'verified' ? 'Payment saved' : 'Saved — waiting for owner/manager to verify');
                    Navigator.pop(sc, true);
                  }
                },
              ),
            ],
          );
        }));
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: amount.dispose();
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: ref.dispose();
    if (ok == true) _load();
  }

  Future<void> _editProfile() async {
    final m = _m!;
    final p = Map<String, dynamic>.from(m['profile'] as Map);
    final batches = ((await gymGet(context, '${widget.ctx.base}/batches?branch_id=${m['branch_id']}'))?['batches'] as List? ?? [])
        .where((b) => b['status'] == 'active')
        .toList();
    if (!mounted) return;
    final emergency = TextEditingController(text: p['emergency_contact'] ?? '');
    final occupation = TextEditingController(text: p['occupation'] ?? '');
    final address = TextEditingController(text: p['address'] ?? '');
    final notes = TextEditingController(text: p['notes'] ?? '');
    String? gender = p['gender'];
    String? batch = batches.any((b) => b['id'] == p['batch_id']) ? p['batch_id'] : null;
    final ok = await showGymSheet<bool>(context, disposeAfter: [emergency, occupation, address, notes], title: 'Edit details', builder: (sc) => StatefulBuilder(builder: (sc, set) { //Modified By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes. Old: no disposeAfter
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('Gender'),
              SegmentTabs(
                options: const {'male': 'Male', 'female': 'Female', 'other': 'Other'},
                selected: gender ?? '',
                onChanged: (k) => set(() => gender = gender == k ? null : k),
              ),
              const SizedBox(height: 12),
              DocDropdown<String?>(
                label: 'Batch',
                value: batch,
                items: [(null, 'No batch'), for (final b in batches) (b['id'] as String, '${b['name']} • ${time12(b['start_time'])}')],
                onChanged: (v) => set(() => batch = v),
              ),
              DocField(label: 'Emergency contact', controller: emergency, keyboardType: TextInputType.phone),
              DocField(label: 'Occupation', controller: occupation),
              DocField(label: 'Address', controller: address),
              DocField(label: 'Notes (injuries, goals…)', controller: notes),
              PillButton(
                label: 'Save',
                variant: PillVariant.accent,
                onPressed: () async {
                  final r = await gymSend(sc, 'PUT', _path, {
                    'gender': gender,
                    'dob': p['dob'],
                    'batch_id': batch,
                    'emergency_contact': emergency.text.trim().isEmpty ? null : emergency.text.trim(),
                    'occupation': occupation.text.trim().isEmpty ? null : occupation.text.trim(),
                    'address': address.text.trim().isEmpty ? null : address.text.trim(),
                    'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
                  });
                  if (r != null && sc.mounted) Navigator.pop(sc, true);
                },
              ),
            ],
          );
        }));
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: for (final c in [emergency, occupation, address, notes]) {
      //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: c.dispose();
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: }
    if (ok == true) _load();
  }

  Future<void> _cancelMembership(dynamic s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Cancel this plan?'),
        content: Text('${s['plan_name']} (${niceDate(s['start_date'])} – ${niceDate(s['expiry_date'])}) will stop counting. Payments stay in history.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel Plan', style: TextStyle(color: AppTheme.errorRed))),
        ],
      ),
    );
    if (yes == true) _act('POST', '${widget.ctx.base}/memberships/${s['id']}/cancel', {}, 'Plan cancelled');
  }

  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Remove member?'),
        content: const Text('They lose access to your gym in the app. Their history (plans, payments, visits) is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove', style: TextStyle(color: AppTheme.errorRed))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final r = await gymSend(context, 'POST', '$_path/remove', {});
    if (r != null && mounted) Navigator.pop(context);
  }
}

// ======================= payments =======================

class PaymentTile extends StatefulWidget {
  const PaymentTile({super.key, required this.p, required this.canVerify, required this.base, required this.onChanged, this.showMember = false});
  final dynamic p;
  final bool canVerify;
  final String base;
  final VoidCallback onChanged;
  final bool showMember;
  @override
  State<PaymentTile> createState() => _PaymentTileState();
}

class _PaymentTileState extends State<PaymentTile> {
  bool _busy = false;

  Future<void> _do(String action) async {
    setState(() => _busy = true);
    final r = await gymSend(context, 'POST', '${widget.base}/payments/${widget.p['id']}/$action', {});
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final (bg, fg) = switch (p['status']) {
      'verified' => (AppTheme.successLight, AppTheme.primaryDark),
      'pending' => (const Color(0xFFFFFBEB), AppTheme.warningOrange),
      _ => (AppTheme.errorLight, AppTheme.errorRed),
    };
    final method = {'cash': '💵 Cash', 'upi': '📱 UPI', 'card': '💳 Card'}[p['method']] ?? 'Other';
    return DocCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(formatMoney(p['amount'] as num),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        decoration: p['status'] == 'cancelled' ? TextDecoration.lineThrough : null)),
              ),
              StatusChip('${p['status']}'[0].toUpperCase() + '${p['status']}'.substring(1), bg: bg, fg: fg, fontSize: 10),
            ],
          ),
          if (widget.showMember) Text(p['member'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text(
            [
              method,
              if (p['reference_last_digits'] != null) '••${p['reference_last_digits']}',
              niceDate(p['paid_on']),
              if (p['plan_name'] != null) p['plan_name'],
              if (p['recorded_by'] != null) 'by ${p['recorded_by']}',
            ].join(' • '),
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
          if (widget.canVerify && p['status'] != 'cancelled') ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (p['status'] == 'pending') ...[
                  Expanded(
                    child: PillButton(
                      label: 'Verify',
                      variant: PillVariant.accent,
                      padding: const EdgeInsets.all(9),
                      fontSize: 12,
                      loading: _busy,
                      onPressed: () => _do('verify'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: PillButton(
                    label: 'Cancel entry',
                    variant: PillVariant.secondary,
                    foreground: AppTheme.errorRed,
                    padding: const EdgeInsets.all(9),
                    fontSize: 12,
                    onPressed: _busy ? null : () => _do('cancel'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.ctx, this.branch, this.status});
  final GymCtx ctx;
  final String? branch;
  final String? status;
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  late String? _branch = widget.branch;
  late String _status = widget.status ?? '';
  List<dynamic>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final qs = {'branch_id': ?_branch, if (_status.isNotEmpty) 'status': _status};
    final d = await gymGet(context, '${widget.ctx.base}/payments?${Uri(queryParameters: qs).query}');
    if (!mounted) return;
    setState(() => _items = (d?['payments'] as List?) ?? []);
  }

  @override
  Widget build(BuildContext context) {
    final total = (_items ?? []).where((p) => p['status'] == 'verified').fold<num>(0, (a, p) => a + (p['amount'] as num));
    return GymPage(
      title: 'Payments',
      subtitle: 'Latest 200 • record new ones from a member\'s page',
      onRefresh: _load,
      children: [
        BranchChips(ctx: widget.ctx, selected: _branch, onChanged: (b) {
          setState(() => _branch = b);
          _load();
        }),
        const SizedBox(height: 10),
        SegmentTabs(
          options: const {'': 'All', 'pending': 'To verify', 'verified': 'Verified', 'cancelled': 'Cancelled'},
          selected: _status,
          onChanged: (k) {
            setState(() => _status = k);
            _load();
          },
        ),
        const SizedBox(height: 12),
        if (_items == null) gymLoading,
        if (_items != null && _items!.isNotEmpty && _status != 'pending' && _status != 'cancelled')
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Verified in this list: ${formatMoney(total)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.label)),
          ),
        if (_items != null && _items!.isEmpty) gymEmpty('No payments here.'),
        for (final p in _items ?? [])
          PaymentTile(p: p, canVerify: p['can_verify'] == true, base: widget.ctx.base, onChanged: _load, showMember: true),
      ],
    );
  }
}
