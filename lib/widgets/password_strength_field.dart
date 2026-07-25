import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/password_policy.dart';
import 'auth_scaffold.dart';

/// Password field with a live strength meter and a requirement checklist.
///
/// Presentation only: it asks [PasswordPolicy] what the password satisfies and
/// draws the answer. Used by both sign-up and change-password so the two always
/// show identical rules.
class PasswordStrengthField extends StatefulWidget {
  const PasswordStrengthField({
    super.key,
    required this.controller,
    required this.enabled,
    this.label = 'Password',
    this.email,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;

  /// Checked against the password so it cannot simply restate the address.
  final String? email;

  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  State<PasswordStrengthField> createState() => _PasswordStrengthFieldState();
}

class _PasswordStrengthFieldState extends State<PasswordStrengthField> {
  bool _obscured = true;

  /// Checklist and meter stay hidden until there is something to assess, so an
  /// untouched form is not a wall of red.
  bool get _hasInput => widget.controller.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final assessment = PasswordPolicy.assess(
      widget.controller.text,
      email: widget.email,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthTextField(
          controller: widget.controller,
          label: widget.label,
          hintText: 'At least ${PasswordPolicy.minLength} characters',
          obscureText: _obscured,
          textInputAction: widget.textInputAction,
          autofillHints: const [AutofillHints.newPassword],
          prefixIcon: Icons.lock_outline_rounded,
          enabled: widget.enabled,
          onFieldSubmitted: widget.onFieldSubmitted,
          validator: (value) =>
              PasswordPolicy.validate(value, email: widget.email),
          suffixIcon: PasswordVisibilityToggle(
            isObscured: _obscured,
            onToggle: () => setState(() => _obscured = !_obscured),
          ),
        ),

        if (_hasInput) ...[
          const SizedBox(height: AppSpacing.m),
          _StrengthMeter(strength: assessment.strength),
          const SizedBox(height: AppSpacing.m),
          _RequirementChecklist(assessment: assessment),
        ],
      ],
    );
  }
}

/// Four segments that fill and warm up as the password improves.
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final PasswordStrength strength;

  static const _segments = 4;

  Color get _color => switch (strength) {
    PasswordStrength.empty => AppColors.divider,
    PasswordStrength.weak => AppColors.error,
    PasswordStrength.fair => AppColors.warning,
    PasswordStrength.good => AppColors.accent,
    PasswordStrength.strong => AppColors.success,
  };

  @override
  Widget build(BuildContext context) {
    final filled = (strength.fraction * _segments).round();

    return Row(
      children: [
        for (var i = 0; i < _segments; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 4,
              decoration: BoxDecoration(
                color: i < filled ? _color : AppColors.divider,
                borderRadius: BorderRadius.circular(AppRadius.s),
              ),
            ),
          ),
        ],
        const SizedBox(width: AppSpacing.s),
        // Fixed width so the meter does not resize as the label changes.
        SizedBox(
          width: 48,
          child: Text(
            strength.label,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Every rule, ticked as it is met — showing the whole list is friendlier than
/// revealing one failure at a time.
class _RequirementChecklist extends StatelessWidget {
  const _RequirementChecklist({required this.assessment});

  final PasswordAssessment assessment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rule in PasswordRule.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _RequirementRow(
              label: rule.label,
              met: assessment.passes(rule),
            ),
          ),
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.label, required this.met});

  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final color = met ? AppColors.success : AppColors.textHint;

    return Row(
      children: [
        Icon(
          met ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 15,
          color: color,
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: met ? AppColors.textSecondary : AppColors.textHint,
              height: 1.4,
            ),
            // Announced as a checklist item so screen readers convey state.
            semanticsLabel: '$label: ${met ? 'met' : 'not met'}',
          ),
        ),
      ],
    );
  }
}
