import 'dart:math';

import 'package:flutter/services.dart';

/// Unambiguous characters: digits 3,4,7,9 and letters A–Z excluding O, I, S, Z, B, G
/// (removes visually confusing: 0/O, 1/I, 2/Z, 5/S, 6/G, 8/B). Uppercase only.
const String kInviteAlphabet = '3479ACDEFHJKLMNPQRTUVWXY';

const int kInviteCodeLength = 6;

final Random _secureRandom = Random.secure();

/// Uppercase, strip spaces; does not validate characters.
String normalizeInviteCode(String raw) {
  return raw.toUpperCase().replaceAll(RegExp(r'\s'), '');
}

bool isInviteAlphabetChar(String char) {
  if (char.length != 1) return false;
  return kInviteAlphabet.contains(char);
}

/// True if [normalized] is exactly 6 characters from [kInviteAlphabet].
bool isValidInviteCodeFormat(String normalized) {
  if (normalized.length != kInviteCodeLength) return false;
  for (var i = 0; i < normalized.length; i++) {
    if (!isInviteAlphabetChar(normalized[i])) return false;
  }
  return true;
}

String generateRandomInviteCode() {
  final buf = StringBuffer();
  for (var i = 0; i < kInviteCodeLength; i++) {
    buf.write(kInviteAlphabet[_secureRandom.nextInt(kInviteAlphabet.length)]);
  }
  return buf.toString();
}

/// Forces uppercase; optionally strips invalid characters (for paste cleanup).
class InviteCodeTextFormatter extends TextInputFormatter {
  InviteCodeTextFormatter({this.stripInvalid = false});

  final bool stripInvalid;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var t = newValue.text.toUpperCase().replaceAll(RegExp(r'\s'), '');
    if (stripInvalid) {
      t = t.split('').where(isInviteAlphabetChar).join();
    }
    if (t.length > kInviteCodeLength) {
      t = t.substring(0, kInviteCodeLength);
    }
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}
