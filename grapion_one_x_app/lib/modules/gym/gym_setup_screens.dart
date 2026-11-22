// //Added By Nikhil 22Nov26 08:41 For Grapion Gym setup pages: plans, batches, staff & shifts, holidays & timings, branches & settings
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import '../../services/location_service.dart'; //Added By Nikhil 22Nov26 20:53 For gym location (owner)
import 'gym_common.dart';

String _branchFor(GymCtx ctx, String? b) => b ?? ctx.branches.first['id'] as String;

Widget _branchDropdown(GymCtx ctx, String value, ValueChanged<String> onChanged) => ctx.branches.length < 2
    ? const SizedBox.shrink()
    : DocDropdown<String>(
        label: 'Branch',
        value: value,
        items: [for (final b in ctx.branches) (b['id'] as String, b['name'] as String)],
        onChanged: (v) => v == null ? null : onChanged(v),
      );

Widget _statusSwitch(bool active, ValueChanged<bool> onChanged, String label) => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: active,
      activeThumbColor: AppTheme.primary,
      onChanged: onChanged,
      title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );

Widget _inactiveChip() => const StatusChip('Off', bg: AppTheme.chipBg, fg: AppTheme.textMuted, fontSize: 10);

// ======================= plans =======================

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, required this.ctx, this.branch});
  final GymCtx ctx;
  final String? branch;
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  late String? _branch = widget.branch;
  List<dynamic>? _plans;
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '${widget.ctx.base}/plans${_branch == null ? '' : '?branch_id=$_branch'}');
    if (!mounted) return;
    setState(() {
      _plans = (d?['plans'] as List?) ?? [];
      _canEdit = d?['can_edit'] == true;
    });
  }

  Future<void> _edit([Map<String, dynamic>? p]) async {
    String branch = p?['branch_id'] ?? _branchFor(widget.ctx, _branch);
    final name = TextEditingController(text: p?['name'] ?? '');
    final months = TextEditingController(text: '${p?['duration_months'] ?? 1}');
    final price = TextEditingController(text: p == null ? '' : '${p['price']}');
    final desc = TextEditingController(text: p?['description'] ?? '');
    bool active = (p?['status'] ?? 'active') == 'active';
    final ok = await showGymSheet<bool>(context, disposeAfter: [name, months, price, desc], title: p == null ? 'New Plan' : 'Edit Plan', builder: (sc) => StatefulBuilder(builder: (sc, set) { //Modified By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes. Old: no disposeAfter
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p == null) _branchDropdown(widget.ctx, branch, (v) => set(() => branch = v)),
              DocField(label: 'Plan name', controller: name, hint: 'e.g. Monthly, Quarterly, Couple Yearly'),
              Row(
                children: [
                  Expanded(
                    child: DocField(
                      label: 'Duration (months)',
                      controller: months,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DocField(
                      label: 'Price (₹)',
                      controller: price,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                    ),
                  ),
                ],
              ),
              DocField(label: 'Description (optional)', controller: desc, hint: 'What is included'),
              if (p != null) _statusSwitch(active, (v) => set(() => active = v), 'Plan is on sale'),
              if (p != null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Members who already bought this plan keep their old price and dates.',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ),
              PillButton(
                label: 'Save Plan',
                variant: PillVariant.accent,
                onPressed: () async {
                  final body = {
                    'branch_id': branch,
                    'name': name.text.trim(),
                    'duration_months': int.tryParse(months.text) ?? 0,
                    'price': int.tryParse(price.text) ?? -1,
                    'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
                    'status': active ? 'active' : 'inactive',
                  };
                  final r = p == null
                      ? await gymSend(sc, 'POST', '${widget.ctx.base}/plans', body)
                      : await gymSend(sc, 'PUT', '${widget.ctx.base}/plans/${p['id']}', body);
                  if (r != null && sc.mounted) Navigator.pop(sc, true);
                },
              ),
            ],
          );
        }));
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: for (final c in [name, months, price, desc]) {
      //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: c.dispose();
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: }
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return GymPage(
      title: 'Plans',
      subtitle: 'Each branch sets its own plans & prices',
      onRefresh: _load,
      fab: _canEdit ? gymFab('New Plan', () => _edit()) : null,
      children: [
        BranchChips(ctx: widget.ctx, selected: _branch, onChanged: (b) {
          setState(() => _branch = b);
          _load();
        }),
        const SizedBox(height: 12),
        if (_plans == null) gymLoading,
        if (_plans != null && _plans!.isEmpty) gymEmpty(_canEdit ? 'No plans yet. Tap "New Plan".' : 'No plans yet.'),
        for (final p in _plans ?? [])
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            onTap: _canEdit ? () => _edit(Map<String, dynamic>.from(p)) : null,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      Text(
                        [
                          '${p['duration_months']} month${p['duration_months'] == 1 ? '' : 's'}',
                          if (_branch == null && widget.ctx.branches.length > 1) widget.ctx.branchName(p['branch_id']),
                          if (p['description'] != null) p['description'],
                        ].join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                if (p['status'] != 'active') ...[_inactiveChip(), const SizedBox(width: 8)],
                Text(formatMoney(p['price'] as num), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.primaryDark)),
              ],
            ),
          ),
      ],
    );
  }
}

// ======================= batches (members) & shifts (staff) — same editor =======================

Future<bool?> _slotEditor(
  BuildContext context, {
  required GymCtx ctx,
  required String kind, // 'batch' | 'shift'
  required String defaultBranch,
  Map<String, dynamic>? existing,
  List<dynamic> trainers = const [],
}) async {
  String branch = existing?['branch_id'] ?? defaultBranch;
  final name = TextEditingController(text: existing?['name'] ?? '');
  final cap = TextEditingController(text: existing?['capacity'] == null ? '' : '${existing!['capacity']}');
  TimeOfDay start = parseHhmm(existing?['start_time'], const TimeOfDay(hour: 6, minute: 0));
  TimeOfDay end = parseHhmm(existing?['end_time'], const TimeOfDay(hour: 7, minute: 0));
  Set<int> days = ((existing?['weekdays'] as List?) ?? [1, 2, 3, 4, 5, 6]).cast<int>().toSet();
  String? trainer = existing?['trainer_member_id'];
  bool active = (existing?['status'] ?? 'active') == 'active';
  final label = kind == 'batch' ? 'Batch' : 'Shift';
  final ok = await showGymSheet<bool>(context, disposeAfter: [name, cap], title: existing == null ? 'New $label' : 'Edit $label', builder: (sc) => StatefulBuilder(builder: (sc, set) { //Modified By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes. Old: no disposeAfter
        final branchTrainers = trainers.where((t) => t['branch_id'] == branch && t['status'] == 'active').toList();
        if (trainer != null && !branchTrainers.any((t) => t['member_id'] == trainer)) trainer = null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (existing == null) _branchDropdown(ctx, branch, (v) => set(() => branch = v)),
            DocField(label: '$label name', controller: name, hint: kind == 'batch' ? 'e.g. Morning Batch, Ladies Batch' : 'e.g. Morning, Evening'),
            Row(
              children: [
                Expanded(
                  child: PickBox(
                    label: 'Starts',
                    value: time12(hhmm(start)),
                    icon: Icons.schedule,
                    onTap: () async {
                      final t = await pickTime(sc, start);
                      if (t != null) set(() => start = t);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PickBox(
                    label: 'Ends',
                    value: time12(hhmm(end)),
                    icon: Icons.schedule,
                    onTap: () async {
                      final t = await pickTime(sc, end);
                      if (t != null) set(() => end = t);
                    },
                  ),
                ),
              ],
            ),
            const FieldLabel('Days'),
            WeekdayPicker(value: days, onChanged: (v) => set(() => days = v)),
            const SizedBox(height: 12),
            if (kind == 'batch') ...[
              DocDropdown<String?>(
                label: 'Trainer (optional)',
                value: trainer,
                items: [(null, 'No trainer'), for (final t in branchTrainers) (t['member_id'] as String, t['name'] as String)],
                onChanged: (v) => set(() => trainer = v),
              ),
              DocField(
                label: 'Capacity (optional)',
                controller: cap,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              ),
            ],
            if (existing != null) _statusSwitch(active, (v) => set(() => active = v), '$label is active'),
            PillButton(
              label: 'Save $label',
              variant: PillVariant.accent,
              onPressed: () async {
                if (days.isEmpty) return gymToast(sc, 'Pick at least one day');
                final body = {
                  'branch_id': branch,
                  'name': name.text.trim(),
                  'start_time': hhmm(start),
                  'end_time': hhmm(end),
                  'weekdays': days.toList()..sort(),
                  'status': active ? 'active' : 'inactive',
                  if (kind == 'batch') 'trainer_member_id': trainer,
                  if (kind == 'batch') 'capacity': int.tryParse(cap.text),
                };
                final path = '${ctx.base}/${kind == 'batch' ? 'batches' : 'shifts'}';
                final r = existing == null ? await gymSend(sc, 'POST', path, body) : await gymSend(sc, 'PUT', '$path/${existing['id']}', body);
                if (r != null && sc.mounted) Navigator.pop(sc, true);
              },
            ),
          ],
        );
      }));
  //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: name.dispose();
  //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: cap.dispose();
  return ok;
}

Widget _slotTile(dynamic s, {required String extra, VoidCallback? onTap}) => DocCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: AppTheme.selectedBg, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Text(time12(s['start_time']).split(' ').first, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.primaryDark)),
                Text(time12(s['start_time']).split(' ').last, style: const TextStyle(fontSize: 9, color: AppTheme.primaryDark)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s['name'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                Text('${time12(s['start_time'])} – ${time12(s['end_time'])} • ${weekdaysLabel(s['weekdays'] as List)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                Text(extra, style: const TextStyle(fontSize: 11, color: AppTheme.label, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (s['status'] != 'active') _inactiveChip(),
        ],
      ),
    );

class BatchesScreen extends StatefulWidget {
  const BatchesScreen({super.key, required this.ctx, this.branch});
  final GymCtx ctx;
  final String? branch;
  @override
  State<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends State<BatchesScreen> {
  late String? _branch = widget.branch;
  List<dynamic>? _items;
  List<dynamic> _trainers = const [];
  bool _canEdit = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '${widget.ctx.base}/batches${_branch == null ? '' : '?branch_id=$_branch'}');
    if (!mounted) return;
    setState(() {
      _items = (d?['batches'] as List?) ?? [];
      _canEdit = d?['can_edit'] == true;
    });
    if (_canEdit && widget.ctx.can('staff.manage')) {
      final s = await gymGet(context, '${widget.ctx.base}/staff');
      if (!mounted) return;
      setState(() => _trainers = ((s?['staff'] as List?) ?? []).where((x) => x['role_code'] == 'trainer').toList());
    }
  }

  Future<void> _edit([Map<String, dynamic>? b]) async {
    final ok = await _slotEditor(context, ctx: widget.ctx, kind: 'batch', defaultBranch: _branchFor(widget.ctx, _branch), existing: b, trainers: _trainers);
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return GymPage(
      title: 'Batches',
      subtitle: 'Member time slots',
      onRefresh: _load,
      fab: _canEdit ? gymFab('New Batch', () => _edit()) : null,
      children: [
        BranchChips(ctx: widget.ctx, selected: _branch, onChanged: (b) {
          setState(() => _branch = b);
          _load();
        }),
        const SizedBox(height: 12),
        if (_items == null) gymLoading,
        if (_items != null && _items!.isEmpty) gymEmpty('No batches yet.'),
        for (final b in _items ?? [])
          _slotTile(
            b,
            extra: [
              b['trainer_name'] != null ? '🧑‍🏫 ${b['trainer_name']}' : 'No trainer',
              '${b['members']}${b['capacity'] != null ? '/${b['capacity']}' : ''} members',
            ].join(' • '),
            onTap: _canEdit ? () => _edit(Map<String, dynamic>.from(b)) : null,
          ),
      ],
    );
  }
}

// ======================= staff & shifts =======================

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.ctx, this.branch, this.view = 'staff'}); //Modified By Nikhil 22Nov26 10:47 For separate Staff and Shifts pages. Old: const StaffScreen({super.key, required this.ctx, this.branch});
  final GymCtx ctx;
  final String? branch;
  final String view; //Added By Nikhil 22Nov26 10:47 For 'staff' | 'shifts' (two menu options)
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  late String? _branch = widget.branch;
  late final String _tab = widget.view; //Modified By Nikhil 22Nov26 10:47 For separate pages. Old: String _tab = 'staff';
  List<dynamic>? _staff;
  List<dynamic> _shifts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = _branch == null ? '' : '?branch_id=$_branch';
    final s = await gymGet(context, '${widget.ctx.base}/staff$q');
    if (!mounted) return;
    final sh = await gymGet(context, '${widget.ctx.base}/shifts$q');
    if (!mounted) return;
    setState(() {
      _staff = (s?['staff'] as List?) ?? [];
      _shifts = (sh?['shifts'] as List?) ?? [];
    });
  }

  static const _roles = {'manager': 'Manager', 'receptionist': 'Receptionist', 'trainer': 'Trainer'};

  Map<String, String> get _allowedRoles => widget.ctx.isOwner ? _roles : {'receptionist': 'Receptionist', 'trainer': 'Trainer'};

  Future<void> _addStaff() async {
    final ok = await Navigator.of(context).push<bool>(docRoute(_AddStaffScreen(ctx: widget.ctx, branch: _branchFor(widget.ctx, _branch), roles: _allowedRoles)));
    if (ok == true) _load();
  }

  Future<void> _editStaff(Map<String, dynamic> s) async {
    final spec = TextEditingController(text: s['specialization'] ?? '');
    final pay = TextEditingController(text: s['pay'] == null ? '' : '${s['pay']}');
    String payPeriod = s['pay_period'] ?? 'monthly';
    DateTime? joined = s['joining_date'] == null ? null : DateTime.tryParse(s['joining_date']);
    final picked = ((s['shift_ids'] as List?) ?? []).cast<String>().toSet();
    final shifts = _shifts.where((x) => x['branch_id'] == s['branch_id'] && x['status'] == 'active').toList();
    final ok = await showGymSheet<bool>(context, disposeAfter: [spec, pay], title: s['name'] ?? 'Staff', builder: (sc) => StatefulBuilder(builder: (sc, set) { //Modified By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes. Old: no disposeAfter
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s['role_name']} • ${s['branch_name']} • @${s['username']}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 12),
              DocField(label: 'Specialization (optional)', controller: spec, hint: 'e.g. Strength, Yoga, Zumba'),
              PickBox(
                label: 'Joining date',
                value: joined == null ? 'Not set' : niceDate(isoDate(joined!)),
                icon: Icons.event,
                onTap: () async {
                  final d = await pickDate(sc, joined ?? DateTime.now(), last: DateTime.now().add(const Duration(days: 60)));
                  if (d != null) set(() => joined = d);
                },
              ),
              if (s['pay_visible'] == true) ...[
                DocField(
                  label: 'Pay (₹) — only owner${widget.ctx.isOwner ? '' : ' & you'} can see this',
                  controller: pay,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                ),
                SegmentTabs(
                  options: const {'monthly': 'Per month', 'per_shift': 'Per shift', 'hourly': 'Per hour'},
                  selected: payPeriod,
                  onChanged: (k) => set(() => payPeriod = k),
                ),
                const SizedBox(height: 12),
              ],
              const FieldLabel('Shifts (attendance is checked against these)'),
              if (shifts.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('No shifts in this branch yet — add them from Shifts on the home page.', //Modified By Nikhil 22Nov26 10:47 For Shifts is its own page. Old: '... add them in the Shifts tab.'
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ),
              for (final sh in shifts)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: picked.contains(sh['id']),
                  activeColor: AppTheme.primary,
                  onChanged: (v) => set(() => v == true ? picked.add(sh['id']) : picked.remove(sh['id'])),
                  title: Text(sh['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: Text('${time12(sh['start_time'])} – ${time12(sh['end_time'])} • ${weekdaysLabel(sh['weekdays'] as List)}',
                      style: const TextStyle(fontSize: 11)),
                ),
              PillButton(
                label: 'Save',
                variant: PillVariant.accent,
                onPressed: () async {
                  if (picked.isEmpty && ((s['shift_ids'] as List?) ?? []).isNotEmpty) return gymToast(sc, 'Staff must have at least one shift'); //Added By Nikhil 22Nov26 10:47 For staff must keep a shift
                  final r = await gymSend(sc, 'PUT', '${widget.ctx.base}/staff/${s['member_id']}', {
                    'specialization': spec.text.trim().isEmpty ? null : spec.text.trim(),
                    'joining_date': joined == null ? null : isoDate(joined!),
                    if (s['pay_visible'] == true && pay.text.trim().isNotEmpty) ...{'pay': int.tryParse(pay.text.trim()), 'pay_period': payPeriod},
                    'shift_ids': picked.toList(),
                  });
                  if (r != null && sc.mounted) Navigator.pop(sc, true);
                },
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () async {
                    final r = await gymSend(sc, 'POST', '${widget.ctx.base}/staff/${s['member_id']}/remove', {});
                    if (r != null && sc.mounted) Navigator.pop(sc, true);
                  },
                  child: const Text('Remove from staff', style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          );
        }));
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: spec.dispose();
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: pay.dispose();
    if (ok == true) _load();
  }

  Future<void> _editShift([Map<String, dynamic>? s]) async {
    final ok = await _slotEditor(context, ctx: widget.ctx, kind: 'shift', defaultBranch: _branchFor(widget.ctx, _branch), existing: s);
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return GymPage(
      title: _tab == 'staff' ? 'Staff' : 'Shifts', //Modified By Nikhil 22Nov26 10:47 For separate pages. Old: title: 'Staff & Shifts',
      subtitle: _tab == 'staff' ? widget.ctx.name : 'Working hours for staff attendance', //Modified By Nikhil 22Nov26 10:47 For separate pages. Old: subtitle: widget.ctx.name,
      onRefresh: _load,
      fab: _tab == 'staff' ? gymFab('Add Staff', _addStaff) : gymFab('New Shift', () => _editShift()),
      children: [
        BranchChips(ctx: widget.ctx, selected: _branch, onChanged: (b) {
          setState(() => _branch = b);
          _load();
        }),
        //Removed By Nikhil 22Nov26 10:47 For separate pages: SegmentTabs(options: const {'staff': '🧑‍🤝‍🧑 Staff', 'shifts': '🕘 Shifts'}, selected: _tab, ...)
        const SizedBox(height: 12),
        if (_staff == null) gymLoading
        else if (_tab == 'staff') ...[
          if (_staff!.isEmpty) gymEmptyAction('No staff yet. Add a manager, receptionist or trainer.', emoji: '🧑‍🤝‍🧑', actionLabel: '+ Add Staff', onAction: _addStaff), //Modified By Nikhil 22Nov26 10:47 For empty state with action. Old: gymEmpty('No staff yet. Add a manager, receptionist or trainer.')
          for (final s in _staff!)
            DocCard(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 10),
              onTap: s['can_edit'] == true && s['status'] == 'active' ? () => _editStaff(Map<String, dynamic>.from(s)) : null,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NameWithChip(
                          name: s['name'] ?? '',
                          nameStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          chipText: s['role_name'] ?? '',
                          chipBg: AppTheme.selectedBg,
                          chipFg: AppTheme.primaryDark,
                          compactChipText: switch (s['role_code']) { 'manager' => '🧑‍💼', 'trainer' => '🧑‍🏫', _ => '🛎️' },
                        ),
                        Text(
                          [
                            if (_branch == null && widget.ctx.branches.length > 1) s['branch_name'],
                            '${(s['shift_ids'] as List).length} shift${(s['shift_ids'] as List).length == 1 ? '' : 's'}',
                            if (s['specialization'] != null) s['specialization'],
                            if (s['pay'] != null) '${formatMoney(s['pay'] as num)} ${{'monthly': '/mo', 'per_shift': '/shift', 'hourly': '/hr'}[s['pay_period']] ?? ''}',
                          ].join(' • '),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (s['status'] == 'invited') const StatusChip('Invite sent', bg: Color(0xFFEFF6FF), fg: AppTheme.accentBlue, fontSize: 10)
                  else if ((s['shift_ids'] as List).isEmpty) const StatusChip('⚠ No shift', bg: Color(0xFFFFFBEB), fg: AppTheme.warningOrange, fontSize: 10), //Added By Nikhil 22Nov26 10:47 For staff accepted an invite but has no shift yet
                ],
              ),
            ),
        ] else ...[
          if (_shifts.isEmpty) gymEmptyAction('No shifts yet. Typical: Morning 6–12, Evening 4–10.', emoji: '🕘', actionLabel: '+ New Shift', onAction: () => _editShift()), //Modified By Nikhil 22Nov26 10:47 For empty state with action. Old: gymEmpty('No shifts yet. Typical: Morning 6–12, Evening 4–10.')
          for (final s in _shifts)
            _slotTile(s, extra: '${s['staff']} staff assigned', onTap: () => _editShift(Map<String, dynamic>.from(s))),
        ],
      ],
    );
  }
}

class _AddStaffScreen extends StatefulWidget {
  const _AddStaffScreen({required this.ctx, required this.branch, required this.roles});
  final GymCtx ctx;
  final String branch;
  final Map<String, String> roles;
  @override
  State<_AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<_AddStaffScreen> {
  late String _branch = widget.branch;
  late String _role = widget.roles.keys.contains('trainer') ? 'trainer' : widget.roles.keys.first;
  String _mode = 'search';
  String _by = 'username';
  final _search = TextEditingController();
  List<dynamic> _found = const [];
  String? _picked;
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _username = TextEditingController();
  final _mobile = TextEditingController();
  bool _busy = false;
  //Added By Nikhil 22Nov26 10:47 For staff created with a login must get a shift START
  List<dynamic>? _shifts;
  final Set<String> _pickedShifts = {};

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  Future<void> _loadShifts() async {
    final d = await gymGet(context, '${widget.ctx.base}/shifts?branch_id=$_branch');
    if (!mounted) return;
    setState(() {
      _shifts = ((d?['shifts'] as List?) ?? []).where((x) => x['status'] == 'active').toList();
      _pickedShifts.retainWhere((id) => _shifts!.any((x) => x['id'] == id));
    });
  }

  Future<void> _newShift() async {
    final ok = await _slotEditor(context, ctx: widget.ctx, kind: 'shift', defaultBranch: _branch);
    if (ok == true) _loadShifts();
  }

  List<Widget> _shiftPicker() => [
        const FieldLabel('Shifts (required)'),
        if (_shifts == null)
          gymLoading
        else if (_shifts!.isEmpty)
          gymEmptyAction('This branch has no shifts yet. Staff need a shift to be added.', emoji: '🕘', actionLabel: '+ Create a shift first', onAction: _newShift)
        else
          for (final sh in _shifts!)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _pickedShifts.contains(sh['id']),
              activeColor: AppTheme.primary,
              onChanged: (v) => setState(() => v == true ? _pickedShifts.add(sh['id'] as String) : _pickedShifts.remove(sh['id'])),
              title: Text(sh['name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text('${time12(sh['start_time'])} – ${time12(sh['end_time'])} • ${weekdaysLabel(sh['weekdays'] as List)}', style: const TextStyle(fontSize: 11)),
            ),
      ];
  //Added By Nikhil 22Nov26 10:47 For staff created with a login must get a shift END

  @override
  void dispose() {
    for (final c in [_search, _first, _last, _username, _mobile]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _find() async {
    if (_search.text.trim().length < 3) return gymToast(context, 'Type the exact value');
    final d = await gymGet(context, '/workspaces/${widget.ctx.workspaceId}/people/search?${Uri(queryParameters: {_by: _search.text.trim()}).query}');
    if (!mounted) return;
    setState(() {
      _found = (d?['results'] as List?) ?? [];
      _picked = null;
    });
    if (_found.isEmpty) gymToast(context, 'No account found — ask them to register, or create a login');
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    Map<String, dynamic>? r;
    if (_mode == 'search') {
      if (_picked == null) {
        setState(() => _busy = false);
        return gymToast(context, 'Search and pick the person first');
      }
      r = await gymSend(context, 'POST', '/workspaces/${widget.ctx.workspaceId}/invites', {'user_id': _picked, 'role_code': _role, 'branch_id': _branch});
    } else {
      if (_pickedShifts.isEmpty) { //Added By Nikhil 22Nov26 10:47 For staff must have a shift START
        setState(() => _busy = false);
        return gymToast(context, 'Pick at least one shift');
      } //Added By Nikhil 22Nov26 10:47 For staff must have a shift END
      r = await gymSend(context, 'POST', '${widget.ctx.base}/staff', {
        'branch_id': _branch,
        'role_code': _role,
        'shift_ids': _pickedShifts.toList(), //Added By Nikhil 22Nov26 10:47 For staff must have a shift
        'login': {'first_name': _first.text.trim(), 'last_name': _last.text.trim(), 'username': _username.text.trim(), 'mobile_number': _mobile.text.trim()},
      });
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (r == null) return;
    if (r['temporary_password'] != null) await showTempPassword(context, r['username'], r['temporary_password']);
    if (!mounted) return;
    gymToast(context, _mode == 'search' ? 'Invite sent — they accept on their next login' : 'Staff login created');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return GymPage(
      title: 'Add Staff',
      subtitle: 'Then set pay from the staff list', //Modified By Nikhil 22Nov26 10:47 For shift chosen here. Old: 'Then set shifts & pay from the staff list'
      onRefresh: () async {},
      children: [
        _branchDropdown(widget.ctx, _branch, (v) { //Modified By Nikhil 22Nov26 10:47 For reload shifts per branch. Old: (v) => setState(() => _branch = v)
          setState(() => _branch = v);
          _loadShifts();
        }),
        const FieldLabel('Role'),
        SegmentTabs(options: widget.roles, selected: _role, onChanged: (k) => setState(() => _role = k)),
        const SizedBox(height: 14),
        SegmentTabs(
          options: const {'search': '🔎 Has an account', 'new': '➕ Create login'},
          selected: _mode,
          onChanged: (k) => setState(() => _mode = k),
        ),
        const SizedBox(height: 14),
        if (_mode == 'search') ...[
          SegmentTabs(
            options: const {'username': 'Exact username', 'mobile': 'Exact mobile'},
            selected: _by,
            onChanged: (k) => setState(() => _by = k),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: DocField(label: _by == 'username' ? 'Username' : 'Mobile number', controller: _search, onSubmitted: (_) => _find())),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: PillButton(label: 'Find', padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), onPressed: _find, expand: false), //Modified By Nikhil 22Nov26 16:52 For white screen (full-width button in a Row). Old: no expand: false
              ),
            ],
          ),
          for (final u in _found)
            DocCard(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              borderColor: _picked == u['user_id'] ? AppTheme.primary : AppTheme.cardBorder,
              onTap: () => setState(() => _picked = u['user_id'] as String),
              child: Row(
                children: [
                  Icon(_picked == u['user_id'] ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: _picked == u['user_id'] ? AppTheme.primary : AppTheme.textSubtle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${u['name']}\n@${u['username']} • ${u['mobile']}', style: const TextStyle(fontSize: 12, height: 1.4)),
                  ),
                ],
              ),
            ),
          const Padding( //Added By Nikhil 22Nov26 10:47 For invited staff get a shift after accepting
            padding: EdgeInsets.only(bottom: 8),
            child: Text('🕘 Assign a shift after they accept the invite (Staff → tap their name).', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ),
        ] else ...[
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
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.]')), LengthLimitingTextInputFormatter(50)],
          ),
          DocField(
            label: 'Mobile (+91)',
            controller: _mobile,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(15)],
          ),
          ..._shiftPicker(), //Added By Nikhil 22Nov26 10:47 For staff must have a shift
        ],
        const SizedBox(height: 6),
        PillButton(label: _mode == 'search' ? 'Send Invite' : 'Create Login', variant: PillVariant.accent, loading: _busy, onPressed: _save),
      ],
    );
  }
}

// ======================= holidays & timings =======================

class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key, required this.ctx, this.branch});
  final GymCtx ctx;
  final String? branch;
  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  late String _branch = _branchFor(widget.ctx, widget.branch);
  String _tab = 'holidays';
  List<dynamic>? _holidays;
  List<Map<String, dynamic>> _hours = [];
  bool _canEditHours = false;

  bool get _canEdit => widget.ctx.can('holidays.edit');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await gymGet(context, '${widget.ctx.base}/holidays');
    if (!mounted) return;
    final s = await gymGet(context, '${widget.ctx.base}/branches/$_branch/setup');
    if (!mounted) return;
    setState(() {
      _holidays = (h?['holidays'] as List?) ?? [];
      _hours = ((s?['hours'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x)).toList();
      _canEditHours = s?['can_edit_hours'] == true;
    });
  }

  Future<void> _addHoliday() async {
    DateTime day = DateTime.now().add(const Duration(days: 1));
    String? branch = widget.ctx.isOwner ? null : _branch; // null = every branch (owner)
    final reason = TextEditingController();
    final ok = await showGymSheet<bool>(context, disposeAfter: [reason], title: 'Add Holiday', builder: (sc) => StatefulBuilder(builder: (sc, set) { //Modified By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes. Old: no disposeAfter
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PickBox(
                label: 'Date',
                value: niceDate(isoDate(day)),
                icon: Icons.event,
                onTap: () async {
                  final d = await pickDate(sc, day, first: DateTime.now());
                  if (d != null) set(() => day = d);
                },
              ),
              DocField(label: 'Reason', controller: reason, hint: 'e.g. Diwali, maintenance'),
              if (widget.ctx.branches.length > 1)
                DocDropdown<String?>(
                  label: 'Which branch',
                  value: branch,
                  items: [if (widget.ctx.isOwner) (null, 'All branches'), for (final b in widget.ctx.branches) (b['id'] as String, b['name'] as String)],
                  onChanged: (v) => set(() => branch = v),
                ),
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('🔔 Every member and staff of the branch gets a notification on their phone.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ),
              PillButton(
                label: 'Save & Notify',
                variant: PillVariant.accent,
                onPressed: () async {
                  final r = await gymSend(sc, 'POST', '${widget.ctx.base}/holidays', {
                    'holiday_date': isoDate(day),
                    'reason': reason.text.trim(),
                    'branch_id': ?(widget.ctx.branches.length > 1 ? branch : _branch),
                  });
                  if (r != null && sc.mounted) {
                    gymToast(sc, 'Holiday saved • ${r['notified']} people notified');
                    Navigator.pop(sc, true);
                  }
                },
              ),
            ],
          );
        }));
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: reason.dispose();
    if (ok == true) _load();
  }

  Future<void> _removeHoliday(dynamic h) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Remove holiday?'),
        content: Text('${niceDate(h['date'])} — ${h['reason']} (${h['branch_name']}). Everyone is told the gym is open.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove', style: TextStyle(color: AppTheme.errorRed))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    if (await gymSend(context, 'POST', '${widget.ctx.base}/holidays/${h['id']}/remove', {}) != null) _load();
  }

  Future<void> _saveHours() async {
    final r = await gymSend(context, 'PUT', '${widget.ctx.base}/branches/$_branch/hours', {'hours': _hours, 'notify': true});
    if (r != null && mounted) gymToast(context, 'Timings saved • members & staff notified');
  }

  @override
  Widget build(BuildContext context) {
    final today = isoDate(DateTime.now());
    return GymPage(
      title: 'Holidays & Timings',
      subtitle: widget.ctx.name,
      onRefresh: _load,
      fab: _tab == 'holidays' && _canEdit ? gymFab('Add Holiday', _addHoliday) : null,
      children: [
        SegmentTabs(options: const {'holidays': '🏖️ Holidays', 'timings': '🕘 Timings'}, selected: _tab, onChanged: (k) => setState(() => _tab = k)),
        const SizedBox(height: 12),
        if (_holidays == null) gymLoading
        else if (_tab == 'holidays') ...[
          if (_holidays!.isEmpty) gymEmpty('No upcoming holidays.'),
          for (final h in _holidays!)
            DocCard(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Text((h['date'] as String).compareTo(today) < 0 ? '🗓' : '🏖️', style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(niceDate(h['date']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                        Text('${h['reason']}${widget.ctx.branches.length > 1 ? ' • ${h['branch_name']}' : ''}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  if (h['can_remove'] == true && (h['date'] as String).compareTo(today) >= 0)
                    IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.errorRed), tooltip: 'Remove', onPressed: () => _removeHoliday(h)),
                ],
              ),
            ),
        ] else ...[
          if (widget.ctx.branches.length > 1)
            _branchDropdown(widget.ctx, _branch, (v) {
              setState(() => _branch = v);
              _load();
            }),
          for (final h in _hours) _hourRow(h),
          if (_canEditHours) ...[
            const SizedBox(height: 8),
            PillButton(label: 'Save Timings & Notify', variant: PillVariant.accent, onPressed: _saveHours),
          ],
        ],
      ],
    );
  }

  Widget _hourRow(Map<String, dynamic> h) {
    final closed = h['is_closed'] == true;
    Future<void> pick(String key) async {
      final t = await pickTime(context, parseHhmm(h[key], const TimeOfDay(hour: 6, minute: 0)));
      if (t != null) setState(() => h[key] = hhmm(t));
    }

    return DocCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 44, child: Text(weekdayShort[(h['weekday'] as int) - 1], style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(
            child: closed
                ? const Text('Closed (weekly off)', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      TextButton(onPressed: _canEditHours ? () => pick('open') : null, child: Text(time12(h['open']))),
                      const Text('–'),
                      TextButton(onPressed: _canEditHours ? () => pick('close') : null, child: Text(time12(h['close']))),
                    ],
                  ),
          ),
          if (_canEditHours)
            Switch(
              value: !closed,
              activeThumbColor: AppTheme.primary,
              onChanged: (open) => setState(() {
                h['is_closed'] = !open;
                if (open) {
                  h['open'] ??= '06:00';
                  h['close'] ??= '22:00';
                } else {
                  h['open'] = null;
                  h['close'] = null;
                }
              }),
            ),
        ],
      ),
    );
  }
}

// ======================= branches & settings =======================

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key, required this.ctx});
  final GymCtx ctx;
  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  List<dynamic>? _branches;
  bool _canAdd = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '${widget.ctx.base}/branches');
    if (!mounted) return;
    setState(() {
      _branches = (d?['branches'] as List?) ?? [];
      _canAdd = d?['can_add'] == true;
    });
  }

  Future<void> _edit([Map<String, dynamic>? b]) async {
    final name = TextEditingController(text: b?['name'] ?? '');
    final address = TextEditingController(text: b?['address'] ?? '');
    final phone = TextEditingController(text: b?['phone'] ?? '');
    final ok = await showGymSheet<bool>(context, disposeAfter: [name, address, phone], title: b == null ? 'New Branch' : 'Edit Branch', builder: (sc) => Column( //Modified By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes. Old: no disposeAfter
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DocField(label: 'Branch name', controller: name, hint: 'e.g. Andheri West'),
            DocField(label: 'Address (optional)', controller: address),
            DocField(label: 'Phone (optional)', controller: phone, keyboardType: TextInputType.phone),
            if (b == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('New branches start with Mon–Sat 6 AM – 10 PM, Sunday closed, and the standard attendance rules. Add plans for it next.',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              ),
            PillButton(
              label: 'Save Branch',
              variant: PillVariant.accent,
              onPressed: () async {
                final body = {
                  'name': name.text.trim(),
                  'address': address.text.trim().isEmpty ? null : address.text.trim(),
                  'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
                };
                final r = b == null
                    ? await gymSend(sc, 'POST', '${widget.ctx.base}/branches', body)
                    : await gymSend(sc, 'PUT', '${widget.ctx.base}/branches/${b['id']}', body);
                if (r != null && sc.mounted) Navigator.pop(sc, true);
              },
            ),
          ],
        ));
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: for (final c in [name, address, phone]) {
      //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: c.dispose();
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: }
    if (ok == true) {
      _load();
      if (b == null && mounted) gymToast(context, 'Branch added — go back to Home and pull down to see it');
    }
  }

  Future<void> _settings(Map<String, dynamic> b) async {
    final d = await gymGet(context, '${widget.ctx.base}/branches/${b['id']}/setup');
    if (!mounted || d == null) return;
    final s = Map<String, dynamic>.from((d['settings'] as Map?) ?? {});
    if (s.isEmpty) return gymToast(context, 'You cannot change settings for this branch');
    final c = {
      for (final k in ['late_grace_minutes', 'half_day_after_minutes', 'early_out_grace_minutes', 'reminder_lead_days'])
        k: TextEditingController(text: '${s[k]}'),
    };
    final upi = TextEditingController(text: s['upi_id'] ?? '');
    final payee = TextEditingController(text: s['upi_payee_name'] ?? '');
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)];
    final ok = await showGymSheet<bool>(context, disposeAfter: [...c.values, upi, payee], title: '${b['name']} • Settings', builder: (sc) => Column( //Modified By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes. Old: no disposeAfter
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FieldLabel('STAFF ATTENDANCE RULES (minutes after shift start)'),
            Row(
              children: [
                Expanded(child: DocField(label: 'Late after', controller: c['late_grace_minutes']!, keyboardType: TextInputType.number, inputFormatters: digits)),
                const SizedBox(width: 8),
                Expanded(child: DocField(label: 'Half day after', controller: c['half_day_after_minutes']!, keyboardType: TextInputType.number, inputFormatters: digits)),
              ],
            ),
            DocField(label: 'Early check-out allowed (minutes)', controller: c['early_out_grace_minutes']!, keyboardType: TextInputType.number, inputFormatters: digits),
            const Text('Present ≤ late · Late up to half-day · Half day after that or early check-out · Absent: no check-in or under 50% of the shift.',
                style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
            const SizedBox(height: 14),
            DocField(label: 'Remind members before expiry (days)', controller: c['reminder_lead_days']!, keyboardType: TextInputType.number, inputFormatters: digits),
            const FieldLabel('UPI FOR MEMBER PAYMENTS (optional)'),
            DocField(label: 'UPI ID', controller: upi, hint: 'yourgym@okbank'),
            DocField(label: 'Payee name', controller: payee),
            PillButton(
              label: 'Save Settings',
              variant: PillVariant.accent,
              onPressed: () async {
                final r = await gymSend(sc, 'PUT', '${widget.ctx.base}/branches/${b['id']}/settings', {
                  for (final e in c.entries) e.key: int.tryParse(e.value.text) ?? -1,
                  'upi_id': upi.text.trim(),
                  'upi_payee_name': payee.text.trim(),
                });
                if (r != null && sc.mounted) Navigator.pop(sc, true);
              },
            ),
          ],
        ));
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: for (final x in [...c.values, upi, payee]) {
      //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: x.dispose();
    //Removed By Nikhil 22Nov26 10:47 For sheet controllers disposed by the sheet after it closes: }
    if (ok == true && mounted) gymToast(context, 'Settings saved');
  }

  //Added By Nikhil 22Nov26 20:53 For location check-in: owner saves where the gym is + allowed distance START
  Future<void> _location(Map<String, dynamic> b) async {
    final d = await gymGet(context, '${widget.ctx.base}/branches/${b['id']}/setup');
    if (!mounted || d == null) return;
    final loc = d['location'] as Map<String, dynamic>?;
    if (loc == null) return gymToast(context, 'Only the owner can set the check-in location');
    double? lat = (loc['latitude'] as num?)?.toDouble();
    double? lng = (loc['longitude'] as num?)?.toDouble();
    final radius = TextEditingController(text: '${loc['radius_m'] ?? 50}');
    String? note;
    bool busy = false;
    await showGymSheet<void>(
      context,
      title: 'Check-in location • ${b['name']}',
      disposeAfter: [radius],
      builder: (sc) => StatefulBuilder(
        builder: (sc, setS) {
          Future<void> save({bool off = false}) async {
            final r = int.tryParse(radius.text.trim());
            if (r == null || r < 20 || r > 1000) return setS(() => note = 'Distance must be 20 to 1000 metres');
            setS(() => busy = true);
            final ok = await gymSend(sc, 'PUT', '${widget.ctx.base}/branches/${b['id']}/location',
                {'latitude': off ? null : lat, 'longitude': off ? null : lng, 'radius_m': r});
            setS(() => busy = false);
            if (ok != null && sc.mounted) {
              Navigator.pop(sc);
              if (mounted) gymToast(context, off ? 'Location check switched off' : 'Check-in location saved');
            }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lat == null
                    ? 'Not set: members and staff can check in from anywhere.'
                    : 'Set ✓ Members and staff must be within the distance below to check in.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: lat == null ? AppTheme.warningOrange : AppTheme.primaryDark),
              ),
              if (lat != null)
                Text('${lat!.toStringAsFixed(5)}, ${lng!.toStringAsFixed(5)}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(height: 12),
              PillButton(
                label: '📍 Use my current location',
                variant: PillVariant.secondary,
                loading: busy,
                onPressed: () async {
                  setS(() => busy = true);
                  final fix = await LocationService.current();
                  setS(() {
                    busy = false;
                    if (fix.error != null) {
                      note = fix.error;
                    } else {
                      lat = fix.lat;
                      lng = fix.lng;
                      note = (fix.accuracy ?? 0) > 50
                          ? 'GPS accuracy is about ${fix.accuracy!.round()} m. For a better fix, stand near the entrance or a window and try again.'
                          : 'Got it (accuracy about ${fix.accuracy?.round()} m). Tap Save.';
                    }
                  });
                },
              ),
              const SizedBox(height: 6),
              const Text('Stand inside the gym (near the entrance) when you tap this.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              const SizedBox(height: 12),
              DocField(label: 'Allowed distance (metres)', controller: radius, keyboardType: TextInputType.number, hint: '50'),
              const Text('50 m is recommended: phone GPS indoors is often 10–50 m off.', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
              if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              const SizedBox(height: 14),
              PillButton(label: 'Save', variant: PillVariant.accent, loading: busy, onPressed: lat == null ? null : () => save()),
              if ((loc['latitude']) != null) ...[
                const SizedBox(height: 8),
                PillButton(label: 'Switch location check off', variant: PillVariant.secondary, foreground: AppTheme.errorRed, onPressed: () => save(off: true)),
              ],
            ],
          );
        },
      ),
    );
  }
  //Added By Nikhil 22Nov26 20:53 For location check-in: owner saves where the gym is + allowed distance END

  @override
  Widget build(BuildContext context) {
    return GymPage(
      title: 'Branches & Settings',
      subtitle: widget.ctx.name,
      onRefresh: _load,
      fab: _canAdd ? gymFab('New Branch', () => _edit()) : null,
      children: [
        if (_branches == null) gymLoading,
        for (final b in _branches ?? [])
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📍 ${b['name']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                if (b['address'] != null || b['phone'] != null)
                  Text([b['address'], b['phone']].whereType<String>().join(' • '), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(height: 10),
                Wrap( //Modified By Nikhil 22Nov26 20:53 For a third option that still fits on a phone. Old: Row(children: [Edit, SizedBox, Rules])
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SmallPill(label: '✏️ Edit', onTap: () => _edit(Map<String, dynamic>.from(b))),
                    SmallPill(label: '⚙️ Rules, reminders & UPI', onTap: () => _settings(Map<String, dynamic>.from(b))),
                    SmallPill(label: '📌 Check-in location', onTap: () => _location(Map<String, dynamic>.from(b))), //Added By Nikhil 22Nov26 20:53 For location check-in
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
