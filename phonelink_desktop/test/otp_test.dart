import 'package:flutter_test/flutter_test.dart';
import 'package:phonelink_desktop/otp.dart';

void main() {
  test('ordinary amounts, numbers and IDs never become OTPs', () {
    for (final body in [
      'Dear BANU, avail pre-qualified Axis Bank Gold Loan of up to INR 1519000. To apply, visit https://Axbk.in/AXISMR/Aw2Ask7HoLE T&C*.',
      'Recharge now your Jio no. 8850783530 with Rs.899 plan.',
      'Your installation for Order ID: PT-80322-1810 is complete.',
      'INR 1015.00 spent using ICICI Bank Card XX6007. SMS BLOCK 6007 to 9215676766.',
      'Your account balance is Rs 123456.00.',
      'Sale code 2026: get Rs 1000 off your next order.',
      'Never share OTP. Your account 12345678 has balance INR 1000.',
      'Do not share your OTP. Transaction reference: 87654321.',
      'Your verification code is unavailable. Reference: 123456.',
      'Verification code: visit https://example.com/123456 to request a code.',
    ]) {
      expect(extractOtp(body), isEmpty, reason: body);
    }
  });

  test('extracts credentials next to an explicit OTP purpose', () {
    final cases = {
      'Your OTP is 637383 from ICICI bank.': '637383',
      'OTP: 0042. Do not share it.': '0042',
      '137508 is your confirmation code. Wix.': '137508',
      'Your verification code is 123456.': '123456',
      'Use 987654 as your login code.': '987654',
      'One-Time Password: 936983 for transaction of INR 1015.00 on card XX6007.':
          '936983',
      'For INR 1519000, your OTP is 654321.': '654321',
      'Your OTP is 123456. Order ID: 87654321.': '123456',
      'Account ending 6007: your security code is 543210.': '543210',
      'Your OTP for this purchase is 777888. Valid for 10 minutes.': '777888',
      'सत्यापन कोड: 123456': '123456',
      'OTP 123456 expires on 17/11/2026.': '123456',
    };
    for (final entry in cases.entries) {
      expect(extractOtp(entry.key), entry.value, reason: entry.key);
    }
  });

  test('does not guess between multiple codes or accept embedded IDs', () {
    for (final body in [
      'OTP: 123456. Verification code: 654321.',
      'Your OTP request ID is 123456. Please wait.',
      'Your verification code is ABC123456XYZ.',
      'Your OTP is 1234567890.',
      'Your OTP is INR 123456.',
    ]) {
      expect(extractOtp(body), isEmpty, reason: body);
    }
  });
}
