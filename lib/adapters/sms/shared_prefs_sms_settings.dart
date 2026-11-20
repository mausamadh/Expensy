// Adapter: persists the SMS import settings (global OTP auto-hide) via
// SharedPreferences, behind the domain [SmsSettings] port.
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/sms_import/ports/ports.dart';

class SharedPreferencesSmsSettings implements SmsSettings {
  static const String _autoHideOtpKey = 'sms_auto_hide_otp';
  static const String _liveCaptureKey = 'sms_live_capture_enabled';

  const SharedPreferencesSmsSettings();

  @override
  Future<bool> getAutoHideOtp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoHideOtpKey) ?? true;
  }

  @override
  Future<void> setAutoHideOtp(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoHideOtpKey, value);
  }

  @override
  Future<bool> getLiveCaptureEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_liveCaptureKey) ?? false;
  }

  @override
  Future<void> setLiveCaptureEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liveCaptureKey, value);
  }
}
