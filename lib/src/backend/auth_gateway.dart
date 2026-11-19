// Porta da conta do professor (Firebase Auth).

enum GoogleLink { linked, switched }

abstract interface class AuthGateway {
  AuthUser? get currentUser;

  Future<AuthUser> signInAnonymously();

  /// Vincula a conta Google ao usuário atual; se ela já for de outro usuário,
  /// entra nele ([GoogleLink.switched]).
  Future<GoogleLink> linkGoogle(String idToken);

  /// Sai da conta (tela de "sem vínculo": entrar com outro e-mail).
  Future<void> signOut();
}

abstract interface class AuthUser {
  String get uid;
  String? get email;
  bool get hasGoogle;
  String? get googleEmail;

  Future<void> refreshIdToken();
}
