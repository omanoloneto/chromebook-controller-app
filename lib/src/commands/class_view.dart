// Visão da turma (set_class_view) — snapshot que o app agrega e re-cifra
// SÓ para o PC do professor (telão). Ver docs/protocolo.md.
// Builder puro (sem Firebase/UI) — testável; paridade por fixture com o JS
// (test/class_view_test.dart <-> tests/classview.test.mjs na extensão).

import 'dart:convert';

import 'command.dart';

const int kMaxClassViewPcs = 60;
const int kMaxClassViewNome = 40;
const int kMaxClassViewAluno = 60;
const int kMaxClassViewTurma = 60;
const int kMaxClassViewTitulo = 120;
const int kMaxClassViewDominio = 100;

String _cortar(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// Extrai o domínio de uma URL (a URL completa nunca viaja no snapshot).
String? dominioDaUrl(String? url) {
  if (url == null) return null;
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Um PC como aparece no snapshot do telão (dados simples, sem sessão viva).
class ClassViewPc {
  const ClassViewPc({
    required this.nome,
    required this.online,
    this.aluno,
    this.abaTitulo,
    this.abaDominio,
    this.alerta,
  });

  final String nome;
  final bool online;
  final String? aluno;
  final String? abaTitulo;
  final String? abaDominio; // sem domínio => sem bloco `aba` no payload
  final String? alerta;
}

/// Monta o comando `set_class_view`. Trunca nos caps do protocolo e ordena
/// determinístico (online primeiro, depois nome) — a página só renderiza.
Map<String, dynamic> buildSetClassView({
  required int rev,
  required bool aulaAtiva,
  String? turma,
  required List<ClassViewPc> pcs,
}) {
  final ordenados = [...pcs]..sort((a, b) {
      if (a.online != b.online) return a.online ? -1 : 1;
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });
  return {
    'v': kProtocolVersion,
    'type': MessageType.setClassView,
    'id': nextCommandId(),
    'payload': {
      'rev': rev,
      'aula': {
        'ativa': aulaAtiva,
        if (aulaAtiva && turma != null)
          'turma': _cortar(turma, kMaxClassViewTurma),
      },
      'pcs': ordenados.take(kMaxClassViewPcs).map((p) {
        return {
          'nome': _cortar(p.nome, kMaxClassViewNome),
          'online': p.online,
          if (p.aluno != null) 'aluno': _cortar(p.aluno!, kMaxClassViewAluno),
          if (p.abaDominio != null)
            'aba': {
              'titulo': _cortar(p.abaTitulo ?? '', kMaxClassViewTitulo),
              'dominio': _cortar(p.abaDominio!, kMaxClassViewDominio),
            },
          if (p.alerta != null)
            'alerta': _cortar(p.alerta!, kMaxClassViewDominio),
        };
      }).toList(),
    },
  };
}

/// Fingerprint do snapshot SEM o `rev`: dois snapshots iguais não geram
/// segundo write no RTDB (o heartbeat usa force para furar o dedupe).
String classViewFingerprint(Map<String, dynamic> cmd) {
  final payload = Map<String, dynamic>.from(cmd['payload'] as Map);
  payload.remove('rev');
  return jsonEncode(payload);
}
