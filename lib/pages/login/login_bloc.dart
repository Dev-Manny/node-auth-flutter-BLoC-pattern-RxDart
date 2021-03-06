import 'dart:async';

import 'package:disposebag/disposebag.dart';
import 'package:meta/meta.dart';
import 'package:node_auth/data/data.dart';
import 'package:node_auth/pages/login/login.dart';
import 'package:node_auth/utils/validators.dart';
import 'package:rxdart/rxdart.dart';

// ignore_for_file: close_sinks

/// BLoC handle validate form and login
class LoginBloc {
  /// Input functions
  final void Function(String) emailChanged;
  final void Function(String) passwordChanged;
  final void Function() submitLogin;

  /// Streams
  final Stream<String> emailError$;
  final Stream<String> passwordError$;
  final Stream<LoginMessage> message$;
  final Stream<bool> isLoading$;

  /// Clean up
  final void Function() dispose;

  LoginBloc._({
    @required this.emailChanged,
    @required this.passwordChanged,
    @required this.submitLogin,
    @required this.emailError$,
    @required this.passwordError$,
    @required this.message$,
    @required this.dispose,
    @required this.isLoading$,
  });

  factory LoginBloc(UserRepository userRepository) {
    assert(userRepository != null);

    /// Controllers
    final emailController = PublishSubject<String>();
    final passwordController = PublishSubject<String>();
    final submitLoginController = PublishSubject<void>();
    final isLoadingController = BehaviorSubject<bool>.seeded(false);
    final controllers = [
      emailController,
      passwordController,
      submitLoginController,
      isLoadingController,
    ];

    ///
    /// Streams
    ///

    final isValidSubmit$ = Rx.combineLatest3(
      emailController.stream.map(Validator.isValidEmail),
      passwordController.stream.map(Validator.isValidPassword),
      isLoadingController.stream,
      (isValidEmail, isValidPassword, isLoading) =>
          isValidEmail && isValidPassword && !isLoading,
    ).shareValueSeeded(false);

    final credential$ = Rx.combineLatest2(
      emailController.stream,
      passwordController.stream,
      (email, password) => Credential(email: email, password: password),
    );

    final submit$ = submitLoginController.stream
        .withLatestFrom(isValidSubmit$, (_, bool isValid) => isValid)
        .share();

    final message$ = Rx.merge([
      submit$
          .where((isValid) => isValid)
          .withLatestFrom(credential$, (_, Credential c) => c)
          .exhaustMap(
            (credential) => userRepository
                .login(
                  email: credential.email,
                  password: credential.password,
                )
                .doOnListen(() => isLoadingController.add(true))
                .doOnData((_) => isLoadingController.add(false))
                .map(_responseToMessage),
          ),
      submit$
          .where((isValid) => !isValid)
          .map((_) => const InvalidInformationMessage())
    ]).share();

    final emailError$ = emailController.stream
        .map((email) {
          if (Validator.isValidEmail(email)) return null;
          return 'Invalid email address';
        })
        .distinct()
        .share();

    final passwordError$ = passwordController.stream
        .map((password) {
          if (Validator.isValidPassword(password)) return null;
          return 'Password must be at least 6 characters';
        })
        .distinct()
        .share();

    final streams = <String, Stream>{
      'emailError': emailError$,
      'passwordError': passwordError$,
      'isValidSubmit': isValidSubmit$,
      'message': message$,
      'isLoading': isLoadingController,
    };
    final subscriptions = streams.keys.map((tag) {
      return streams[tag].listen((data) {
        print('[DEBUG] [$tag] = $data');
      });
    }).toList();

    return LoginBloc._(
      emailChanged: emailController.add,
      passwordChanged: passwordController.add,
      submitLogin: () => submitLoginController.add(null),
      emailError$: emailError$,
      passwordError$: passwordError$,
      message$: message$,
      dispose: DisposeBag([...controllers, subscriptions]).dispose,
      isLoading$: isLoadingController,
    );
  }

  static LoginMessage _responseToMessage(Result result) {
    if (result is Success) {
      return const LoginSuccessMessage();
    }
    if (result is Failure) {
      return LoginErrorMessage(result.message, result.error);
    }
    return LoginErrorMessage("Unknown result $result");
  }
}
