import 'dart:convert';

import 'package:zedu/core/core.dart';
import 'package:zedu/features/features.dart';

/// Client-side persistence for message reminders, keyed by user and org so a
/// reminder never shows up for another account or workspace.
///
/// Uses the app's [SecureStorageService], looked up on first use. Storage can
/// fail (a locked keychain, a missing entitlement, no storage at all), so
/// neither call throws: [load] falls back to an empty list and [save] reports
/// whether it worked.
class ReminderStore {
  ReminderStore(this._storage, {required String userId, required String orgId})
    : _key = 'message_reminders_${userId}_$orgId';

  final SecureStorageService Function() _storage;
  final String _key;

  Future<List<MessageReminder>> load() async {
    try {
      final raw = await _storage().readData(_key);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [for (final entry in decoded) ?MessageReminder.tryFromJson(entry)];
    } catch (_) {
      return const [];
    }
  }

  /// Returns false when the list could not be saved.
  Future<bool> save(List<MessageReminder> reminders) async {
    try {
      if (reminders.isEmpty) {
        await _storage().deleteValue(_key);
      } else {
        await _storage().writeData(
          _key,
          jsonEncode([for (final r in reminders) r.toJson()]),
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
