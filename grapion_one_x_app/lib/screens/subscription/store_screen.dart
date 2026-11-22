// //Added By Nikhil 18Nov26 21:41 For Dynamic DB Store & Active Festival Discounts
//Modified By Nikhil 21Nov26 21:00 For store matching ui_prototype_docspot + live currency + per-period discount. Old: full file backed up at D:\AI Agents Temp\grapion-one-x\GrapionOneX_DocSpot_CleanUI\21Nov26\backup\allscreens_2100_DesignMatch\ START
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../modules/module_registry.dart';
import '../../services/api_client.dart';
import '../../theme/app_theme.dart';
import '../../theme/motion.dart';
import '../../widgets/doc_ui.dart';

class StoreScreen extends StatefulWidget {
  //Modified By Nikhil 21Nov26 22:36 For add-modules / renew flow. Old: const StoreScreen({super.key});
  const StoreScreen({super.key, this.preselectCodes = const []});

  /// Module codes to pre-select (Renew button).
  final List<String> preselectCodes;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  static const _periods = {'weekly': 'Weekly', 'monthly': 'Monthly', 'quarterly': 'Quarterly', 'yearly': 'Yearly'};

  String _selectedPeriod = 'monthly';
  final Set<String> _selectedModuleIds = {};

  List<dynamic> _modules = [];
  Map<String, dynamic>? _discount;
  String _symbol = '₹';
  String _currency = 'INR';
  double _rate = 1.0;
  String? _fxSource;
  final Set<String> _ownedCodes = {}; //Added By Nikhil 21Nov26 22:36 For modules already active (each has its own dates)
  final Map<String, DateTime> _ownedEnds = {}; //Added By Nikhil 22Nov26 10:47 For current end date per active module (renewal extends it)
  static const _periodDays = {'weekly': 7, 'monthly': 30, 'quarterly': 90, 'yearly': 365}; //Added By Nikhil 22Nov26 10:47 For same days the server adds on approval
  static const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']; //Added By Nikhil 22Nov26 10:47 For short date
  String _d(DateTime d) => '${d.day} ${_mon[d.month - 1]} ${d.year}'; //Added By Nikhil 22Nov26 10:47 For short date
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  Future<void> _fetchCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await apiClient.get('/subscriptions/catalog');
      final mine = await apiClient.get('/subscriptions/my-modules'); //Added By Nikhil 21Nov26 22:36 For owned modules
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        //Added By Nikhil 21Nov26 22:36 For owned modules + renew pre-selection START
        _ownedCodes
          ..clear()
          ..addAll(mine.statusCode == 200
              ? ((jsonDecode(mine.body)['modules'] as List?) ?? []).map((m) => m['code'] as String)
              : const <String>[]);
        //Added By Nikhil 22Nov26 10:47 For end dates of active modules START
        _ownedEnds.clear();
        if (mine.statusCode == 200) {
          for (final m in ((jsonDecode(mine.body)['modules'] as List?) ?? [])) {
            final e = DateTime.tryParse(m['expires_at'] as String? ?? '');
            if (e != null) _ownedEnds[m['code'] as String] = e;
          }
        }
        //Added By Nikhil 22Nov26 10:47 For end dates of active modules END
        for (final m in (data['modules'] as List? ?? [])) {
          if (widget.preselectCodes.contains(m['code'])) { //Modified By Nikhil 22Nov26 10:47 For owned modules can be renewed. Old: && !_ownedCodes.contains(m['code'])
            _selectedModuleIds.add(m['id'] as String);
          }
        }
        //Added By Nikhil 21Nov26 22:36 For owned modules + renew pre-selection END
        setState(() {
          _modules = data['modules'] ?? [];
          _discount = data['active_discount'];
          _symbol = (data['currency_symbol'] as String? ?? '₹').trim();
          _currency = data['user_currency'] as String? ?? 'INR';
          _rate = (data['fx_rate'] as num? ?? 1).toDouble();
          _fxSource = data['fx_source'] as String?;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load module catalog';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e); //Modified By Nikhil 22Nov26 16:06 For clear error messages. Old: 'Connection error'
          _loading = false;
        });
      }
    }
  }

  /// Discount % for a period: the per-period column when the DB has it, else the single percent_off.
  double _pctFor(String period) {
    final d = _discount;
    if (d == null) return 0;
    final perPeriod = d['period_percent_off'] as Map<String, dynamic>?;
    final v = perPeriod?[period] ?? d['percent_off'];
    return (v as num? ?? 0).toDouble();
  }

  num _basePrice(dynamic m) => ((m['prices'] as Map<String, dynamic>)[_selectedPeriod] as num?) ?? 0;

  /// Same maths as the API (discount on the summed base, in INR) so the total shown = the amount requested.
  num _totalInr() {
    num base = 0;
    for (final m in _modules) {
      if (_selectedModuleIds.contains(m['id'])) base += _basePrice(m);
    }
    final pct = _pctFor(_selectedPeriod);
    return pct > 0 ? base - (base * pct / 100).floor() : base;
  }

  String _money(num inr) => formatMoney(inr, symbol: _symbol, rate: _rate);

  String? _bestPeriodBadge() {
    final perPeriod = _discount?['period_percent_off'] as Map<String, dynamic>?;
    if (perPeriod == null) return null;
    String? best;
    double bestPct = 0;
    for (final p in _periods.keys) {
      final v = _pctFor(p);
      if (v > bestPct) {
        bestPct = v;
        best = p;
      }
    }
    return best;
  }

  Future<void> _handleSubmitRequest() async {
    if (_selectedModuleIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least 1 module.')));
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await apiClient.post('/subscriptions/request', {
        'module_ids': _selectedModuleIds.toList(),
        'billing_period': _selectedPeriod,
      });
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 201) {
        // Design: submitting returns to the gate, which now shows "Approval Pending".
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop(true);
        messenger.showSnackBar(SnackBar(content: Text('Request ${data['request_number']} sent for admin approval')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] is String ? data['detail'] : 'Submission failed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error communicating with server')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: kScreenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: ScreenTitle(title: 'Choose Modules', subtitle: 'Select services for your business'),
                  ),
                  SmallPill(label: '← Back', onTap: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(child: _buildBody()),
              if (!_loading && _error == null) _buildFloatingBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            SizedBox(width: 140, child: PillButton(label: 'Retry', onPressed: _fetchCatalog)),
          ],
        ),
      );
    }
    final best = _bestPeriodBadge();
    return ListView(
      children: [
        if (_discount != null) _buildSaleBanner(),
        SegmentTabs(
          options: _periods,
          selected: _selectedPeriod,
          onChanged: (p) => setState(() => _selectedPeriod = p),
          badges: best == null ? const {} : {best: '-${_pctFor(best).round()}%'},
        ),
        const SizedBox(height: 16),
        for (final m in _modules) _buildModuleRow(m),
        if (_modules.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('No modules available right now.', style: TextStyle(color: AppTheme.textMuted))),
          ),
      ],
    );
  }

  Widget _buildSaleBanner() {
    final d = _discount!;
    final pct = _pctFor(_selectedPeriod);
    final from = formatServerDateTime(d['start_date'] as String?, withTime: false);
    final to = formatServerDateTime(d['end_date'] as String?, withTime: false);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)]),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '🎉 ${d['title']}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                    ),
                    if (pct > 0) DiscountBadge('-${pct % 1 == 0 ? pct.round() : pct}% OFF'),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Valid from $from – $to',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.warningOrange),
                ),
              ],
            ),
          ),
          const StatusChip(
            'Live Sale',
            bg: Colors.white,
            fg: Color(0xFFB45309),
            fontSize: 10,
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleRow(dynamic m) {
    final isSelected = _selectedModuleIds.contains(m['id']);
    final owned = _ownedCodes.contains(m['code']); //Added By Nikhil 21Nov26 22:36 For already-active modules
    final base = _basePrice(m);
    final pct = _pctFor(_selectedPeriod);
    final finalPrice = pct > 0 ? (base * (1 - pct / 100)).round() : base;
    // Preview when the DB says so OR the app has no implemented code for it (ModuleRegistry).
    final isDev = !ModuleRegistry.isModuleImplemented(m['code']) || m['status'] == 'in_development';

    return GestureDetector(
      //Modified By Nikhil 21Nov26 22:36 For owned modules not selectable. Old: onTap: () => setState(() => isSelected ? remove : add)
      //Modified By Nikhil 22Nov26 10:47 For owned modules selectable for renewal (any period). Old: onTap: owned ? snackbar 'already active' : toggle
      onTap: () => setState(() => isSelected ? _selectedModuleIds.remove(m['id']) : _selectedModuleIds.add(m['id'])),
      child: Opacity(opacity: 1, child: AnimatedContainer( //Modified By Nikhil 22Nov26 10:47 For owned not dimmed. Old: opacity: owned ? 0.55 : 1
        duration: AppMotion.fast,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.selectedBg : AppTheme.cardSubtle,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.cardBorder, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Text(m['icon'] ?? '📦', style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  //Modified By Nikhil 21Nov26 22:36 For full name always visible (chip compacts). Old: Row(Flexible(name, ellipsis), Preview chip)
                  NameWithChip(
                    name: m['name'] ?? '',
                    nameStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                    chipText: owned ? 'Active' : (isDev ? 'Preview' : null),
                    compactChipText: owned ? '✓' : '🚧',
                    chipBg: owned ? AppTheme.successLight : AppTheme.warningLight,
                    chipFg: owned ? AppTheme.primaryDark : AppTheme.warningOrange,
                    chipFontSize: 9,
                  ),
                  Text(m['description'] ?? '', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  //Added By Nikhil 22Nov26 10:47 For renewal: current end date and the new one START
                  if (owned && _ownedEnds[m['code']] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        isSelected
                            ? '🔁 Renew → new end date ${_d(_ownedEnds[m['code']]!.add(Duration(days: _periodDays[_selectedPeriod] ?? 30)))}'
                            : 'Active till ${_d(_ownedEnds[m['code']]!)} • tap to extend',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
                      ),
                    ),
                  //Added By Nikhil 22Nov26 10:47 For renewal: current end date and the new one END
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (pct > 0)
                  Text(
                    _money(base),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSubtle,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: AppTheme.textSubtle,
                    ),
                  ),
                Text(_money(finalPrice), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              ],
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: AppMotion.fast,
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? AppTheme.primary : const Color(0xFFCBD5E1), width: 2),
              ),
              child: isSelected ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
            ),
          ],
        ),
      )), //Modified By Nikhil 21Nov26 22:36 For closing Opacity
    );
  }

  Widget _buildFloatingBar() {
    final count = _selectedModuleIds.length;
    final totalInr = _totalInr();
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.cardBorder))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Calculated Total:', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  Text(_money(totalInr), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                ],
              ),
              StatusChip(
                '$count Module${count == 1 ? '' : 's'} Selected',
                bg: AppTheme.successLight,
                fg: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
            ],
          ),
          // Conversion note + required attribution for the free rates provider.
          if (_currency != 'INR')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '≈ converted from ${formatMoney(totalInr)} INR at today\'s rate${_fxSource != null ? ' • $_fxSource' : ''}',
                  style: const TextStyle(fontSize: 10, color: AppTheme.textSubtle),
                ),
              ),
            ),
          const SizedBox(height: 10),
          PillButton(
            label: 'Submit Subscription Request',
            variant: PillVariant.accent,
            loading: _submitting,
            onPressed: _handleSubmitRequest,
          ),
        ],
      ),
    );
  }
}
//Modified By Nikhil 21Nov26 21:00 For store matching ui_prototype_docspot + live currency + per-period discount END
