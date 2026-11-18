final _otpPurpose = RegExp(
  r'\b(?:otp|one[\s-]*time\s+(?:password|passcode|code)|(?:verification|confirmation|security|authentication|login|sign[\s-]*in|access)\s+(?:code|passcode)|passcode)\b|ओटीपी|सत्यापन\s+कोड',
  caseSensitive: false,
);
final _digits = RegExp(r'(?<![A-Za-z0-9_])\d{4,8}(?![A-Za-z0-9_])');
final _urlsAndDates = RegExp(
  r'https?://\S+|www\.\S+|\b\d{1,4}[/\-]\d{1,2}[/\-]\d{1,4}\b',
  caseSensitive: false,
);
final _moneyBefore = RegExp(
  r'(?:\b(?:inr|rs\.?|usd|eur|gbp|amount|balance|limit|price|total)\s*[:=]?\s*[₹$€£]?\s*|[₹$€£]\s*)$',
  caseSensitive: false,
);
final _moneyAfter = RegExp(
  r'^\s*(?:inr|rupees|usd|eur|gbp)\b',
  caseSensitive: false,
);
final _referenceBefore = RegExp(
  r'\b(?:account|a/c|card|order|reference|ref|transaction|txn|invoice|ticket|customer|booking|mobile|phone|request)(?:\s+(?:number|no\.?|id|ref(?:erence)?|ending(?:\s+in)?))?\s*[:#=\-]?\s*(?:is\s*)?$',
  caseSensitive: false,
);
final _warningBefore = RegExp(
  r"(?:do\s+not|don't|never)\s+share\s+(?:(?:your|the)\s+)?$",
  caseSensitive: false,
);
final _directBridge = RegExp(
  r'''^[\s:;=#\-–—"'’]*(?:(?:is|your|the|a|an|as|for|use|code|password|passcode)\b[\s:;=#\-–—"'’]*)*$''',
  caseSensitive: false,
);

/// Conservative local detection: an explicit OTP purpose is required. Ambiguous
/// messages return no code rather than auto-copying a financial/reference value.
String extractOtp(String message) {
  final purposes = _otpPurpose.allMatches(message).where((purpose) {
    final before = message.substring(0, purpose.start);
    return !_warningBefore.hasMatch(before);
  }).toList();
  if (purposes.isEmpty) return '';
  final excludedSpans = _urlsAndDates.allMatches(message).toList();
  final candidates = _digits.allMatches(message).where((number) {
    if (excludedSpans.any(
      (span) => number.start < span.end && number.end > span.start,
    )) {
      return false;
    }
    final before = message.substring(0, number.start);
    final after = message.substring(number.end);
    if (_moneyBefore.hasMatch(before) ||
        _moneyAfter.hasMatch(after) ||
        _referenceBefore.hasMatch(before)) {
      return false;
    }
    // Reject decimal/grouped amounts and numeric fragments of hyphenated IDs.
    if (RegExp(r'\d[.,/\-]$').hasMatch(before) ||
        RegExp(r'^[.,/\-]\d').hasMatch(after)) {
      return false;
    }
    return true;
  }).toList();

  final direct = <String>{};
  final nearby = <String>{};
  for (final number in candidates) {
    for (final purpose in purposes) {
      final String bridge;
      if (number.start >= purpose.end) {
        bridge = message.substring(purpose.end, number.start);
      } else if (purpose.start >= number.end) {
        bridge = message.substring(number.end, purpose.start);
      } else {
        continue;
      }
      if (bridge.length <= 80) nearby.add(number.group(0)!);
      if (bridge.length <= 32 && _directBridge.hasMatch(bridge)) {
        direct.add(number.group(0)!);
      }
    }
  }
  if (direct.length == 1) return direct.single;
  if (direct.isNotEmpty) return '';
  return nearby.length == 1 ? nearby.single : '';
}
