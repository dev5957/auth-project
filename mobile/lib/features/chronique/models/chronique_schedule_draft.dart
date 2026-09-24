import 'chronique.dart';
import 'chronique_date.dart';

/// Mode de publication local. Distinct du JSON API.
enum ChroniquePublishMode {
  now,
  schedule,
}

/// Brouillon local de programmation / expiration. Pas un modèle API.
class ChroniqueScheduleDraft {
  const ChroniqueScheduleDraft({
    this.publishMode = ChroniquePublishMode.now,
    this.scheduledAt,
    this.expirationEnabled = false,
    this.expirationPreset = ChroniqueExpirationPreset.oneHour,
    this.customExpiresAt,
  });

  final ChroniquePublishMode publishMode;
  final DateTime? scheduledAt;
  final bool expirationEnabled;
  final ChroniqueExpirationPreset expirationPreset;
  final DateTime? customExpiresAt;

  /// Valeur interne / contrat API : `now` | `schedule`.
  String get publish =>
      publishMode == ChroniquePublishMode.schedule ? 'schedule' : 'now';

  ChroniqueExpirationPreset get effectivePreset => expirationEnabled
      ? (expirationPreset == ChroniqueExpirationPreset.none
          ? ChroniqueExpirationPreset.oneHour
          : expirationPreset)
      : ChroniqueExpirationPreset.none;

  DateTime activationLocal({DateTime? now}) {
    final clock = now ?? DateTime.now();
    if (publishMode == ChroniquePublishMode.schedule) {
      return scheduledAt ?? ChroniqueDateHelper.defaultScheduleLocal(now: clock);
    }
    return clock;
  }

  DateTime? resolvedExpiresLocal({DateTime? now}) {
    return ChroniqueDateHelper.resolveExpirationLocal(
      preset: effectivePreset,
      activationLocal: activationLocal(now: now),
      customLocal: customExpiresAt,
    );
  }

  String? validationError({DateTime? now}) {
    final clock = now ?? DateTime.now();
    if (publishMode == ChroniquePublishMode.schedule) {
      final scheduleError = ChroniqueDateHelper.scheduleError(
        scheduledAt,
        now: clock,
      );
      if (scheduleError != null) {
        return scheduleError;
      }
    }
    return ChroniqueDateHelper.expirationError(
      preset: effectivePreset,
      activationLocal: activationLocal(now: clock),
      customLocal: customExpiresAt,
    );
  }

  String? apiScheduledAt() {
    if (publishMode != ChroniquePublishMode.schedule || scheduledAt == null) {
      return null;
    }
    return ChroniqueDateHelper.toUtcIso(scheduledAt!);
  }

  bool get apiIsTimeLimited => effectivePreset != ChroniqueExpirationPreset.none;

  String? apiExpiresAt({DateTime? now}) {
    if (!apiIsTimeLimited) {
      return null;
    }
    final expires = resolvedExpiresLocal(now: now);
    if (expires == null) {
      return null;
    }
    return ChroniqueDateHelper.toUtcIso(expires);
  }

  ChroniqueScheduleDraft copyWith({
    ChroniquePublishMode? publishMode,
    DateTime? scheduledAt,
    bool? expirationEnabled,
    ChroniqueExpirationPreset? expirationPreset,
    DateTime? customExpiresAt,
    bool clearScheduledAt = false,
    bool clearCustomExpiresAt = false,
  }) {
    return ChroniqueScheduleDraft(
      publishMode: publishMode ?? this.publishMode,
      scheduledAt: clearScheduledAt ? null : (scheduledAt ?? this.scheduledAt),
      expirationEnabled: expirationEnabled ?? this.expirationEnabled,
      expirationPreset: expirationPreset ?? this.expirationPreset,
      customExpiresAt:
          clearCustomExpiresAt ? null : (customExpiresAt ?? this.customExpiresAt),
    );
  }

  factory ChroniqueScheduleDraft.fromChronique(Chronique chronique) {
    final scheduled = chronique.scheduledAt?.toLocal();
    final expires = chronique.expiresAt?.toLocal();
    final limited = chronique.isTimeLimited && expires != null;
    return ChroniqueScheduleDraft(
      publishMode: chronique.status == 'scheduled'
          ? ChroniquePublishMode.schedule
          : ChroniquePublishMode.now,
      scheduledAt: scheduled,
      expirationEnabled: limited,
      expirationPreset:
          limited ? ChroniqueExpirationPreset.custom : ChroniqueExpirationPreset.oneHour,
      customExpiresAt: expires,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChroniqueScheduleDraft &&
        publishMode == other.publishMode &&
        scheduledAt == other.scheduledAt &&
        expirationEnabled == other.expirationEnabled &&
        expirationPreset == other.expirationPreset &&
        customExpiresAt == other.customExpiresAt;
  }

  @override
  int get hashCode => Object.hash(
        publishMode,
        scheduledAt,
        expirationEnabled,
        expirationPreset,
        customExpiresAt,
      );
}
