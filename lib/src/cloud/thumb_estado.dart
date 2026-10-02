// Grade de telas ao vivo (item 23): o que um quadro da grade mostra — a
// miniatura com a idade dela, ou o texto no lugar da imagem. Puro (sem
// Flutter) — igual ao teacher/thumb_estado.py do desktop e testável em
// test/thumb_estado_test.dart. Ver SPEC-turma §5.4.

import '../commands/command.dart';

/// O que ocupa o quadro.
enum TipoQuadro {
  carregando, // esqueleto cinza + "Carregando…"
  desligado,
  versaoAntiga,
  ninguemLogado,
  naoPermitida,
  indisponivel,
  imagem,
}

/// Até esta idade a miniatura é "fresca" (imagem normal + "agora"/"há N s");
/// depois, esmaecida + "há N min".
const Duration kThumbFresca = Duration(seconds: 30);

/// Abaixo disto a idade vira "agora".
const Duration kThumbAgora = Duration(seconds: 5);

class EstadoQuadro {
  const EstadoQuadro(this.tipo, this.texto, {this.esmaecida = false});

  final TipoQuadro tipo;

  /// Sem imagem: o texto no lugar dela. Com imagem: a idade ("agora",
  /// "há 12 s", "há 2 min").
  final String texto;

  /// Imagem velha (mais de 30 s): opacidade 0,5.
  final bool esmaecida;

  bool get temImagem => tipo == TipoQuadro.imagem;

  @override
  String toString() =>
      'EstadoQuadro($tipo, $texto${esmaecida ? ', esmaecida' : ''})';
}

const EstadoQuadro _carregando =
    EstadoQuadro(TipoQuadro.carregando, 'Carregando…');

/// Estado do quadro de um PC na grade.
///
/// - [online]: presença do PC (heartbeat);
/// - [suportaTurma]: o PC entende `set_monitor` (meta/ext);
/// - [thumb]: última miniatura lida de `/thumbs/{id}` (null = nada ainda);
/// - [gradeAbertaEm]: quando a grade abriu (ms do servidor) — miniatura de
///   antes disso é de outra abertura e conta como "Carregando…";
/// - [agoraMs]: agora, no relógio do servidor (o mesmo do `ts` da miniatura).
EstadoQuadro estadoDoQuadro({
  required bool online,
  required bool suportaTurma,
  required Miniatura? thumb,
  required int? gradeAbertaEm,
  required int agoraMs,
}) {
  if (!online) return const EstadoQuadro(TipoQuadro.desligado, 'Desligado');
  if (!suportaTurma) {
    return const EstadoQuadro(
      TipoQuadro.versaoAntiga,
      'Versão antiga — atualize para ver a tela',
    );
  }
  if (thumb == null) return _carregando;
  if (gradeAbertaEm != null && thumb.ts < gradeAbertaEm) return _carregando;
  if (thumb.jpeg == null) {
    switch (thumb.motivo) {
      case 'sem_sessao':
        return const EstadoQuadro(TipoQuadro.ninguemLogado, 'Ninguém logado');
      case 'sem_permissao':
        return const EstadoQuadro(
          TipoQuadro.naoPermitida,
          'Miniatura não permitida neste Chromebook',
        );
      default: // aba_protegida, falhou ou qualquer outro marcador
        return const EstadoQuadro(
          TipoQuadro.indisponivel,
          'Tela indisponível agora',
        );
    }
  }
  final idadeMs = agoraMs - thumb.ts < 0 ? 0 : agoraMs - thumb.ts;
  if (idadeMs <= kThumbFresca.inMilliseconds) {
    if (idadeMs < kThumbAgora.inMilliseconds) {
      return const EstadoQuadro(TipoQuadro.imagem, 'agora');
    }
    return EstadoQuadro(TipoQuadro.imagem, 'há ${idadeMs ~/ 1000} s');
  }
  final minutos = (idadeMs / 60000).round();
  return EstadoQuadro(
    TipoQuadro.imagem,
    'há ${minutos < 1 ? 1 : minutos} min',
    esmaecida: true,
  );
}

/// Colunas da grade pela largura disponível (dp): < 600 → 2; < 900 → 3;
/// senão 4.
int colunasDaGrade(double largura) {
  if (largura < 600) return 2;
  if (largura < 900) return 3;
  return 4;
}
