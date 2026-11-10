// Endereços do projeto Firebase para os adaptadores REST (Linux).

final class RestConfig {
  const RestConfig({
    required this.apiKey,
    required this.databaseUrl,
    required this.storageBucket,
    this.databaseNamespace,
    this.identityOrigin = 'https://identitytoolkit.googleapis.com',
    this.tokenOrigin = 'https://securetoken.googleapis.com',
    this.storageOrigin = 'https://firebasestorage.googleapis.com',
  });

  // Chave Web do projeto, a mesma do agente do Celita: a do app Android pode
  // ser restrita ao pacote e não vale fora dele.
  static const RestConfig production = RestConfig(
    apiKey: 'AIzaSyBU8ee9m62I6CWEhMI_lId9gE_uSSYMZlo',
    databaseUrl: 'https://controle-de-aula-f53bd-default-rtdb.firebaseio.com',
    storageBucket: 'controle-de-aula-f53bd.firebasestorage.app',
  );

  final String apiKey;
  final String databaseUrl;
  final String storageBucket;

  /// Só o emulador precisa: lá o banco é escolhido por `?ns=`.
  final String? databaseNamespace;
  final String identityOrigin;
  final String tokenOrigin;
  final String storageOrigin;
}
