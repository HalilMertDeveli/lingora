// The AI cost guard reasons (functions/src/ai_guard.ts) get their own
// messages on every AI screen instead of "too short" or "quota used".
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/services/conversation.dart';
import 'package:lingora/services/explain_more.dart';
import 'package:lingora/services/rehearsal_service.dart';
import 'package:lingora/services/writing.dart';

void main() {
  test('App Check and budget reasons win over the per-feature texts', () {
    final appCheck = aiGuardMessage('app_check_required')!;
    final budget = aiGuardMessage('ai_budget')!;
    expect(
      CallableConversationService.messageForCode('failed-precondition', reason: 'app_check_required'),
      appCheck,
    );
    expect(
      CallableRehearsalService.messageForCode('failed-precondition', reason: 'app_check_required'),
      appCheck,
    );
    expect(CallableWritingService.messageForCode('resource-exhausted', reason: 'ai_budget'), budget);
    expect(CallableRehearsalService.messageForCode('resource-exhausted', reason: 'ai_budget'), budget);
    // "Neden yanlış?" ek açıklama used to say "hakkın doldu" when the whole
    // AI budget was spent.
    expect(CallableExplainMoreService.messageForCode('resource-exhausted', reason: 'ai_budget'), budget);
    expect(
      CallableExplainMoreService.messageForCode('resource-exhausted', reason: 'explain_quota'),
      contains('ek açıklama hakkın doldu'),
    );
  });

  test('other reasons keep the existing texts', () {
    expect(aiGuardMessage('free_quota'), isNull);
    expect(
      CallableRehearsalService.messageForCode('failed-precondition', reason: 'too_short'),
      contains('çok kısa'),
    );
    expect(
      CallableWritingService.messageForCode('resource-exhausted', reason: 'daily_quota'),
      contains('hakkın doldu'),
    );
  });
}
