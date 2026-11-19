// lib/application/sms_import/auto_hide_otp_use_case.dart
//
// SetSmsAutoHideOtp: toggles the global "hide OTP messages automatically"
// setting through the [SmsSettings] port.

import 'package:finwick/application/mutation_gate.dart';
import 'package:finwick/domain/sms_import/ports/ports.dart';

class SetSmsAutoHideOtp {
  SetSmsAutoHideOtp({required this.settings, required this.gate});

  final SmsSettings settings;
  final MutationGate gate;

  /// Persists [value] and returns it (so the view model can update state).
  Future<bool> call(bool value) {
    return gate.run(() async {
      await settings.setAutoHideOtp(value);
      return value;
    });
  }
}
