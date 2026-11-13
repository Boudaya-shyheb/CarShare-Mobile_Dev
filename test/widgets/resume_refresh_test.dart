import 'package:carshare/widgets/resume_refresh.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calls back only when the app returns to the foreground', (
    tester,
  ) async {
    var resumes = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ResumeRefresh(onResume: () => resumes++, child: const Text('x')),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(resumes, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(resumes, 1);
  });

  testWidgets('stops listening once it is removed from the tree', (
    tester,
  ) async {
    var resumes = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ResumeRefresh(onResume: () => resumes++, child: const Text('x')),
      ),
    );
    await tester.pumpWidget(const SizedBox());

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(resumes, 0);
  });
}
