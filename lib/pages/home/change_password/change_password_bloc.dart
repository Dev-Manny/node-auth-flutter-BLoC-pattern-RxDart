import 'dart:async';

import 'package:meta/meta.dart';
import 'package:node_auth/data/data.dart';
import 'package:node_auth/pages/home/change_password/change_password.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tuple/tuple.dart';

bool _isValidPassword(String password) {
  return password.length >= 6;
}

class ChangePasswordBloc {
  ///
  /// Input functions
  ///
  final void Function() changePassword;
  final void Function(String) passwordChanged;
  final void Function(String) newPasswordChanged;

  ///
  /// Output stream
  ///
  final Stream<ChangePasswordState> changePasswordState$;
  final Stream<String> passwordError$;
  final Stream<String> newPasswordError$;

  ///
  /// Clean up
  ///
  final void Function() dispose;

  ChangePasswordBloc._({
    @required this.changePassword,
    @required this.changePasswordState$,
    @required this.dispose,
    @required this.passwordChanged,
    @required this.newPasswordChanged,
    @required this.passwordError$,
    @required this.newPasswordError$,
  });

  factory ChangePasswordBloc(UserRepository userRepository) {
    assert(userRepository != null);

    ///
    /// Controllers
    ///
    // ignore: close_sinks
    final passwordController = PublishSubject<String>();
    // ignore: close_sinks
    final newPasswordController = PublishSubject<String>();
    // ignore: close_sinks
    final submitChangePasswordController = PublishSubject<void>();
    final controllers = <StreamController>[
      newPasswordController,
      passwordController,
      submitChangePasswordController,
    ];

    ///
    /// Streams
    ///

    final both$ = Observable.combineLatest2(
      passwordController.stream.startWith(''),
      newPasswordController.stream.startWith(''),
      (String password, String newPassword) => Tuple2(password, newPassword),
    ).share();

    final ValueObservable<bool> isValidSubmit$ = both$.map((both) {
      final password = both.item1;
      final newPassword = both.item2;
      return _isValidPassword(newPassword) &&
          _isValidPassword(password) &&
          password != newPassword;
    }).shareValue(seedValue: false);

    final changePasswordState$ = submitChangePasswordController.stream
        .withLatestFrom(isValidSubmit$, (_, bool isValid) => isValid)
        .where((isValid) => isValid)
        .withLatestFrom(both$, (_, Tuple2<String, String> both) => both)
        .exhaustMap((both) => _performChangePassword(userRepository, both))
        .share();

    final passwordError$ = both$
        .map((tuple) {
          final password = tuple.item1;
          final newPassword = tuple.item2;

          if (!_isValidPassword(password)) {
            return 'Password must be at least 6 characters';
          }

          if (_isValidPassword(newPassword) && password == newPassword) {
            return 'New password is same old password!';
          }

          return null;
        })
        .distinct()
        .share();

    final newPasswordError$ = both$
        .map((tuple) {
          final password = tuple.item1;
          final newPassword = tuple.item2;

          if (!_isValidPassword(newPassword)) {
            return 'New password must be at least 6 characters';
          }

          if (_isValidPassword(password) && password == newPassword) {
            return 'New password is same old password!';
          }

          return null;
        })
        .distinct()
        .share();

    final streams = <String, Stream>{
      'newPasswordError': newPasswordError$,
      'passwordError': passwordError$,
      'isValidSubmit': isValidSubmit$,
      'both': both$,
      'changePasswordState': changePasswordState$,
    };
    final subscriptions = streams.keys.map((tag) {
      return streams[tag].listen((data) {
        print('[DEBUG] [$tag] = $data');
      });
    }).toList();

    return ChangePasswordBloc._(
      changePassword: () => submitChangePasswordController.add(null),
      changePasswordState$: changePasswordState$,
      dispose: () async {
        await Future.wait(subscriptions.map((s) => s.cancel()));
        await Future.wait(controllers.map((c) => c.close()));
      },
      passwordChanged: passwordController.add,
      newPasswordChanged: newPasswordController.add,
      passwordError$: passwordError$,
      newPasswordError$: newPasswordError$,
    );
  }

  static Observable<ChangePasswordState> _performChangePassword(
    UserRepository userRepository,
    Tuple2<String, String> both,
  ) {
    print('[DEBUG] change password both=$both');

    ChangePasswordState resultToState(result) {
      print('[DEBUG] change password result=$result');

      if (result is Success) {
        return ChangePasswordState((b) => b
          ..isLoading = false
          ..error = null
          ..message = 'Change password successfully!');
      }
      if (result is Failure) {
        return ChangePasswordState((b) => b
          ..isLoading = false
          ..error = result.error
          ..message = 'Error when change passwor: ${result.message}');
      }
      return null;
    }

    return userRepository
        .changePassword(password: both.item1, newPassword: both.item2)
        .map(resultToState)
        .startWith(
          ChangePasswordState((b) => b
            ..isLoading = true
            ..error = null
            ..message = null),
        );
  }
}
