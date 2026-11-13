import 'package:flutter/material.dart';

import '../services/api_client.dart' show ApiException;
import '../theme.dart';

/// What the server said about an email it refused (`email_invalid`, `email_disposable`,
/// `email_undeliverable`), and the correction it suggested, if any.
class EmailProblem {
  const EmailProblem(this.message, {this.suggestion});
  final String message;
  final String? suggestion;

  /// The problem behind [error], or null when the error is about something else.
  static EmailProblem? from(Object error) {
    if (error is! ApiException) return null;
    const codes = {'email_invalid', 'email_disposable', 'email_undeliverable'};
    if (!codes.contains(error.code)) return null;
    return EmailProblem(error.message, suggestion: error.suggestion);
  }
}

/// Shown under the email field: the friendly message, and a "Did you mean …?" button that
/// fills the suggested address in.
class EmailProblemNotice extends StatelessWidget {
  const EmailProblemNotice({
    super.key,
    required this.problem,
    required this.onUseSuggestion,
  });

  final EmailProblem problem;
  final ValueChanged<String> onUseSuggestion;

  @override
  Widget build(BuildContext context) {
    final suggestion = problem.suggestion;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: carShareDangerTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 18, color: carShareDanger),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  problem.message,
                  style: const TextStyle(color: carShareText, height: 1.35),
                ),
              ),
            ],
          ),
          if (suggestion != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onUseSuggestion(suggestion),
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text('Did you mean $suggestion?'),
              ),
            ),
        ],
      ),
    );
  }
}
