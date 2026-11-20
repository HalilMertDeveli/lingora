import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lingora/nav/course_badge.dart';

void main() {
  testWidgets('top bar course name: whole when it fits, else its first word', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    const style = TextStyle(fontSize: 14, fontWeight: FontWeight.w800);
    expect(fittedCourseName(ctx, 'Genel İngilizce', style, 400), 'Genel İngilizce');
    // Galaxy QA: with 283 XP and 218 gold the chip showed a cut "Genel İ…".
    expect(fittedCourseName(ctx, 'Genel İngilizce', style, 70), 'Genel');
    expect(fittedCourseName(ctx, 'YDS', style, 70), 'YDS');
  });
}
