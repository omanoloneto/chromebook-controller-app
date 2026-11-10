// Perfil do app no computador: vale só para a sessão em que o professor
// entrou, a conta fica num arquivo dele, e o que se salva vai para Downloads.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:controle_de_aula/src/backend/rest/file_session_store.dart';
import 'package:controle_de_aula/src/platform/computer_files.dart';
import 'package:controle_de_aula/src/platform/session_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('cda-profile'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('outra sessão ou outro boot apaga o perfil; a mesma mantém', () async {
    final profile = Directory('${temp.path}/profile');
    const first = {'boot': 'b1', 'session': '3'};
    expect(await SessionProfile.enforce(profile, stamp: first), isFalse);
    File('${profile.path}/teacher_key.txt').writeAsStringSync('priv:pub');
    Directory('${profile.path}/stores').createSync();
    File('${profile.path}/stores/turmas.json').writeAsStringSync('{}');

    expect(await SessionProfile.enforce(profile, stamp: first), isFalse);
    expect(File('${profile.path}/teacher_key.txt').existsSync(), isTrue);

    for (final other in const [
      {'boot': 'b1', 'session': '4'},
      {'boot': 'b2', 'session': '4'},
    ]) {
      File('${profile.path}/teacher_key.txt').writeAsStringSync('priv:pub');
      expect(await SessionProfile.enforce(profile, stamp: other), isTrue);
      expect(
        profile.listSync().map((e) => e.path.split('/').last),
        [SessionProfile.stampFile],
      );
      expect(
        jsonDecode(File('${profile.path}/${SessionProfile.stampFile}').readAsStringSync()),
        other,
      );
    }
  });

  test('carimbo ilegível conta como outra sessão', () async {
    final profile = Directory('${temp.path}/profile')..createSync();
    File('${profile.path}/${SessionProfile.stampFile}').writeAsStringSync('lixo');
    File('${profile.path}/auth.json').writeAsStringSync('{}');
    expect(
      await SessionProfile.enforce(profile, stamp: const {'boot': 'b', 'session': 's'}),
      isTrue,
    );
    expect(File('${profile.path}/auth.json').existsSync(), isFalse);
  });

  test('o carimbo junta o boot e a sessão gráfica', () {
    final boot = File('${temp.path}/boot_id')..writeAsStringSync('abc-123\n');
    expect(
      SessionProfile.currentStamp(bootIdPath: boot.path, environment: {'XDG_SESSION_ID': '7'}),
      {'boot': 'abc-123', 'session': '7'},
    );
    expect(
      SessionProfile.currentStamp(bootIdPath: '${temp.path}/nada', environment: {}),
      {'boot': '', 'session': ''},
    );
  });

  test('a sessão da conta vai e volta do arquivo', () {
    final file = File('${temp.path}/auth.json');
    final store = FileSessionStore(file);
    expect(store.load(), isNull);
    store.save({'uid': 'u1', 'refreshToken': 'r'});
    expect(FileSessionStore(file).load(), {'uid': 'u1', 'refreshToken': 'r'});
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    file.writeAsStringSync('[1]');
    expect(store.load(), isNull);
    store.save(null);
    expect(file.existsSync(), isFalse);
    store.save(null);
  });

  test('salvar no computador não sobrescreve o que já está na pasta', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final a = await saveBytesToComputer(bytes, 'Tela 1/2.jpg', base: temp);
    final b = await saveBytesToComputer(bytes, 'Tela 1/2.jpg', base: temp);
    expect(a.path, '${temp.path}/$kComputerFolder/Tela 1-2.jpg');
    expect(b.path, '${temp.path}/$kComputerFolder/Tela 1-2 (2).jpg');
    final source = File('${temp.path}/video.mp4')..writeAsBytesSync(bytes);
    final c = await copyToComputer(source.path, base: temp);
    expect(c.path, '${temp.path}/$kComputerFolder/video.mp4');
    expect(c.readAsBytesSync(), bytes);
    final d = await saveBytesToComputer(bytes, 'sem extensao', base: temp);
    final e = await saveBytesToComputer(bytes, 'sem extensao', base: temp);
    expect(d.path.endsWith('/sem extensao'), isTrue);
    expect(e.path.endsWith('/sem extensao (2)'), isTrue);
  });
}
