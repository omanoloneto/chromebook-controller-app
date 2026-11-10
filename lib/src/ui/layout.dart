// Janela larga (computador, celular deitado, tablet): a navegação vai para a
// lateral e as listas ficam numa coluna central. Quem decide é a largura, e
// não a plataforma, para a mesma tela servir aos dois.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

const double kWideLayoutWidth = 840;
const double kContentMaxWidth = 880;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutWidth;

/// Margem de cada lado que centraliza uma lista. Vai no recuo da própria
/// lista, e não em volta dela: a rolagem continua valendo na janela toda.
double contentSideMargin(BuildContext context) =>
    math.max(0, (MediaQuery.sizeOf(context).width - kContentMaxWidth) / 2);
