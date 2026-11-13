import 'package:flutter/widgets.dart';

/// Calls [onResume] each time the app returns to the foreground, then shows [child] unchanged.
/// For screens whose data can change while the app sits in the background (an admin decided
/// something on another phone), so they never show a stale list after the user comes back.
class ResumeRefresh extends StatefulWidget {
  const ResumeRefresh({super.key, required this.onResume, required this.child});

  final VoidCallback onResume;
  final Widget child;

  @override
  State<ResumeRefresh> createState() => _ResumeRefreshState();
}

class _ResumeRefreshState extends State<ResumeRefresh>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) widget.onResume();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
