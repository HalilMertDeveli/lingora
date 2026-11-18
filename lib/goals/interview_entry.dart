import 'package:flutter/material.dart';

import '../data/scenarios.dart';
import '../screens/conversation_screen.dart';

/// Entry point of the İş görüşmesi goal (home goal card, goal plan).
///
/// The interview rehearsal flow is built on its own branch
/// (feature/mulakat-provasi); whichever branch merges second points this
/// function at that screen. Until then it opens the "İş görüşmesi"
/// conversation scenario. No numeric score is ever shown for interviews.
///
/// TODO(mulakat-provasi): once lib/screens/rehearsal/rehearsal_screen.dart is
/// on main, replace the body with `return openRehearsal(context);`.
Future<void> openInterviewRehearsal(BuildContext context) {
  final scenario = scenarios.firstWhere((s) => s.id == 'interview', orElse: () => scenarios.first);
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ConversationScreen(scenario: scenario)));
}
