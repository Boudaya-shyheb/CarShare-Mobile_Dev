import 'package:carshare/widgets/support_evidence_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('support evidence accepts only non-empty files up to 5 MB', () {
    expect(isSupportEvidenceSizeAllowed(0), isFalse);
    expect(isSupportEvidenceSizeAllowed(1), isTrue);
    expect(isSupportEvidenceSizeAllowed(supportMaxEvidenceBytes), isTrue);
    expect(isSupportEvidenceSizeAllowed(supportMaxEvidenceBytes + 1), isFalse);
  });
}
