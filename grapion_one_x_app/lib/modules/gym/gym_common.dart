// //Added By Nikhil 22Nov26 08:41 For shared Grapion Gym UI pieces (context, page frame, branch chips, weekday + time pickers, sheets)
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
//Removed By Nikhil 22Nov26 10:47 For chips replaced by dropdown (no animation import needed): import '../../theme/motion.dart';
import '../../widgets/doc_ui.dart';

/// What every gym screen needs: which business, which branches, what the caller may do.
/// Permissions here only hide buttons; the server checks every request again.
class GymCtx {
  GymCtx({required this.workspaceId, required this.name, required this.isOwner, required this.permissions, required this.branches});

  final String workspaceId;
  final String name;
  final bool isOwner;
  final Set<String> permissions;
  final List<Map<String, dynamic>> branches;

  String get base => '/gym/$workspaceId';
  bool can(String perm) => permissions.contains('gym.$perm');
  String branchName(String? id) => branches.firstWhere((b) => b['id'] == id, orElse: () => const {'name': ''})['name'] as String;

  factory GymCtx.fromOverview(Map<String, dynamic> o) => GymCtx(
        workspaceId: o['workspace']['id'] as String,
        name: o['workspace']['name'] as String,
        isOwner: o['is_owner'] == true,
        permissions: ((o['permissions'] as List?) ?? []).cast<String>().toSet(),
        branches: ((o['branches'] as List?) ?? []).cast<Map<String, dynamic>>(),
      );
}

void gymToast(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

const gymLoading = Padding(
  padding: EdgeInsets.symmetric(vertical: 60),
  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
);

Widget gymEmpty(String text) => DocCard(
      child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13))),
    );

//Added By Nikhil 22Nov26 10:47 For empty state with a next step (e.g. "No expired members" + Add Member) START
Widget gymEmptyAction(String text, {String? actionLabel, VoidCallback? onAction, String emoji = '📭'}) => DocCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            PillButton(label: actionLabel, variant: PillVariant.accent, onPressed: onAction),
          ],
        ],
      ),
    );
//Added By Nikhil 22Nov26 10:47 For empty state with a next step END

/// GET helper: decoded JSON or null (and a toast with the server's message).
Future<Map<String, dynamic>?> gymGet(BuildContext context, String path) async {
  try {
    final res = await apiClient.get(path);
    if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, dynamic>;
    if (context.mounted) gymToast(context, apiDetail(res.body, 'Could not load'));
  } catch (e) { //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: catch (_)
    if (context.mounted) gymToast(context, friendlyError(e)); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: 'Connection error'
  }
  return null;
}

/// POST/PUT helper: returns decoded body on 2xx, otherwise shows the error and returns null.
Future<Map<String, dynamic>?> gymSend(BuildContext context, String method, String path, Map<String, dynamic> body,
    {String fallback = 'Could not save'}) async {
  try {
    final res = method == 'PUT' ? await apiClient.put(path, body) : await apiClient.post(path, body);
    if (res.statusCode == 200 || res.statusCode == 201) return jsonDecode(res.body) as Map<String, dynamic>;
    if (context.mounted) gymToast(context, _validation(res.body) ?? apiDetail(res.body, fallback));
  } catch (e) { //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: catch (_)
    if (context.mounted) gymToast(context, friendlyError(e)); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: 'Connection error'
  }
  return null;
}

/// FastAPI 422 → first readable message ("End time must be after the start time").
String? _validation(String body) {
  try {
    final d = jsonDecode(body)['detail'];
    if (d is List && d.isNotEmpty) {
      final msg = (d.first['msg'] ?? '').toString().replaceFirst('Value error, ', '');
      final field = (d.first['loc'] as List?)?.last?.toString().replaceAll('_', ' ');
      return msg.startsWith('String should') || msg.startsWith('Input should') ? 'Check $field: $msg' : msg;
    }
  } catch (_) {}
  return null;
}

/// Title + back + optional action, pull to refresh, staggered entrance.
class GymPage extends StatelessWidget {
  const GymPage({super.key, required this.title, this.subtitle, required this.onRefresh, required this.children, this.fab, this.trailing});
  final String title;
  final String? subtitle;
  final Future<void> Function() onRefresh;
  final List<Widget> children;
  final Widget? fab;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: fab,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 96),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: ScreenTitle(title: title, subtitle: subtitle)),
                  ?trailing,
                  const SizedBox(width: 6),
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

Widget gymFab(String label, VoidCallback onTap) => FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: AppTheme.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );

/// Branch picker. //Modified By Nikhil 22Nov26 10:47 For one dropdown instead of a chip per branch (long lists stay tidy). Old: horizontal chip row (full copy: AI Agents Temp\grapion-one-x\GymModuleSetup\22Nov26\backup\ui_feedback_1047)
/// `allowAll` false → must pick one.
class BranchChips extends StatelessWidget {
  const BranchChips({super.key, required this.ctx, required this.selected, required this.onChanged, this.allowAll = true});
  final GymCtx ctx;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool allowAll;

  @override
  Widget build(BuildContext context) {
    if (ctx.branches.length < 2) return const SizedBox.shrink();
    return GymPillDropdown<String?>(
      icon: Icons.storefront_outlined,
      value: selected,
      items: [if (allowAll) (null, 'All branches'), for (final b in ctx.branches) (b['id'] as String, b['name'] as String)],
      onChanged: onChanged,
    );
  }
}

//Added By Nikhil 22Nov26 10:47 For compact pill dropdown (branch, status filters) START
class GymPillDropdown<T> extends StatelessWidget {
  const GymPillDropdown({super.key, required this.value, required this.items, required this.onChanged, this.icon});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final current = items.any((i) => i.$1 == value) ? value : items.first.$1;
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(color: AppTheme.chipBg, borderRadius: BorderRadius.circular(99)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: current,
          isExpanded: true,
          isDense: false,
          borderRadius: BorderRadius.circular(16),
          dropdownColor: Colors.white,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.label),
          selectedItemBuilder: (_) => [
            for (final (_, l) in items)
              Row(
                children: [
                  if (icon != null) ...[Icon(icon, size: 16, color: AppTheme.label), const SizedBox(width: 8)],
                  Expanded(
                    child: Text(l, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  ),
                ],
              ),
          ],
          items: [
            for (final (v, l) in items)
              DropdownMenuItem<T>(value: v, child: Text(l, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ],
          onChanged: (v) => onChanged(v as T),
        ),
      ),
    );
  }
}
//Added By Nikhil 22Nov26 10:47 For compact pill dropdown (branch, status filters) END

const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String weekdaysLabel(List days) {
  final d = days.cast<int>().toList()..sort();
  if (d.length == 7) return 'Every day';
  if (d.join(',') == '1,2,3,4,5,6') return 'Mon – Sat';
  if (d.join(',') == '1,2,3,4,5') return 'Mon – Fri';
  return d.map((x) => weekdayShort[x - 1]).join(', ');
}

/// 7 toggle chips, ISO weekdays 1..7.
class WeekdayPicker extends StatelessWidget {
  const WeekdayPicker({super.key, required this.value, required this.onChanged});
  final Set<int> value;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 1; i <= 7; i++)
          FilterChip(
            label: Text(weekdayShort[i - 1]),
            selected: value.contains(i),
            showCheckmark: false,
            selectedColor: AppTheme.successLight,
            side: BorderSide(color: value.contains(i) ? AppTheme.primary : AppTheme.borderSubtle),
            labelStyle: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: value.contains(i) ? AppTheme.primaryDark : AppTheme.label),
            onSelected: (on) => onChanged({...value}..removeWhere((d) => d == i)..addAll(on ? {i} : {})),
          ),
      ],
    );
  }
}

/// Tappable box showing a value (date / time) — same look as DocField.
class PickBox extends StatelessWidget {
  const PickBox({super.key, required this.label, required this.value, required this.icon, required this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
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
                    Icon(icon, size: 16, color: AppTheme.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay parseHhmm(String? s, TimeOfDay fallback) {
  if (s == null || !s.contains(':')) return fallback;
  final p = s.split(':');
  return TimeOfDay(hour: int.tryParse(p[0]) ?? fallback.hour, minute: int.tryParse(p[1]) ?? fallback.minute);
}

/// 12-hour display of "HH:MM".
String time12(String? s) {
  if (s == null) return '';
  final t = parseHhmm(s, const TimeOfDay(hour: 0, minute: 0));
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
}

String isoDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String niceDate(String? iso) => iso == null ? '' : formatServerDateTime('${iso.substring(0, 10)}T00:00:00', withTime: false);

Future<TimeOfDay?> pickTime(BuildContext context, TimeOfDay initial) => showTimePicker(context: context, initialTime: initial);

Future<DateTime?> pickDate(BuildContext context, DateTime initial, {DateTime? first, DateTime? last}) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(2020),
      lastDate: last ?? DateTime(2035),
    );

/// Bottom-sheet frame used by every editor. Returns whatever the sheet pops.
/// `disposeAfter`: text controllers the sheet uses — disposed only when the sheet has fully left the screen
/// (after the close/drag-down animation), never while its text boxes are still on screen.
//Modified By Nikhil 22Nov26 10:47 For drag-down crash (_dependents.isEmpty). Old: callers disposed controllers as soon as the future returned
Future<T?> showGymSheet<T>(BuildContext context,
    {required String title, required Widget Function(BuildContext) builder, List<ChangeNotifier> disposeAfter = const []}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (sheetCtx) => _DisposeWithSheet(notifiers: disposeAfter, child: Padding( //Modified By Nikhil 22Nov26 10:47 For sheet-owned disposal. Old: builder: (sheetCtx) => Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.viewInsetsOf(sheetCtx).bottom),
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
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            builder(sheetCtx),
          ],
        ),
      ),
    )), //Modified By Nikhil 22Nov26 10:47 For sheet-owned disposal wrapper. Old: ),
  );
}

//Added By Nikhil 22Nov26 10:47 For controllers disposed when the sheet is unmounted (after its exit animation) START
class _DisposeWithSheet extends StatefulWidget {
  const _DisposeWithSheet({required this.notifiers, required this.child});
  final List<ChangeNotifier> notifiers;
  final Widget child;
  @override
  State<_DisposeWithSheet> createState() => _DisposeWithSheetState();
}

class _DisposeWithSheetState extends State<_DisposeWithSheet> {
  @override
  void dispose() {
    for (final n in widget.notifiers) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
//Added By Nikhil 22Nov26 10:47 For controllers disposed when the sheet is unmounted (after its exit animation) END

/// Simple dropdown in the DocField style.
class DocDropdown<T> extends StatelessWidget {
  const DocDropdown({super.key, required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T? value;
  final List<(T, String)> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label),
          DropdownButtonFormField<T>(
            initialValue: value,
            isExpanded: true,
            items: [for (final (v, l) in items) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
            onChanged: onChanged,
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
          ),
        ],
      ),
    );
  }
}

/// Shown once after the owner creates a login: username + temporary password to hand over in person.
Future<void> showTempPassword(BuildContext context, String username, String password) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Login created', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Share these in person. The password is shown only once — they must set their own on first login.',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          const SizedBox(height: 14),
          SelectableText('Username: $username', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          SelectableText('Temporary password: $password', style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primaryDark)),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
    ),
  );
}
