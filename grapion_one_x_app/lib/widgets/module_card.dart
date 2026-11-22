// //Added By Nikhil 21Nov26 21:00 For module card shared by admin Modules tab and user My Modules
import 'package:flutter/material.dart';

import '../modules/module_registry.dart';
import '../theme/app_theme.dart';
import 'doc_ui.dart';

/// Admin "All Modules" card from the prototype: icon, name + 🚧 In Development pill, description,
/// and a Preview / Launch chip. Tapping opens the module when its code is implemented, else the dev modal.
class ModuleCard extends StatelessWidget {
  const ModuleCard({super.key, required this.module, this.footer});

  final Map<String, dynamic> module;
  final String? footer; // e.g. "Active until Dec 21, 2026"

  @override
  Widget build(BuildContext context) {
    final code = module['code'] as String?;
    final name = module['name'] as String? ?? '';
    final ready = ModuleRegistry.isModuleImplemented(code) && module['status'] != 'in_development';

    return DocCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      onTap: () {
        if (ready) {
          final screen = ModuleRegistry.getHomeScreen(code!, context);
          if (screen != null) {
            Navigator.of(context).push(docRoute(screen));
            return;
          }
        }
        showDevModuleDialog(context, name);
      },
      child: Row(
        children: [
          Text(module['icon'] as String? ?? '📦', style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                //Modified By Nikhil 21Nov26 22:36 For full name always visible (chip compacts to 🚧). Old: Row(Flexible(name, ellipsis), chip)
                NameWithChip(
                  name: name,
                  nameStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  chipText: ready ? null : '🚧 In Development',
                  compactChipText: '🚧',
                  chipBg: const Color(0xFFFFFBEB),
                ),
                if ((module['description'] as String?)?.isNotEmpty ?? false)
                  Text(module['description'], style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(footer!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(
            ready ? 'Launch' : 'Preview',
            bg: ready ? AppTheme.successLight : AppTheme.warningLight,
            fg: ready ? AppTheme.primaryDark : AppTheme.warningOrange,
            radius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
        ],
      ),
    );
  }
}
