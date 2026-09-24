import 'package:flutter/material.dart';

import 'chronique.dart';

const _monthLabels = <String>[
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

const String kScheduleRequiredMessage = 'Choisissez une date de publication';
const String kSchedulePastMessage = 'La date de publication doit être dans le futur';
const String kExpiresRequiredMessage = 'Choisissez une date d\'expiration';
const String kExpiresBeforeActivationMessage =
    'La date d\'expiration doit être après la publication';

enum ChroniqueExpirationPreset {
  none,
  oneHour,
  sixHours,
  twentyFourHours,
  seventyTwoHours,
  sevenDays,
  custom,
}

/// Conversion locale → UTC et format d’affichage. Pas dans les widgets.
abstract final class ChroniqueDateHelper {
  static String formatLocal(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = _monthLabels[local.month - 1];
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day $month ${local.year} • $hour:$minute';
  }

  /// ISO-8601 UTC avec suffixe `Z`. Jamais une date locale brute.
  static String toUtcIso(DateTime date) {
    return date.toUtc().toIso8601String();
  }

  static DateTime combineLocal(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  static DateTime? tryParse(String? raw) {
    return parseChroniqueDateTime(raw);
  }

  static DateTime? parseJsonDate(Object? raw) {
    return parseChroniqueDateTime(raw);
  }

  static String? scheduleError(DateTime? scheduledLocal, {DateTime? now}) {
    if (scheduledLocal == null) {
      return kScheduleRequiredMessage;
    }
    final clock = now ?? DateTime.now();
    if (!scheduledLocal.isAfter(clock)) {
      return kSchedulePastMessage;
    }
    return null;
  }

  static String? expirationError({
    required ChroniqueExpirationPreset preset,
    required DateTime activationLocal,
    DateTime? customLocal,
  }) {
    if (preset == ChroniqueExpirationPreset.none) {
      return null;
    }
    final expires = resolveExpirationLocal(
      preset: preset,
      activationLocal: activationLocal,
      customLocal: customLocal,
    );
    if (expires == null) {
      return kExpiresRequiredMessage;
    }
    if (!expires.isAfter(activationLocal)) {
      return kExpiresBeforeActivationMessage;
    }
    return null;
  }

  static DateTime? resolveExpirationLocal({
    required ChroniqueExpirationPreset preset,
    required DateTime activationLocal,
    DateTime? customLocal,
  }) {
    return switch (preset) {
      ChroniqueExpirationPreset.none => null,
      ChroniqueExpirationPreset.oneHour => activationLocal.add(const Duration(hours: 1)),
      ChroniqueExpirationPreset.sixHours => activationLocal.add(const Duration(hours: 6)),
      ChroniqueExpirationPreset.twentyFourHours =>
        activationLocal.add(const Duration(hours: 24)),
      ChroniqueExpirationPreset.seventyTwoHours =>
        activationLocal.add(const Duration(hours: 72)),
      ChroniqueExpirationPreset.sevenDays => activationLocal.add(const Duration(days: 7)),
      ChroniqueExpirationPreset.custom => customLocal,
    };
  }

  static String expirationLabel(ChroniqueExpirationPreset preset) {
    return switch (preset) {
      ChroniqueExpirationPreset.none => 'Non',
      ChroniqueExpirationPreset.oneHour => '1 heure',
      ChroniqueExpirationPreset.sixHours => '6 heures',
      ChroniqueExpirationPreset.twentyFourHours => '24 heures',
      ChroniqueExpirationPreset.seventyTwoHours => '72 heures',
      ChroniqueExpirationPreset.sevenDays => '7 jours',
      ChroniqueExpirationPreset.custom => 'Date personnalisée',
    };
  }

  static DateTime defaultScheduleLocal({DateTime? now}) {
    final clock = now ?? DateTime.now();
    return clock.add(const Duration(hours: 2));
  }
}

/// Date affichée selon le statut (archives = `archived_at`, programmé = `scheduled_at`).
DateTime? chroniqueDisplayDateTime(Chronique chronique) {
  if (chronique.status == 'archived') {
    return ChroniqueDateHelper.tryParse(chronique.archivedAt) ??
        ChroniqueDateHelper.tryParse(chronique.publishedAt);
  }
  if (chronique.status == 'scheduled') {
    return chronique.scheduledAt ?? ChroniqueDateHelper.tryParse(chronique.publishedAt);
  }
  if (chronique.status == 'expired') {
    return chronique.expiredAt ??
        chronique.expiresAt ??
        ChroniqueDateHelper.tryParse(chronique.publishedAt);
  }
  return ChroniqueDateHelper.tryParse(chronique.publishedAt) ??
      ChroniqueDateHelper.tryParse(chronique.createdAt);
}

String? chroniqueDisplayInstant(Chronique chronique) {
  final date = chroniqueDisplayDateTime(chronique);
  if (date == null) {
    return null;
  }
  return date.toIso8601String();
}

/// Exemple : `23 sept. 2026 • 15:57` (heure locale, sans secondes).
String formatChroniqueDateTime(DateTime date) => ChroniqueDateHelper.formatLocal(date);

String chroniqueDateLabel(Chronique chronique) {
  final date = chroniqueDisplayDateTime(chronique);
  if (date == null) {
    return '';
  }
  return ChroniqueDateHelper.formatLocal(date);
}

String? formatOptionalChroniqueDate(DateTime? date) {
  if (date == null) {
    return null;
  }
  return ChroniqueDateHelper.formatLocal(date);
}
