// //Added By Nikhil 18Nov26 23:00 For Universal Dynamic Module Registry
import 'package:flutter/material.dart';

/// Contract that any module in G.One.X must implement.
abstract class AppModuleDefinition {
  String get code;
  String get name;
  bool get isImplemented;
  Widget buildHomeScreen(BuildContext context);
}

/// The Single Source of Truth for compiled vertical code in the app.
class ModuleRegistry {
  static final Map<String, AppModuleDefinition> _registeredModules = {};

  /// Register an implemented module definition
  static void register(AppModuleDefinition module) {
    _registeredModules[module.code.toLowerCase().trim()] = module;
  }

  /// Safe query: Returns TRUE ONLY IF:
  /// 1. The module code exists in the app code
  /// 2. Its manifest explicitly says isImplemented == true
  /// 
  /// In ALL other cases (e.g. unknown row in DB, missing code/folder, isImplemented == false):
  /// Returns FALSE -> ENFORCES PREVIEW / IN DEVELOPMENT MODE!
  static bool isModuleImplemented(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return false;
    final cleanCode = moduleCode.toLowerCase().trim();
    final module = _registeredModules[cleanCode];
    if (module == null) {
      // Code / folder does NOT exist in the app!
      return false;
    }
    return module.isImplemented;
  }

  static Widget? getHomeScreen(String moduleCode, BuildContext context) {
    final cleanCode = moduleCode.toLowerCase().trim();
    final module = _registeredModules[cleanCode];
    if (module != null && module.isImplemented) {
      return module.buildHomeScreen(context);
    }
    return null;
  }
}
