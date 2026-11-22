// //Added By Nikhil 21Nov26 21:00 For shared design widgets from ui_prototype_docspot
// One place for the prototype's building blocks (.pill-btn, .doc-input, .period-tabs, .doc-card,
// back pills, brand pill, dev modal, tab/page transition) so every screen looks the same.
import 'dart:convert'; //Added By Nikhil 21Nov26 22:44 For apiDetail
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
//Removed By Nikhil 21Nov26 21:16 For bundled fonts (google_fonts 9 targets material_ui): import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';

enum PillVariant { dark, secondary, accent }

/// .pill-btn — full-width rounded button (dark / secondary / accent).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PillVariant.dark,
    this.loading = false,
    this.foreground,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    this.fontSize = 14,
    this.fontWeight = FontWeight.w700,
  });

  final String label;
  final VoidCallback? onPressed;
  final PillVariant variant;
  final bool loading;
  final Color? foreground;
  final EdgeInsets padding;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (variant) {
      PillVariant.dark => (AppTheme.pillDark, Colors.white),
      PillVariant.secondary => (AppTheme.chipBg, AppTheme.secondaryText),
      PillVariant.accent => (AppTheme.primary, Colors.white),
    };
    final textColor = foreground ?? fg;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: onPressed == null && !loading ? bg.withValues(alpha: 0.6) : bg,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: loading ? null : onPressed,
          child: Padding(
            padding: padding,
            child: Center(
              child: loading
                  ? SizedBox(
                      height: fontSize + 4,
                      width: fontSize + 4,
                      child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
                    )
                  : Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: textColor),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small grey pill used for "← Sign In", "← Cancel", "← Back", "Sign Out" (.period-tab with #F1F5F9).
class SmallPill extends StatelessWidget {
  const SmallPill({
    super.key,
    required this.label,
    required this.onTap,
    this.color = AppTheme.textMuted,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
  });

  final String label;
  final VoidCallback onTap;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.chipBg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ),
    );
  }
}

/// .screen-title + .screen-subtitle
class ScreenTitle extends StatelessWidget {
  const ScreenTitle({super.key, required this.title, this.subtitle, this.size = 22, this.trailing});

  final String title;
  final String? subtitle;
  final double size;
  final Widget? trailing; // e.g. "1 New" badge next to the title

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
        ],
      ],
    );
  }
}

/// .input-group (label + .doc-input). Visual style comes from AppTheme.inputDecorationTheme.
class DocField extends StatefulWidget {
  const DocField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<DocField> createState() => _DocFieldState();
}

class _DocFieldState extends State<DocField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // .doc-input:focus turns the fill white.
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(widget.label),
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.obscure,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.inputFormatters,
            maxLength: widget.maxLength,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            autofillHints: widget.autofillHints,
            style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: widget.hint,
              fillColor: _focus.hasFocus ? Colors.white : AppTheme.cardSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

/// .input-label
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.label)),
    );
  }
}

/// .period-tabs — segmented pill tabs (store periods, payment methods).
class SegmentTabs extends StatelessWidget {
  const SegmentTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.badges = const {},
  });

  final Map<String, String> options; // key -> label
  final String selected;
  final ValueChanged<String> onChanged;
  final Map<String, String> badges; // key -> small red badge text, e.g. "-20%"

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppTheme.chipBg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        children: [
          for (final e in options.entries) ...[
            if (e.key != options.keys.first) const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(e.key),
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: selected == e.key ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: selected == e.key
                        ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 2))]
                        : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: selected == e.key ? AppTheme.textPrimary : AppTheme.textMuted,
                          ),
                        ),
                        if (badges[e.key] != null) ...[
                          const SizedBox(width: 4),
                          DiscountBadge(badges[e.key]!),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// .badge-discount
class DiscountBadge extends StatelessWidget {
  const DiscountBadge(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: AppTheme.errorLight, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.errorRed)),
    );
  }
}

/// .doc-card
class DocCard extends StatelessWidget {
  const DocCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = const EdgeInsets.only(bottom: 14),
    this.gradient,
    this.borderColor = AppTheme.cardBorder,
    this.leftAccent,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Gradient? gradient;
  final Color borderColor;
  final Color? leftAccent; // border-left: 4px solid …
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusLg);
    Widget content = Padding(padding: padding, child: child);
    if (leftAccent != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: leftAccent!, width: 4))),
        child: content,
      );
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: gradient == null ? Colors.white : null,
        gradient: gradient,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: AppTheme.shadowCard,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: onTap, child: content),
        ),
      ),
    );
  }
}

/// Small rounded status chip ("Pending", "Preview", "Admin Access", "1 New").
class StatusChip extends StatelessWidget {
  const StatusChip(
    this.text, {
    super.key,
    required this.bg,
    required this.fg,
    this.radius = 99,
    this.fontSize = 11,
    this.fontWeight = FontWeight.w700,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
  });

  final String text;
  final Color bg;
  final Color fg;
  final double radius;
  final double fontSize;
  final FontWeight fontWeight;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: Text(text, maxLines: 1, softWrap: false, style: TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: fg)),
    );
  }
}

/// G.ONE.X dark brand pill (login header).
class BrandPill extends StatelessWidget {
  const BrandPill({super.key});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: 'Orbitron', fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.pillDark,
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Text.rich(
        TextSpan(style: style, children: const [
          TextSpan(text: 'G.ONE.'),
          TextSpan(text: 'X', style: TextStyle(color: AppTheme.primary)),
        ]),
      ),
    );
  }
}

/// Inline error / success message box (not in the prototype, kept for real API feedback).
class MessageBanner extends StatelessWidget {
  const MessageBanner(this.message, {super.key, this.success = false});
  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final fg = success ? const Color(0xFF15803D) : AppTheme.errorRed;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: success ? AppTheme.selectedBg : AppTheme.errorLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: success ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
      ),
      child: Text(message, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// Standard screen body padding (.screen-content: 16 22 24 22).
const EdgeInsets kScreenPadding = EdgeInsets.fromLTRB(22, 16, 22, 24);

/// Page route with the prototype's tab-in motion: fade + rise 12px + scale 0.985 → 1 (350ms).
Route<T> docRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: AppMotion.tabIn,
    reverseTransitionDuration: AppMotion.fast,
    pageBuilder: (context, a1, a2) => page,
    transitionsBuilder: (context, anim, secondary, child) => TabInTransition(animation: anim, child: child),
  );
}

/// The prototype's `tabSlideFadeIn` keyframes as a reusable transition.
class TabInTransition extends StatelessWidget {
  const TabInTransition({super.key, required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.smooth);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, c) => Opacity(
        opacity: curved.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - curved.value)),
          child: Transform.scale(scale: 0.985 + 0.015 * curved.value, child: c),
        ),
      ),
      child: child,
    );
  }
}

/// .dev-modal — "`moduleName` (In Development)" with a blurred backdrop and pop-in.
Future<void> showDevModuleDialog(BuildContext context, String moduleName) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x8C0F172A),
    transitionDuration: AppMotion.modalPop,
    pageBuilder: (ctx, a1, a2) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.cardBorder),
                boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 40, offset: Offset(0, 20))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppTheme.warningLight, shape: BoxShape.circle),
                    child: const Text('🚧', style: TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '$moduleName (In Development)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  const Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.5),
                      children: [
                        TextSpan(text: 'This module is currently being developed and is in active engineering.\n'),
                        TextSpan(
                          text: 'Contact administrator for further details.',
                          style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  PillButton(
                    label: 'Understood',
                    variant: PillVariant.accent,
                    padding: const EdgeInsets.all(12),
                    fontSize: 13,
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, a2, child) {
      final pop = CurvedAnimation(parent: anim, curve: AppMotion.modalPopCurve);
      return BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 5 * anim.value, sigmaY: 5 * anim.value),
        child: FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(pop), child: child),
        ),
      );
    },
  );
}

// ---------- formatting helpers ----------

/// Groups digits in threes: 12749 -> "12,749".
String groupDigits(num value) {
  final s = value.round().abs().toString();
  final buf = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Display price: INR amount converted with the catalog's live rate (prototype rounds to whole units).
String formatMoney(num amountInr, {String symbol = '₹', double rate = 1.0}) =>
    '$symbol${groupDigits(amountInr * rate)}';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "2026-11-18T20:45:10+05:30" -> "Nov 18, 2026 • 20:45".
/// The API already sends server time (APP_TIMEZONE), so we read the wall-clock part as-is
/// instead of converting to the phone's zone.
String formatServerDateTime(String? iso, {bool withTime = true}) {
  if (iso == null || iso.length < 16) return '';
  final d = DateTime.tryParse(iso.substring(0, 19));
  if (d == null) return '';
  final date = '${_months[d.month - 1]} ${d.day}, ${d.year}';
  if (!withTime) return date;
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$date • $hh:$mm';
}

/// "Aarav Sharma" -> "AS"  //Modified By Nikhil 22Nov26 12:22 For neutral placeholder. Old: "Nikhil Kamble" -> "NK"
String initialsOf(String first, String last) {
  String pick(String s) => s.trim().isEmpty ? '' : s.trim()[0].toUpperCase();
  final r = '${pick(first)}${pick(last)}';
  return r.isEmpty ? '?' : r;
}

//Added By Nikhil 21Nov26 22:36 For name + status chip on one line without cutting the name START
/// Module name with a status chip on the same line (prototype layout).
/// The name is never cut: if the full chip does not fit beside it, the chip shrinks to its compact
/// form (e.g. "🚧"), which still carries the full text for screen readers.
class NameWithChip extends StatelessWidget {
  const NameWithChip({
    super.key,
    required this.name,
    required this.nameStyle,
    this.chipText,
    this.compactChipText,
    this.chipBg = AppTheme.warningLight,
    this.chipFg = AppTheme.warningOrange,
    this.chipFontSize = 10,
  });

  final String name;
  final TextStyle nameStyle;
  final String? chipText; // null = no chip
  final String? compactChipText;
  final Color chipBg;
  final Color chipFg;
  final double chipFontSize;

  double _width(BuildContext context, String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final nameText = Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle);
    if (chipText == null) return nameText;

    return LayoutBuilder(
      builder: (context, constraints) {
        final chipStyle = TextStyle(fontSize: chipFontSize, fontWeight: FontWeight.w700);
        const chipPad = 12.0, gap = 6.0; // horizontal padding 6+6
        final fits = _width(context, name, nameStyle) + gap + _width(context, chipText!, chipStyle) + chipPad <=
            constraints.maxWidth;
        final label = fits ? chipText! : (compactChipText ?? chipText!);
        return Row(
          children: [
            Flexible(child: nameText),
            const SizedBox(width: gap),
            Semantics(
              label: chipText,
              excludeSemantics: true,
              child: StatusChip(
                label,
                bg: chipBg,
                fg: chipFg,
                fontSize: chipFontSize,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              ),
            ),
          ],
        );
      },
    );
  }
}
//Added By Nikhil 21Nov26 22:36 For name + status chip on one line without cutting the name END

//Added By Nikhil 21Nov26 22:44 For reason prompts (cancel / reject) START
/// Asks for a short reason (min 2 chars). Returns the text, or null if dismissed.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  String? message,
  String label = 'Reason',
  String hint = 'Tell us why',
  String confirmLabel = 'Submit',
  bool destructive = true,
}) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      String? err;
      return StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(message, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4)),
                ),
              if (err != null) MessageBanner(err!),
              DocField(label: label, controller: ctrl, hint: hint, maxLength: 500),
            ],
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'Back',
                    variant: PillVariant.secondary,
                    padding: const EdgeInsets.all(10),
                    fontSize: 12,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PillButton(
                    label: confirmLabel,
                    variant: destructive ? PillVariant.dark : PillVariant.accent,
                    foreground: destructive ? const Color(0xFFFCA5A5) : null,
                    padding: const EdgeInsets.all(10),
                    fontSize: 12,
                    onPressed: () {
                      final r = ctrl.text.trim();
                      if (r.length < 2) {
                        setD(() => err = 'Please enter a reason (min 2 characters).');
                        return;
                      }
                      Navigator.pop(ctx, r);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  ctrl.dispose();
  return result;
}

/// Reads `detail` from an API error body.
String apiDetail(String body, String fallback) {
  try {
    final d = jsonDecode(body)['detail'];
    return d is String ? d : fallback;
  } catch (_) {
    return fallback;
  }
}
//Added By Nikhil 21Nov26 22:44 For reason prompts (cancel / reject) END
