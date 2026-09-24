import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../models/chronique_date.dart';
import '../../models/chronique_schedule_draft.dart';

/// Champs locaux de publication et d’expiration (CREATE étape 2 / édition scheduled).
class ChroniquePublicationFields extends StatelessWidget {
  const ChroniquePublicationFields({
    super.key,
    required this.draft,
    required this.onChanged,
    this.enabled = true,
    this.showPublishMode = true,
  });

  final ChroniqueScheduleDraft draft;
  final ValueChanged<ChroniqueScheduleDraft> onChanged;
  final bool enabled;
  final bool showPublishMode;

  Future<void> _pickScheduledDate(BuildContext context) async {
    final initial = draft.scheduledAt ?? ChroniqueDateHelper.defaultScheduleLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) {
      return;
    }
    onChanged(
      draft.copyWith(
        scheduledAt: ChroniqueDateHelper.combineLocal(
          picked,
          TimeOfDay.fromDateTime(draft.scheduledAt ?? initial),
        ),
      ),
    );
  }

  Future<void> _pickScheduledTime(BuildContext context) async {
    final initial = draft.scheduledAt ?? ChroniqueDateHelper.defaultScheduleLocal();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null) {
      return;
    }
    onChanged(
      draft.copyWith(scheduledAt: ChroniqueDateHelper.combineLocal(initial, picked)),
    );
  }

  Future<void> _pickExpiresDate(BuildContext context) async {
    final initial = draft.customExpiresAt ??
        draft.activationLocal().add(const Duration(hours: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null) {
      return;
    }
    onChanged(
      draft.copyWith(
        customExpiresAt: ChroniqueDateHelper.combineLocal(
          picked,
          TimeOfDay.fromDateTime(draft.customExpiresAt ?? initial),
        ),
      ),
    );
  }

  Future<void> _pickExpiresTime(BuildContext context) async {
    final initial = draft.customExpiresAt ??
        draft.activationLocal().add(const Duration(hours: 1));
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null) {
      return;
    }
    onChanged(
      draft.copyWith(customExpiresAt: ChroniqueDateHelper.combineLocal(initial, picked)),
    );
  }

  Widget _sectionTitle(String label, Color color) {
    return Text(
      label,
      style: AppTextTheme.titleSmall.copyWith(color: color),
    );
  }

  Widget _dateButton({
    required Key key,
    required String label,
    required String value,
    required VoidCallback? onPressed,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTextTheme.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton(
          key: key,
          onPressed: onPressed,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(value),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final scheduled = draft.publishMode == ChroniquePublishMode.schedule;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showPublishMode) ...[
          _sectionTitle('Publication', colors.textSecondary),
          ListTile(
            key: const ValueKey('publish-now'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              scheduled ? Icons.radio_button_off : Icons.radio_button_checked,
              color: colors.primary,
            ),
            title: Text(
              'Maintenant',
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
            ),
            onTap: enabled
                ? () => onChanged(
                      draft.copyWith(publishMode: ChroniquePublishMode.now),
                    )
                : null,
          ),
          ListTile(
            key: const ValueKey('publish-schedule'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              scheduled ? Icons.radio_button_checked : Icons.radio_button_off,
              color: colors.primary,
            ),
            title: Text(
              'Programmer',
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
            ),
            onTap: enabled
                ? () => onChanged(
                      draft.copyWith(
                        publishMode: ChroniquePublishMode.schedule,
                        scheduledAt:
                            draft.scheduledAt ?? ChroniqueDateHelper.defaultScheduleLocal(),
                      ),
                    )
                : null,
          ),
        ],
        if (scheduled) ...[
          if (!showPublishMode) ...[
            _sectionTitle('Publication', colors.textSecondary),
            const SizedBox(height: AppSpacing.sm),
          ],
          _dateButton(
            key: const ValueKey('schedule-date'),
            label: 'Date de publication',
            value: draft.scheduledAt == null
                ? 'Choisir'
                : ChroniqueDateHelper.formatLocal(draft.scheduledAt!).split(' • ').first,
            onPressed: enabled ? () => _pickScheduledDate(context) : null,
          ),
          const SizedBox(height: AppSpacing.md),
          _dateButton(
            key: const ValueKey('schedule-time'),
            label: 'Heure de publication',
            value: draft.scheduledAt == null
                ? 'Choisir'
                : ChroniqueDateHelper.formatLocal(draft.scheduledAt!).split(' • ').last,
            onPressed: enabled ? () => _pickScheduledTime(context) : null,
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        _sectionTitle('Expiration', colors.textSecondary),
        ListTile(
          key: const ValueKey('expiration-no'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            draft.expirationEnabled
                ? Icons.radio_button_off
                : Icons.radio_button_checked,
            color: colors.primary,
          ),
          title: Text(
            'Non',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          onTap: enabled
              ? () => onChanged(draft.copyWith(expirationEnabled: false))
              : null,
        ),
        ListTile(
          key: const ValueKey('expiration-yes'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            draft.expirationEnabled
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
            color: colors.primary,
          ),
          title: Text(
            'Oui',
            style: AppTextTheme.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          onTap: enabled
              ? () => onChanged(
                    draft.copyWith(
                      expirationEnabled: true,
                      expirationPreset: draft.expirationPreset ==
                              ChroniqueExpirationPreset.none
                          ? ChroniqueExpirationPreset.oneHour
                          : draft.expirationPreset,
                    ),
                  )
              : null,
        ),
        if (draft.expirationEnabled) ...[
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<ChroniqueExpirationPreset>(
            key: const ValueKey('expiration-dropdown'),
            value: draft.effectivePreset,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: [
              for (final preset in ChroniqueExpirationPreset.values)
                if (preset != ChroniqueExpirationPreset.none)
                  DropdownMenuItem(
                    value: preset,
                    child: Text(ChroniqueDateHelper.expirationLabel(preset)),
                  ),
            ],
            onChanged: enabled
                ? (value) {
                    if (value == null) {
                      return;
                    }
                    var next = draft.copyWith(expirationPreset: value);
                    if (value == ChroniqueExpirationPreset.custom) {
                      next = next.copyWith(
                        customExpiresAt: draft.customExpiresAt ??
                            draft.activationLocal().add(const Duration(hours: 1)),
                      );
                    }
                    onChanged(next);
                  }
                : null,
          ),
          if (draft.effectivePreset == ChroniqueExpirationPreset.custom) ...[
            const SizedBox(height: AppSpacing.md),
            _dateButton(
              key: const ValueKey('expires-date'),
              label: 'Date d\'expiration',
              value: draft.customExpiresAt == null
                  ? 'Choisir'
                  : ChroniqueDateHelper.formatLocal(draft.customExpiresAt!)
                      .split(' • ')
                      .first,
              onPressed: enabled ? () => _pickExpiresDate(context) : null,
            ),
            const SizedBox(height: AppSpacing.md),
            _dateButton(
              key: const ValueKey('expires-time'),
              label: 'Heure d\'expiration',
              value: draft.customExpiresAt == null
                  ? 'Choisir'
                  : ChroniqueDateHelper.formatLocal(draft.customExpiresAt!)
                      .split(' • ')
                      .last,
              onPressed: enabled ? () => _pickExpiresTime(context) : null,
            ),
          ],
        ],
      ],
    );
  }
}
