// //Added By Nikhil 18Nov26 23:01 For Grapion Gym Module Manifest
import 'package:flutter/material.dart';
import '../module_registry.dart';
import 'gym_view_as.dart'; //Added By Nikhil 22Nov26 14:41 For admin "View as Owner / Member"

class GymModuleDefinition implements AppModuleDefinition {
  @override
  String get code => 'gym';

  @override
  String get name => 'Grapion Gym';

  //Modified By Nikhil 22Nov26 14:41 For Gym ready (owner, staff, members built). Old: /// Currently in active engineering - set to FALSE so it stays in Preview! ... isImplemented => false;
  @override
  bool get isImplemented => true;

  /// Opened from the admin Modules tab: admins choose to view the module as an Owner or as a Member.
  //Modified By Nikhil 22Nov26 14:41 For admin "View as" chooser. Old: Scaffold(body: Center(child: Text('Grapion Gym Dashboard')))
  @override
  Widget buildHomeScreen(BuildContext context) => const GymViewAsScreen();
}
