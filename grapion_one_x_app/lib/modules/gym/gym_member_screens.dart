// //Added By Nikhil 22Nov26 17:36 For member screens (step 5): home, check-in/out, membership, visits, payments & receipts, renew, gym info
// Based on grapion_gym_web/src/routes/_authed/member/*. Every call is the member's own data (/gym/{ws}/me/...).
import 'package:flutter/material.dart';

import '../../services/location_service.dart'; //Added By Nikhil 22Nov26 20:53 For location check-in
import '../../theme/app_theme.dart';
import '../../widgets/doc_ui.dart';
import 'gym_common.dart';

String _clock(String? iso) => iso == null || iso.length < 16 ? '' : time12(iso.substring(11, 16));
String _day(String? iso) => iso == null ? '' : niceDate(iso.substring(0, 10));
String _money(num? v) => formatMoney(v ?? 0);

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

// =============================== Member home (shown inside the gym home for the member role) ===============================

class MemberHomeSection extends StatefulWidget {
  const MemberHomeSection({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  State<MemberHomeSection> createState() => _MemberHomeSectionState();
}

class _MemberHomeSectionState extends State<MemberHomeSection> {
  Map<String, dynamic>? _h;
  bool _failed = false;
  bool _busy = false;

  String get _base => '/gym/${widget.workspaceId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '$_base/me/member');
    if (!mounted) return;
    setState(() {
      _h = d;
      _failed = d == null;
    });
  }

  Future<void> _visit(bool checkIn) async {
    setState(() => _busy = true);
    //Added By Nikhil 22Nov26 20:53 For location check-in: read GPS only when this gym has set its location START
    var body = <String, dynamic>{};
    if (checkIn && _h?['location_required'] == true) {
      final fix = await LocationService.current();
      if (!mounted) return;
      if (fix.error != null) {
        setState(() => _busy = false);
        return gymToast(context, fix.error!);
      }
      body = fix.toJson();
    }
    //Added By Nikhil 22Nov26 20:53 For location check-in END
    final r = await gymSend(context, 'POST', '$_base/me/visit/${checkIn ? 'checkin' : 'checkout'}', body, //Modified By Nikhil 22Nov26 20:53 For location body. Old: {},
        fallback: checkIn ? 'Could not check in' : 'Could not check out');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      gymToast(context, checkIn ? '✅ Checked in. Have a great workout!' : '👋 Checked out. See you next time!');
      _load();
    }
  }

  void _open(Widget w) => Navigator.of(context).push(docRoute(w)).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    final h = _h;
    if (h == null) return _failed ? gymEmpty('Could not load your membership. Pull down to try again.') : gymLoading;
    final ms = h['membership'] as Map<String, dynamic>?;
    final last = h['last_expired'] as Map<String, dynamic>?;
    final upcoming = (h['upcoming'] as List?) ?? const [];
    final days = (ms?['days_left'] as num?)?.toInt();
    final hours = h['hours_today'] as Map<String, dynamic>?;
    final visit = h['today_visit'] as Map<String, dynamic>?;
    final batch = h['batch'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- membership card
        DocCard(
          gradient: const LinearGradient(colors: [AppTheme.pillDark, Color(0xFF1E293B)]),
          borderColor: AppTheme.pillDark,
          padding: const EdgeInsets.all(18),
          onTap: () => _open(MyMembershipScreen(workspaceId: widget.workspaceId)), //Added By Nikhil 23Nov26 17:20 For Home card → same page as Profile → My Membership
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🏋️', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(ms != null ? '${ms['plan_name']}' : 'No active membership',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                  Text('${h['member_code']}', style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 10),
              if (ms != null) ...[
                Text(days == 1 ? '1 day left' : '$days days left',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: (days ?? 0) <= 7 ? const Color(0xFFFCD34D) : Colors.white)),
                Text('${_day(ms['start_date'])} → ${_day(ms['expiry_date'])}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                if ((days ?? 99) <= 7)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('Expiring soon — renew to keep training.', style: TextStyle(fontSize: 12, color: Color(0xFFFCD34D), fontWeight: FontWeight.w700)),
                  ),
              ] else
                Text(
                  last != null ? 'Your ${last['plan_name']} ended on ${_day(last['expiry_date'])}. Renew to continue.' : 'Ask the gym to start a plan, or renew below.',
                  style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                ),
              if (upcoming.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Next: ${upcoming.first['plan_name']} from ${_day(upcoming.first['start_date'])}',
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                ),
              const Padding( //Added By Nikhil 23Nov26 17:20 For showing the card opens My Membership
                padding: EdgeInsets.only(top: 8),
                child: Text('View membership details →', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        // ---- holiday / closed
        if (hours?['holiday'] != null)
          DocCard(
            padding: const EdgeInsets.all(14),
            gradient: const LinearGradient(colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)]),
            borderColor: AppTheme.warningLight,
            child: Text('🏖️ Gym closed today — ${hours!['holiday']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        // ---- check in / out
        DocCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('📍 Today at the gym', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                  if (hours != null && hours['open'] != null && hours['closed'] != true)
                    Text('${time12(hours['open'])} – ${time12(hours['close'])}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
              const SizedBox(height: 6),
              //Added By Nikhil 22Nov26 18:05 For "you forgot to check out" warning (visit stays open until the member checks out)
              if (h['forgot_checkout'] == true)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('⚠️ You forgot to check out (in since ${_day(h['inside_since'] as String?)}, ${_clock(h['inside_since'] as String?)}). Tap Check Out.',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.warningOrange)),
                ),
              Text(
                h['inside_now'] == true
                    ? 'You are checked in since ${_clock((h['inside_since'] as String?) ?? visit?['check_in_at'])}.' //Modified By Nikhil 22Nov26 18:05 For open visit from an earlier day. Old: _clock(visit?['check_in_at'])
                    : visit != null
                        ? "Today's visit: ${_clock(visit['check_in_at'])} → ${_clock(visit['check_out_at'])}"
                        : (h['check_in_note'] as String?) ?? 'Tap Check In when you arrive.',
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              if (h['can_check_in'] == true || h['can_check_out'] == true) ...[
                const SizedBox(height: 12),
                PillButton(
                  label: h['can_check_out'] == true ? 'Check Out' : 'Check In',
                  variant: h['can_check_out'] == true ? PillVariant.secondary : PillVariant.accent,
                  padding: const EdgeInsets.all(12),
                  fontSize: 13,
                  loading: _busy,
                  onPressed: _busy ? null : () => _visit(h['can_check_in'] == true),
                ),
              ],
            ],
          ),
        ),
        // ---- batch & trainer
        if (batch != null)
          DocCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Text('🗓', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My batch: ${batch['name']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      Text('${time12(batch['start_time'])} – ${time12(batch['end_time'])} • ${weekdaysLabel(batch['weekdays'] as List)}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      Text(
                        batch['trainer'] != null
                            ? 'Trainer: ${batch['trainer']}${batch['specialization'] != null ? ' • ${batch['specialization']}' : ''}'
                            : 'No trainer assigned yet',
                        style: const TextStyle(fontSize: 11, color: AppTheme.label),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        const Text('MY GYM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: AppTheme.textSubtle)),
        const SizedBox(height: 10),
        for (final (icon, title, sub, screen) in <(String, String, String, Widget)>[
          ('🎫', 'My Membership', 'Plan, dates, paid & history', MyMembershipScreen(workspaceId: widget.workspaceId)),
          ('📅', 'My Visits', 'Check-in history by month', MyVisitsScreen(workspaceId: widget.workspaceId)),
          ('🧾', 'Payments & Receipts', 'What you paid, verified or pending', MemberPaymentsScreen(workspaceId: widget.workspaceId)),
          ('🔁', 'Renew Membership', 'Pay the gym by UPI and confirm here', RenewScreen(workspaceId: widget.workspaceId)),
          ('📍', 'Gym Info', 'Timings, holidays, contact', GymInfoScreen(workspaceId: widget.workspaceId)),
        ])
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            onTap: () => _open(screen),
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 22)),
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
                const Icon(Icons.chevron_right, color: AppTheme.textSubtle),
              ],
            ),
          ),
      ],
    );
  }
}

// =============================== My Membership ===============================

class MyMembershipScreen extends StatefulWidget {
  const MyMembershipScreen({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  State<MyMembershipScreen> createState() => _MyMembershipScreenState();
}

class _MyMembershipScreenState extends State<MyMembershipScreen> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '/gym/${widget.workspaceId}/me/payments');
    if (mounted) setState(() => _d = d ?? const {'memberships': []});
  }

  @override
  Widget build(BuildContext context) {
    final list = ((_d?['memberships'] as List?) ?? []).cast<Map<String, dynamic>>();
    final today = isoDate(DateTime.now());
    return GymPage(
      title: 'My Membership',
      subtitle: _d?['member_code'] != null ? 'Member ID ${_d!['member_code']}' : null,
      onRefresh: _load,
      children: [
        if (_d == null) gymLoading else if (list.isEmpty) gymEmpty('No membership yet. Ask the gym to start a plan.'),
        for (final m in list)
          () {
            final current = (m['start_date'] as String).compareTo(today) <= 0 && (m['expiry_date'] as String).compareTo(today) >= 0;
            final future = (m['start_date'] as String).compareTo(today) > 0;
            final (label, bg, fg) = m['status'] == 'cancelled'
                ? ('Cancelled', AppTheme.chipBg, AppTheme.textMuted)
                : current
                    ? ('Active', AppTheme.successLight, AppTheme.primaryDark)
                    : future
                        ? ('Upcoming', const Color(0xFFEFF6FF), AppTheme.accentBlue)
                        : ('Ended', AppTheme.errorLight, AppTheme.errorRed);
            return DocCard(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('${m['plan_name']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                      StatusChip(label, bg: bg, fg: fg, fontSize: 10),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${_day(m['start_date'])} → ${_day(m['expiry_date'])}', style: const TextStyle(fontSize: 12, color: AppTheme.label)),
                  const SizedBox(height: 6),
                  Text('Total ${_money(m['total'])} • Paid ${_money(m['paid'])}${((m['pending'] as num?) ?? 0) > 0 ? ' • Pending ${_money(m['pending'])}' : ''}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            );
          }(),
      ],
    );
  }
}

// =============================== My Visits ===============================

class MyVisitsScreen extends StatefulWidget {
  const MyVisitsScreen({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  State<MyVisitsScreen> createState() => _MyVisitsScreenState();
}

class _MyVisitsScreenState extends State<MyVisitsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _d;

  String get _key => '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '/gym/${widget.workspaceId}/me/visits?month=$_key');
    if (mounted) setState(() => _d = d ?? const {'visits': [], 'count': 0, 'days': 0});
  }

  void _go(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _d = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final visits = ((_d?['visits'] as List?) ?? []).cast<Map<String, dynamic>>();
    return GymPage(
      title: 'My Visits',
      subtitle: 'Your check-ins at the gym',
      onRefresh: _load,
      children: [
        Row(
          children: [
            IconButton(tooltip: 'Previous month', onPressed: () => _go(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('${_months[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            IconButton(tooltip: 'Next month', onPressed: isCurrent ? null : () => _go(1), icon: const Icon(Icons.chevron_right)),
          ],
        ),
        const SizedBox(height: 8),
        if (_d == null)
          gymLoading
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 6, children: [
              StatusChip('${_d!['days']} days', bg: AppTheme.successLight, fg: AppTheme.primaryDark, fontSize: 11),
              StatusChip('${_d!['count']} visits', bg: AppTheme.chipBg, fg: AppTheme.label, fontSize: 11),
            ]),
          ),
          if (visits.isEmpty) gymEmpty('No visits in ${_months[_month.month - 1]}.'),
          for (final v in visits)
            DocCard(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_day(v['check_in_at']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                        Text('${_clock(v['check_in_at'])} → ${v['check_out_at'] != null ? _clock(v['check_out_at']) : 'inside'}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  if (v['minutes'] != null)
                    StatusChip('${v['minutes'] ~/ 60}h ${v['minutes'] % 60}m', bg: AppTheme.chipBg, fg: AppTheme.label, fontSize: 10),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

// =============================== Payments & Receipts ===============================

class MemberPaymentsScreen extends StatefulWidget {
  const MemberPaymentsScreen({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  State<MemberPaymentsScreen> createState() => _MemberPaymentsScreenState();
}

class _MemberPaymentsScreenState extends State<MemberPaymentsScreen> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '/gym/${widget.workspaceId}/me/payments');
    if (mounted) setState(() => _d = d ?? const {'payments': []});
  }

  void _receipt(Map<String, dynamic> p) {
    showGymSheet<void>(
      context,
      title: 'Payment receipt',
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (k, v) in [
            ('Member ID', '${_d?['member_code'] ?? ''}'),
            ('Amount', _money(p['amount'])),
            ('Towards', '${p['towards'] ?? 'Gym payment'}'),
            ('Method', '${p['method']}'.toUpperCase()),
            if (p['reference'] != null) ('Reference', '${p['reference']}'),
            ('Paid on', _day(p['paid_on'])),
            ('Status', p['status'] == 'verified' ? 'Verified${p['verified_on'] != null ? ' on ${_day(p['verified_on'])}' : ''}' : 'Pending — the gym will verify it'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(width: 100, child: Text(k, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted))),
                  Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pays = ((_d?['payments'] as List?) ?? []).cast<Map<String, dynamic>>();
    return GymPage(
      title: 'Payments & Receipts',
      subtitle: 'Tap a payment to see its receipt',
      onRefresh: _load,
      children: [
        if (_d == null) gymLoading else if (pays.isEmpty) gymEmpty('No payments yet.'),
        for (final p in pays)
          DocCard(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 8),
            onTap: () => _receipt(p),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_money(p['amount']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      Text('${p['towards'] ?? 'Gym payment'} • ${_day(p['paid_on'])} • ${'${p['method']}'.toUpperCase()}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                StatusChip(
                  p['status'] == 'verified' ? 'Verified' : 'Pending',
                  bg: p['status'] == 'verified' ? AppTheme.successLight : AppTheme.warningLight,
                  fg: p['status'] == 'verified' ? AppTheme.primaryDark : AppTheme.warningOrange,
                  fontSize: 10,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// =============================== Renew ===============================

class RenewScreen extends StatefulWidget {
  const RenewScreen({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  State<RenewScreen> createState() => _RenewScreenState();
}

class _RenewScreenState extends State<RenewScreen> {
  Map<String, dynamic>? _d;
  String? _plan;
  final _ref = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '/gym/${widget.workspaceId}/me/renew-options');
    if (mounted) setState(() => _d = d ?? const {'plans': []});
  }

  Future<void> _submit() async {
    if (_plan == null) return gymToast(context, 'Choose a plan');
    final ref = _ref.text.trim();
    if (ref.length < 4) return gymToast(context, 'Enter the last 4–6 digits of the UPI reference (UTR)');
    setState(() => _saving = true);
    final r = await gymSend(context, 'POST', '/gym/${widget.workspaceId}/me/renew', {'plan_id': _plan, 'reference_last_digits': ref},
        fallback: 'Could not send your renewal');
    if (!mounted) return;
    setState(() => _saving = false);
    if (r != null) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Sent to your gym', style: TextStyle(fontWeight: FontWeight.w800)),
          content: Text('${_money(r['amount'])} for ${r['plan']} is waiting for the gym to confirm. '
              'Your new dates appear here once they verify the payment.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ((_d?['plans'] as List?) ?? []).cast<Map<String, dynamic>>();
    final chosen = plans.where((p) => p['id'] == _plan).firstOrNull;
    return GymPage(
      title: 'Renew Membership',
      subtitle: 'Pay your gym, then confirm here',
      onRefresh: _load,
      children: [
        if (_d == null)
          gymLoading
        else if (plans.isEmpty)
          gymEmpty('Your gym has not added plans yet. Please contact the gym to renew.')
        else ...[
          const FieldLabel('1. Choose a plan'),
          for (final p in plans)
            DocCard(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 8),
              borderColor: _plan == p['id'] ? AppTheme.primary : AppTheme.cardBorder,
              onTap: () => setState(() => _plan = p['id'] as String),
              child: Row(
                children: [
                  Icon(_plan == p['id'] ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: _plan == p['id'] ? AppTheme.primary : AppTheme.textSubtle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${p['name']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                        Text('${p['months']} month${p['months'] == 1 ? '' : 's'}${p['description'] != null ? ' • ${p['description']}' : ''}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  Text(_money(p['price']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const FieldLabel('2. Pay your gym by UPI'),
          DocCard(
            padding: const EdgeInsets.all(14),
            child: _d!['upi_id'] == null
                ? const Text('Your gym has not added a UPI ID. Pay at the front desk instead.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('${_d!['upi_id']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      if (_d!['upi_payee_name'] != null) Text('${_d!['upi_payee_name']}', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      if (chosen != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Amount: ${_money(chosen['price'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          const FieldLabel('3. Confirm your payment'),
          DocField(label: 'Last 4–6 digits of the UPI reference (UTR)', controller: _ref, keyboardType: TextInputType.text, hint: 'e.g. 482913'),
          PillButton(label: 'Send to gym', variant: PillVariant.accent, loading: _saving, onPressed: _upiReady ? _submit : null),
          const SizedBox(height: 8),
          const Text('The gym checks the payment and then starts your new plan. Never share your UPI PIN with anyone.',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ],
    );
  }

  bool get _upiReady => _d?['upi_id'] != null;
}

// =============================== Gym info ===============================

class GymInfoScreen extends StatefulWidget {
  const GymInfoScreen({super.key, required this.workspaceId});
  final String workspaceId;

  @override
  State<GymInfoScreen> createState() => _GymInfoScreenState();
}

class _GymInfoScreenState extends State<GymInfoScreen> {
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await gymGet(context, '/gym/${widget.workspaceId}/me/gym-info');
    if (mounted) setState(() => _d = d ?? const {});
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final hours = ((d?['hours'] as List?) ?? []).cast<Map<String, dynamic>>();
    final hols = ((d?['holidays'] as List?) ?? []).cast<Map<String, dynamic>>();
    return GymPage(
      title: 'Gym Info',
      subtitle: d?['gym'] != null ? '${d!['gym']} • ${d['branch']}' : null,
      onRefresh: _load,
      children: [
        if (d == null)
          gymLoading
        else ...[
          DocCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contact', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                if (d['address'] != null) Text('📍 ${d['address']}', style: const TextStyle(fontSize: 12)),
                if (d['phone'] != null) SelectableText('📞 ${d['phone']}', style: const TextStyle(fontSize: 12)),
                if (d['upi_id'] != null) SelectableText('💳 UPI: ${d['upi_id']}', style: const TextStyle(fontSize: 12)),
                if (d['address'] == null && d['phone'] == null) const Text('Ask at the front desk.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ),
          DocCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Opening hours', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final h in hours)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 48, child: Text(weekdayShort[(h['weekday'] as int) - 1], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                        Text(h['closed'] == true ? 'Closed' : '${time12(h['open'])} – ${time12(h['close'])}',
                            style: TextStyle(fontSize: 12, color: h['closed'] == true ? AppTheme.errorRed : AppTheme.label)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          DocCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Upcoming holidays', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                if (hols.isEmpty) const Text('No holidays announced.', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                for (final h in hols) Text('🏖️ ${_day(h['date'])} — ${h['reason']}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
