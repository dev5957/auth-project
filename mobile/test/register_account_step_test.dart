import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/auth/presentation/screens/register_screen.dart';
import 'package:mobile/features/auth/presentation/state/register_flow_controller.dart';
import 'package:mobile/features/auth/presentation/state/register_form_data.dart';
import 'package:mobile/features/auth/presentation/widgets/register_account_step.dart';

class _SeededAccountFlow extends RegisterFlowController {
  @override
  RegisterFlowState build() {
    return RegisterFlowState(
      step: RegisterStep.account,
      data: RegisterFormData(
        firstName: 'Ada',
        lastName: 'Lovelace',
        birthDate: DateTime(2000, 1, 15),
        login: 'ada',
        email: 'ada@example.com',
        confirmEmail: 'ada@example.com',
        password: 'password1',
        confirmPassword: 'password1',
      ),
    );
  }
}

void main() {
  test('account data survives back to Personal then forward again', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final flow = container.read(registerFlowProvider.notifier);
    final birthDate = DateTime(2000, 1, 15);

    flow.savePersonal(
      firstName: 'Ada',
      lastName: 'Lovelace',
      birthDate: birthDate,
    );
    flow.goToNextStep();
    flow.saveAccount(
      login: 'ada',
      email: 'ada@example.com',
      confirmEmail: 'ada@example.com',
      password: 'password1',
      confirmPassword: 'password1',
    );

    flow.goToPreviousStep();
    final afterBack = container.read(registerFlowProvider);
    expect(afterBack.step, RegisterStep.personal);
    expect(afterBack.data.firstName, 'Ada');
    expect(afterBack.data.lastName, 'Lovelace');
    expect(afterBack.data.birthDate, birthDate);
    expect(afterBack.data.login, 'ada');
    expect(afterBack.data.email, 'ada@example.com');
    expect(afterBack.data.confirmEmail, 'ada@example.com');
    expect(afterBack.data.password, 'password1');
    expect(afterBack.data.confirmPassword, 'password1');

    flow.goToNextStep();
    final afterForward = container.read(registerFlowProvider);
    expect(afterForward.step, RegisterStep.account);
    expect(afterForward.data.firstName, 'Ada');
    expect(afterForward.data.login, 'ada');
    expect(afterForward.data.password, 'password1');
  });

  testWidgets('Account step restores saved fields and keeps Continue enabled', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          registerFlowProvider.overrideWith(_SeededAccountFlow.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: RegisterAccountStep(onContinue: _noop),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Step 2 of 4 · Account'), findsOneWidget);
    expect(find.text('ada'), findsOneWidget);
    expect(find.text('ada@example.com'), findsNWidgets(2));

    final continueInkWell = tester.widget<InkWell>(
      find.ancestor(
        of: find.text('Continue'),
        matching: find.byType(InkWell),
      ),
    );
    expect(continueInkWell.onTap, isNotNull);
  });

  testWidgets('Continue stays disabled and shows local errors until Account is valid', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: RegisterAccountStep(onContinue: _noop),
            ),
          ),
        ),
      ),
    );

    InkWell continueButton() {
      return tester.widget<InkWell>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(InkWell),
        ),
      );
    }

    expect(continueButton().onTap, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Choose a login'), 'ada');
    await tester.enterText(find.widgetWithText(TextField, 'you@example.com'), 'not-an-email');
    await tester.enterText(find.widgetWithText(TextField, 'Re-enter your email'), 'other@example.com');
    await tester.enterText(find.widgetWithText(TextField, '8–72 characters'), 'short');
    await tester.enterText(find.widgetWithText(TextField, 'Re-enter your password'), 'different');
    await tester.pump();

    expect(find.text('email is invalid'), findsOneWidget);
    expect(find.text('Emails do not match'), findsOneWidget);
    expect(find.text('Password must be between 8 and 72 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(continueButton().onTap, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'you@example.com'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Re-enter your email'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextField, '8–72 characters'), 'password1');
    await tester.enterText(find.widgetWithText(TextField, 'Re-enter your password'), 'password1');
    await tester.pump();

    expect(find.text('email is invalid'), findsNothing);
    expect(find.text('Emails do not match'), findsNothing);
    expect(find.text('Passwords do not match'), findsNothing);
    expect(continueButton().onTap, isNotNull);
  });

  testWidgets('Personal Continue opens Account; back keeps Personal data', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RegisterScreen(),
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, 'First name'), 'Ada');
    await tester.tap(find.byTooltip('Choose date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4 · Account'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Choose a login'), 'ada');
    await tester.enterText(find.widgetWithText(TextField, 'you@example.com'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Re-enter your email'), 'ada@example.com');
    await tester.enterText(find.widgetWithText(TextField, '8–72 characters'), 'password1');
    await tester.enterText(find.widgetWithText(TextField, 'Re-enter your password'), 'password1');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 4 · Personal'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4 · Account'), findsOneWidget);
    expect(find.text('ada'), findsOneWidget);
    expect(find.text('ada@example.com'), findsNWidgets(2));
  });
}

void _noop() {}
