// //Added By Nikhil 22Nov26 14:41 For staff self check-in + shift attendance (my shift card, my attendance, staff register, month summary, corrections)
import 'package:flutter/material.dart';

import '../../services/location_service.dart'; //Added By Nikhil 22Nov26 20:53 For location check-in
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import 'gym_common.dart';

/// Status → (label, background, foreground). Labels come from the server; colours live here.
(Color, Color) attendanceColors(String? status) => switch (status) {
      'present' => (AppTheme.successLight, AppTheme.primaryDark),
      'late' => (AppTheme.warningLight, AppTheme.warningOrange),
      'half_day' => (const Color(0xFFFFEDD5), const Color(0xFFC2410C)),
      'absent' || 'missed_checkout' => (AppTheme.errorLight, AppTheme.errorRed),
      'holiday' || 'week_off' => (const Color(0xFFEFF6FF), AppTheme.accentBlue),
      _ => (AppTheme.chipBg, AppTheme.textMuted),
    };

Widget attendanceChip(Map<String, dynamic> i) {
  final (bg, fg) = attendanceColors(i['status'] as String?);
  return StatusChip('${i['status_label'] ?? i['status']}${i['corrected'] == true ? ' ✎' : ''}', bg: bg, fg: fg, fontSize: 10);
}

/// "06:10" from an ISO timestamp the server sent in IST (never the phone clock).
String _clock(String? iso) => iso == null || iso.length < 16 ? '' : time12(iso.substring(11, 16));

String _inOut(Map<String, dynamic> i) {
  final a = _clock(i['check_in_at'] as String?), b = _clock(i['check_out_at'] as String?);
  if (a.isEmpty) return '';
  return b.isEmpty ? 'In $a' : 'In $a • Out $b';
}

String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
String _monthLabel(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';

/// Counts row: Present 3 • Late 1 • …  (only the non-zero ones).
Widget attendanceCounts(Map<String, dynamic>? c) {
  if (c == null) return const SizedBox.shrink();
  const keys = [('present', 'Present'), ('late', 'Late'), ('half_day', 'Half day'), ('absent', 'Absent'),
    ('missed_checkout', 'Missed check-out'), ('holiday', 'Holiday'), ('week_off', 'Week off'), ('pending', 'Not in yet')];
  final chips = [
    for (final (k, l) in keys)
      if (((c[k] as num?) ?? 0) > 0)
        () {
          final (bg, fg) = attendanceColors(k);
          return StatusChip('$l ${c[k]}', bg: bg, fg: fg, fontSize: 11);
        }(),
  ];
  if (chips.isEmpty) return const SizedBox.shrink();
  return Padding(padding: const EdgeInsets.only(bottom: 12), child: Wrap(spacing: 6, runSpacing: 6, children: chips));
}

/// Month header with ‹ › (never past the current month).
class _MonthNav extends StatelessWidget {
  const _MonthNav({required this.month, required this.onChanged});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(child: Text(_monthLabel(month), textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          IconButton(
            tooltip: 'Next month',
            onPressed: isCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

// =============================== My shift today (home card) ===============================

/// Shown on the gym home for staff roles: today's shifts with Check In / Check Out.
class MyShiftCard extends StatefulWidget {
  const MyShiftCard({super.key, required this.workspaceId, this.onChanged});
  final String workspaceId;
  final VoidCallback? onChanged;

  @override
  State<MyShiftCard> createState() => _MyShiftCardState();
}

class _MyShiftCardState extends State<MyShiftCard> {
  List<Map<String, dynamic>>? _shifts;
  bool _busy = false;

  String get _base => '/gym/${widget.workspaceId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '$_base/me/today');
    if (!mounted || d == null) return;
    setState(() => _shifts = ((d['shifts'] as List?) ?? []).cast<Map<String, dynamic>>());
  }

  Future<void> _act(String what, [String? shiftId, bool needsLocation = false]) async { //Modified By Nikhil 22Nov26 20:53 For location check-in. Old: ([String? shiftId])
    setState(() => _busy = true);
    //Added By Nikhil 22Nov26 20:53 For location check-in: read GPS only when this branch has set its location START
    var geo = <String, dynamic>{};
    if (what == 'checkin' && needsLocation) {
      final fix = await LocationService.current();
      if (!mounted) return;
      if (fix.error != null) {
        setState(() => _busy = false);
        return gymToast(context, fix.error!);
      }
      geo = fix.toJson();
    }
    //Added By Nikhil 22Nov26 20:53 For location check-in END
    final r = await gymSend(context, 'POST', '$_base/me/$what', {'shift_id': ?shiftId, ...geo}, //Modified By Nikhil 22Nov26 20:53 For location body. Old: {'shift_id': ?shiftId},
        fallback: what == 'checkin' ? 'Could not check in' : 'Could not check out');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      gymToast(context, what == 'checkin' ? '✅ Checked in — ${r['status_label']}' : '👋 Checked out — ${r['status_label']}');
      await _load();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shifts = _shifts;
    if (shifts == null) return const SizedBox.shrink();
    return DocCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('🕒 My shift today', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              SmallPill(
                label: 'My attendance →',
                onTap: () => Navigator.of(context).push(docRoute(MyAttendanceScreen(workspaceId: widget.workspaceId))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (shifts.isEmpty)
            const Text('No shift today.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))
          else
            for (final s in shifts) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s['shift_name']} • ${time12(s['start_time'])} – ${time12(s['end_time'])}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(
                          [
                            if (_inOut(s).isNotEmpty) _inOut(s),
                            if (s['status'] == 'pending' && s['can_check_in'] != true) 'Check-in opens at ${time12(s['check_in_opens'])}',
                            if (s['holiday'] != null) '🏖️ ${s['holiday']}',
                          ].join(' • '),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  attendanceChip(s),
                ],
              ),
              if (s['can_check_in'] == true || s['can_check_out'] == true) ...[
                const SizedBox(height: 10),
                PillButton(
                  label: s['can_check_out'] == true ? 'Check Out' : (s['extra_day'] == true ? 'Check In (extra day)' : 'Check In'), //Modified By Nikhil 22Nov26 20:53 For week-off extra day. Old: ... : 'Check In',
                  variant: s['can_check_out'] == true ? PillVariant.secondary : PillVariant.accent,
                  padding: const EdgeInsets.all(12),
                  fontSize: 13,
                  loading: _busy,
                  onPressed: _busy ? null : () => _act(s['can_check_out'] == true ? 'checkout' : 'checkin', s['shift_id'] as String, s['location_required'] == true), //Modified By Nikhil 22Nov26 20:53 For location check-in. Old: (..., s['shift_id'] as String)
                ),
              ],
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

// =============================== My attendance (staff, own month) ===============================

class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '/gym/${widget.workspaceId}/me/attendance?month=${_monthKey(_month)}');
    if (mounted) setState(() => _data = d ?? const {'days': [], 'counts': null});
  }

  @override
  Widget build(BuildContext context) {
    final days = ((_data?['days'] as List?) ?? []).cast<Map<String, dynamic>>().where((d) => d['status'] != 'week_off').toList();
    return GymPage(
      title: 'My Attendance',
      subtitle: 'Your shifts, check-ins and check-outs',
      onRefresh: _load,
      children: [
        _MonthNav(month: _month, onChanged: (m) {
          setState(() {
            _month = m;
            _data = null;
          });
          _load();
        }),
        if (_data == null)
          gymLoading
        else ...[
          attendanceCounts(_data!['counts'] as Map<String, dynamic>?),
          if (days.isEmpty) gymEmpty('No shifts in ${_monthLabel(_month)}.'),
          for (final d in days) _AttendanceRow(item: d, title: niceDate(d['work_date']), sub: '${d['shift_name']} • ${time12(d['start_time'])} – ${time12(d['end_time'])}'),
        ],
      ],
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  const _AttendanceRow({required this.item, required this.title, required this.sub, this.onTap});
  final Map<String, dynamic> item;
  final String title;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final note = item['correction_note'] as String?;
    return DocCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 8),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                Text(sub, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                if (_inOut(item).isNotEmpty) Text(_inOut(item), style: const TextStyle(fontSize: 11, color: AppTheme.label)),
                if (note != null && note.isNotEmpty) Text('✎ $note', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          attendanceChip(item),
          if (onTap != null) const Icon(Icons.chevron_right, color: AppTheme.textSubtle, size: 18),
        ],
      ),
    );
  }
}

// =============================== Staff attendance (owner / manager / receptionist) ===============================

class StaffAttendanceScreen extends StatefulWidget {
  const StaffAttendanceScreen({super.key, required this.ctx, this.branch});
  final GymCtx ctx;
  final String? branch;

  @override
  State<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends State<StaffAttendanceScreen> {
  String _view = 'day';
  late String? _branch = widget.branch;
  DateTime _date = DateTime.now();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _day;
  Map<String, dynamic>? _summary;

  GymCtx get ctx => widget.ctx;
  String get _branchQ => _branch == null ? '' : '&branch_id=$_branch';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_view == 'day') {
      final d = await gymGet(context, '${ctx.base}/staff-attendance?date=${isoDate(_date)}$_branchQ');
      if (mounted) setState(() => _day = d ?? const {'items': []});
    } else {
      final d = await gymGet(context, '${ctx.base}/staff-attendance/summary?month=${_monthKey(_month)}$_branchQ');
      if (mounted) setState(() => _summary = d ?? const {'staff': []});
    }
  }

  void _reload({bool clear = true}) {
    if (clear) {
      setState(() {
        _day = null;
        _summary = null;
      });
    }
    _load();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await pickDate(context, _date, first: DateTime(now.year - 1), last: now);
    if (d == null) return;
    _date = d;
    _reload();
  }

  Future<void> _correct(Map<String, dynamic> i) async {
    final note = TextEditingController();
    var status = (['present', 'late', 'half_day', 'absent'].contains(i['status']) ? i['status'] : 'present') as String;
    String? cin = (i['check_in_at'] as String?)?.substring(11, 16);
    String? cout = (i['check_out_at'] as String?)?.substring(11, 16);
    final saved = await showGymSheet<bool>(
      context,
      title: 'Correct attendance — ${i['name']}',
      disposeAfter: [note],
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${i['shift_name']} • ${niceDate(i['work_date'])} • ${time12(i['start_time'])} – ${time12(i['end_time'])}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            DocDropdown<String>(
              label: 'Status',
              value: status,
              items: const [('present', 'Present'), ('late', 'Late'), ('half_day', 'Half day'), ('absent', 'Absent')],
              onChanged: (v) => setS(() => status = v ?? status),
            ),
            Row(
              children: [
                Expanded(
                  child: PickBox(
                    label: 'Check-in (optional)',
                    value: cin == null ? 'Not set' : time12(cin),
                    icon: Icons.login,
                    onTap: () async {
                      final t = await pickTime(sheet, parseHhmm(cin ?? i['start_time'], const TimeOfDay(hour: 9, minute: 0)));
                      if (t != null) setS(() => cin = hhmm(t));
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PickBox(
                    label: 'Check-out (optional)',
                    value: cout == null ? 'Not set' : time12(cout),
                    icon: Icons.logout,
                    onTap: () async {
                      final t = await pickTime(sheet, parseHhmm(cout ?? i['end_time'], const TimeOfDay(hour: 18, minute: 0)));
                      if (t != null) setS(() => cout = hhmm(t));
                    },
                  ),
                ),
              ],
            ),
            DocField(label: 'Reason (shown to the staff member)', controller: note, hint: 'e.g. Was at a client session outside'),
            PillButton(
              label: 'Save correction',
              variant: PillVariant.accent,
              onPressed: () async {
                if (note.text.trim().length < 3) {
                  gymToast(sheet, 'Write a short reason');
                  return;
                }
                final r = await gymSend(sheet, 'POST', '${ctx.base}/staff-attendance/correct', {
                  'member_id': i['member_id'],
                  'shift_id': i['shift_id'],
                  'work_date': i['work_date'],
                  'status': status,
                  'check_in': ?cin,
                  'check_out': ?cout,
                  'note': note.text.trim(),
                });
                if (r != null && sheet.mounted) Navigator.pop(sheet, true);
              },
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      gymToast(context, 'Attendance corrected. ${i['name']} has been notified.');
      _reload(clear: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GymPage(
      title: 'Staff Attendance',
      subtitle: _view == 'day' ? 'Who came in today, late, absent' : 'Monthly totals per staff member',
      onRefresh: _load,
      children: [
        SegmentTabs(
          options: const {'day': 'Day register', 'month': 'Month summary'},
          selected: _view,
          onChanged: (v) {
            _view = v;
            _reload();
          },
        ),
        const SizedBox(height: 12),
        BranchChips(ctx: ctx, selected: _branch, onChanged: (b) {
          _branch = b;
          _reload();
        }),
        if (ctx.branches.length > 1) const SizedBox(height: 12),
        if (_view == 'day') ..._dayView() else ..._monthView(),
      ],
    );
  }

  List<Widget> _dayView() {
    final items = ((_day?['items'] as List?) ?? []).cast<Map<String, dynamic>>();
    final working = items.where((i) => i['status'] != 'week_off').toList();
    final off = items.length - working.length;
    return [
      PickBox(label: 'Date', value: niceDate(isoDate(_date)), icon: Icons.calendar_today_outlined, onTap: _pickDate),
      if (_day == null)
        gymLoading
      else ...[
        attendanceCounts(_day!['counts'] as Map<String, dynamic>?),
        if (working.isEmpty) gymEmpty(items.isEmpty ? 'No staff shifts on this day. Assign shifts in Staff.' : 'Everyone has a week off on this day.'),
        for (final i in working)
          _AttendanceRow(
            item: i,
            title: '${i['name']} • ${i['role_name']}',
            sub: '${i['shift_name']} • ${time12(i['start_time'])} – ${time12(i['end_time'])}${ctx.branches.length > 1 ? ' • ${i['branch_name']}' : ''}',
            onTap: i['can_correct'] == true ? () => _correct(i) : null,
          ),
        if (off > 0) Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('$off shift(s) on week off today', style: const TextStyle(fontSize: 11, color: AppTheme.textSubtle)),
        ),
      ],
    ];
  }

  List<Widget> _monthView() {
    final staff = ((_summary?['staff'] as List?) ?? []).cast<Map<String, dynamic>>();
    return [
      _MonthNav(month: _month, onChanged: (m) {
        _month = m;
        _reload();
      }),
      if (_summary == null)
        gymLoading
      else ...[
        if (staff.isEmpty) gymEmpty('No staff shifts in ${_monthLabel(_month)}.'),
        for (final p in staff)
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${p['name']} • ${p['role_name']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                    Text('${p['counts']['scheduled']} shifts', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w700)),
                  ],
                ),
                if (ctx.branches.length > 1) Text(p['branch_name'] ?? '', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                const SizedBox(height: 8),
                attendanceCounts(p['counts'] as Map<String, dynamic>?),
              ],
            ),
          ),
      ],
    ];
  }
}

// =============================== Visits: who is inside now / who came today ===============================
//Added By Nikhil 22Nov26 20:53 For "Inside now" / "Visits today" tiles opening the list of members START

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key, required this.ctx, this.branch, this.insideOnly = true, this.onOpenMember});
  final GymCtx ctx;
  final String? branch;
  final bool insideOnly;
  /// Opens the member page (members.view); null = rows not tappable.
  final void Function(BuildContext context, String profileId)? onOpenMember;

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  late String _view = widget.insideOnly ? 'inside' : 'today';
  late String? _branch = widget.branch;
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = [if (_view == 'inside') 'inside=true', if (_branch != null) 'branch_id=$_branch'].join('&');
    final d = await gymGet(context, '${widget.ctx.base}/visits${q.isEmpty ? '' : '?$q'}');
    if (mounted) setState(() => _d = d ?? const {'visits': [], 'count': 0});
  }

  void _reload() {
    setState(() => _d = null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final visits = ((_d?['visits'] as List?) ?? []).cast<Map<String, dynamic>>();
    return GymPage(
      title: _view == 'inside' ? 'Inside Now' : 'Visits Today',
      subtitle: _d == null ? null : '${_d!['count']} member${_d!['count'] == 1 ? '' : 's'}',
      onRefresh: _load,
      children: [
        SegmentTabs(
          options: const {'inside': '🟢 Inside now', 'today': '📅 Today'},
          selected: _view,
          onChanged: (v) {
            _view = v;
            _reload();
          },
        ),
        const SizedBox(height: 12),
        BranchChips(ctx: widget.ctx, selected: _branch, onChanged: (b) {
          _branch = b;
          _reload();
        }),
        if (widget.ctx.branches.length > 1) const SizedBox(height: 12),
        if (_d == null)
          gymLoading
        else if (visits.isEmpty)
          gymEmpty(_view == 'inside' ? 'Nobody is inside right now.' : 'No visits yet today.')
        else
          for (final v in visits)
            DocCard(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 8),
              onTap: widget.onOpenMember == null ? null : () => widget.onOpenMember!(context, v['profile_id'] as String),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${v['name']} • ${v['member_code']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        Text(
                          [
                            v['check_out_at'] == null ? 'In since ${_clock(v['check_in_at'])}' : '${_clock(v['check_in_at'])} → ${_clock(v['check_out_at'])}',
                            if (v['forgot_checkout'] == true) 'since ${niceDate((v['check_in_at'] as String).substring(0, 10))} (forgot to check out)',
                            if (widget.ctx.branches.length > 1) v['branch_name'],
                          ].join(' • '),
                          style: TextStyle(fontSize: 11, color: v['forgot_checkout'] == true ? AppTheme.warningOrange : AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (v['inside'] == true)
                    const StatusChip('Inside', bg: AppTheme.successLight, fg: AppTheme.primaryDark, fontSize: 10)
                  else if (v['minutes'] != null)
                    StatusChip('${v['minutes'] ~/ 60}h ${v['minutes'] % 60}m', bg: AppTheme.chipBg, fg: AppTheme.label, fontSize: 10),
                ],
              ),
            ),
      ],
    );
  }
}
//Added By Nikhil 22Nov26 20:53 For "Inside now" / "Visits today" tiles opening the list of members END
