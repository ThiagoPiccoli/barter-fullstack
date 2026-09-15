import 'package:flutter/material.dart';

import '../branding/brand_wordmark.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// As larguras em que o app MUDA DE FORMA.
///
/// Os cortes são de LARGURA DISPONÍVEL, nunca de "é celular ou é computador":
/// o app roda em janela redimensionável no navegador e no desktop, e meia tela
/// de um monitor de 27" é mais estreita do que um tablet deitado. Perguntar
/// pelo aparelho acerta o caso comum e erra todos os outros.
///
/// Pelo mesmo motivo não se decide nada por `MediaQuery.orientationOf`: a
/// orientação do aparelho não diz quanto espaço a janela recebeu.
class Breakpoints {
  Breakpoints._();

  /// Abaixo daqui a navegação é a barra de baixo — onde o polegar alcança.
  static const double medium = 840;

  /// Daqui para cima a navegação lateral cabe ABERTA, com os rótulos à vista.
  static const double expanded = 1200;

  /// A largura da própria coluna, fechada e aberta.
  ///
  /// Declaradas aqui porque o cabeçalho e o pé da coluna precisam delas: o
  /// `leading` e o `trailing` da [NavigationRail] recebem largura NÃO LIMITADA,
  /// e um `Expanded` dentro de uma `Row` sem teto é erro de layout, não um
  /// detalhe estético. Quem desenha ali dentro tem de dizer em quanto espaço
  /// está desenhando.
  static const double railWidth = 72;
  static const double railExtendedWidth = 256;

  /// O quanto o conteúdo de um painel se deixa esticar.
  ///
  /// Sem este teto, um cartão de resumo ocupa 2000px num monitor grande e a
  /// leitura vira um varrer de olhos de ponta a ponta. O excedente vira margem,
  /// e não linha mais longa.
  static const double contentMaxWidth = 1200;
}

/// Um destino da navegação, na forma que serve às DUAS cascas.
///
/// A barra de baixo e a lateral pedem widgets diferentes
/// ([BottomNavigationBarItem] e [NavigationRailDestination]), e é
/// [AdaptiveNavScaffold] quem traduz. Quem monta a tela descreve o destino uma
/// vez só — do contrário, acrescentar uma aba seria lembrar de mexer em dois
/// lugares, e um deles ficaria para trás.
class AdaptiveDestination {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Quanto trabalho espera AÇÃO de quem está olhando, neste destino.
  ///
  /// Zero não desenha selo nenhum: um selo zerado é ruído que treina o olho a
  /// ignorar o selo, que é o oposto do que ele existe para fazer.
  final int badgeCount;

  /// A cor da ETAPA do selo — o mesmo índigo/âmbar/verde-azulado que a permuta
  /// tem na lista. Um selo de cor fixa faria a fila do faturista parecer a do
  /// gerente.
  final Color? badgeColor;

  const AdaptiveDestination({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount = 0,
    this.badgeColor,
  });

  Widget _icon(bool selected) {
    final child = Icon(selected ? activeIcon : icon);
    if (badgeCount == 0) return child;
    return Badge(
      label: Text('$badgeCount'),
      backgroundColor: badgeColor ?? AppColors.atManager,
      textColor: AppColors.onPrimary,
      child: child,
    );
  }
}

/// A casca de navegação dos painéis de papel — a mesma tela em três formas.
///
/// Estreito, a navegação é a barra de baixo. A partir de [Breakpoints.medium]
/// ela vira uma coluna lateral de ícones, e a partir de [Breakpoints.expanded]
/// essa coluna abre com os rótulos. O corpo é o mesmo widget nos três casos —
/// o que muda é onde ficam os botões, não o que a tela mostra.
///
/// Existe porque os três painéis (admin, retaguarda, consultor) tinham a mesma
/// [BottomNavigationBar] copiada, e barra de baixo em monitor de 27" é celular
/// esticado: a navegação vai morar no rodapé, longe dos olhos e do cursor.
class AdaptiveNavScaffold extends StatelessWidget {
  final List<AdaptiveDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// O corpo já vem com [Scaffold] e [AppBar] próprios (cada aba é uma tela
  /// inteira). Aninhar Scaffold é de propósito: é o que deixa a barra de título
  /// da aba conviver com a navegação lateral, à direita dela.
  final Widget body;

  /// Quem está usando o app — o rodapé da coluna lateral.
  ///
  /// Só a coluna o mostra. No estreito, a identidade continua onde sempre
  /// esteve: na barra de título, que é o canto onde se procura por ela quando
  /// não há coluna nenhuma.
  final UserModel? user;

  const AdaptiveNavScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.body,
    this.user,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Breakpoints.medium) {
          return Scaffold(
            body: RailScope(hasRail: false, child: body),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: selectedIndex,
              onTap: onSelect,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.textLight,
              selectedLabelStyle:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              items: [
                for (final d in destinations)
                  BottomNavigationBarItem(
                    icon: d._icon(false),
                    activeIcon: d._icon(true),
                    label: d.label,
                  ),
              ],
            ),
          );
        }

        final extended = constraints.maxWidth >= Breakpoints.expanded;
        return Scaffold(
          body: Row(
            children: [
              // O PÉ FICA FORA DA [NavigationRail], e não no `trailing` dela.
              //
              // O `trailing` parece o lugar certo e não é: ele entra no MESMO
              // grupo dos destinos, que a rail alinha ao topo — o rodapé
              // colava embaixo do último item, no meio da coluna, em vez de
              // ancorar no fim dela. Empilhar a rail e o pé numa `Column`,
              // com a rail em `Expanded`, põe cada um onde ele pertence.
              //
              // A cor de fundo sai da rail e vem para cá: com o pé fora dela,
              // é esta caixa que precisa pintar a coluna inteira, senão o
              // trecho de baixo aparece sobre o fundo da tela.
              SizedBox(
                width: extended
                    ? Breakpoints.railExtendedWidth
                    : Breakpoints.railWidth,
                child: ColoredBox(
                  color: AppColors.surface,
                  child: Column(
                    children: [
                      Expanded(
                        child: NavigationRail(
                          selectedIndex: selectedIndex,
                          onDestinationSelected: onSelect,
                          extended: extended,
                          // Aberta, a rail já mostra o rótulo ao lado do ícone;
                          // repetir o rótulo embaixo é proibido pelo próprio widget.
                          labelType: extended
                              ? NavigationRailLabelType.none
                              : NavigationRailLabelType.all,
                          backgroundColor: Colors.transparent,
                          indicatorColor: AppColors.primarySurface,
                          minWidth: Breakpoints.railWidth,
                          minExtendedWidth: Breakpoints.railExtendedWidth,
                          // A MARCA no topo. A coluna é a moldura fixa do app no
                          // computador, e uma moldura sem assinatura é onde o
                          // espaço vazio começa a incomodar.
                          leading: _RailHeader(extended: extended),
                          selectedIconTheme: IconThemeData(color: AppColors.primary),
                          unselectedIconTheme:
                              IconThemeData(color: AppColors.textLight),
                          // Os destinos são o primeiro nível: peso maior que o do
                          // rodapé, para o olho ter onde pousar.
                          //
                          // O CORPO depende do estado, e não é preciosismo:
                          // fechada, o rótulo fica SOB o ícone numa coluna de
                          // 72px, e 14 quebrava "Permutas" em duas linhas. Aberta,
                          // ele fica ao lado, com a largura toda — e aí 14 é o que
                          // separa um destino de um item de rodapé.
                          selectedLabelTextStyle: TextStyle(
                            fontSize: extended ? 14 : 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                          unselectedLabelTextStyle: TextStyle(
                            fontSize: extended ? 14 : 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMedium,
                          ),
                          destinations: [
                            for (final d in destinations)
                              NavigationRailDestination(
                                icon: d._icon(false),
                                selectedIcon: d._icon(true),
                                label: Text(d.label),
                              ),
                          ],
                        ),
                      ),
                      // A IDENTIDADE e as ações quietas, ancoradas no fim —
                      // separadas por divisória, menores e mais apagadas que os
                      // destinos. É a hierarquia de três níveis: o que se visita
                      // todo dia em cima e forte; conta e saída embaixo e discretas.
                      if (user != null)
                        _RailFooter(user: user!, extended: extended),
                    ],
                  ),
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: AppColors.divider),
              // A coluna se ANUNCIA ao corpo: é assim que os botões de conta e
              // saída da barra de título sabem que já estão representados aqui.
              Expanded(child: RailScope(hasRail: true, child: body)),
            ],
          ),
        );
      },
    );
  }
}

/// Uma faixa da coluna lateral, com a LARGURA da coluna dentro.
///
/// O `leading` e o `trailing` da [NavigationRail] são medidos sem teto de
/// largura — quem desenha ali recebe `BoxConstraints(unconstrained)`. Sob isso,
/// um `Expanded` numa `Row` é exceção de layout, e um texto longo não tem contra
/// o que reticenciar. Esta faixa devolve o teto que a coluna tem de verdade,
/// para o cabeçalho e o pé desenharem em cima de um número real.
class _RailBand extends StatelessWidget {
  final bool extended;
  final EdgeInsets padding;
  final Widget child;

  const _RailBand({
    required this.extended,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: extended ? Breakpoints.railExtendedWidth : Breakpoints.railWidth,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A MARCA no topo da coluna lateral.
///
/// Aberta, o logotipo inteiro; fechada, só o monograma — o mesmo desenho nas
/// duas larguras, e não dois logotipos diferentes. O tom é o de fundo claro,
/// porque a coluna é branca: o da barra de título não serviria aqui.
class _RailHeader extends StatelessWidget {
  final bool extended;
  const _RailHeader({required this.extended});

  @override
  Widget build(BuildContext context) {
    return _RailBand(
      extended: extended,
      padding: EdgeInsets.fromLTRB(extended ? 20 : 0, 8, extended ? 20 : 0, 8),
      child: BrandWordmark(
        size: 30,
        showLettering: extended,
        showTagline: false,
        tone: BrandTone.onSurface,
      ),
    );
  }
}

/// O PÉ da coluna: quem está logado, e as duas ações que não são navegação.
///
/// Ele fecha a moldura pelo lado de baixo — o canto onde se procura a própria
/// conta num app de painel. E resolve o vazio de outro jeito que não enchendo
/// linguiça: o que está ali é o que a barra de título carregava, agora no lugar
/// onde ele tem endereço fixo.
///
/// Aberto, mostra nome e cargo; fechado, só o avatar e os dois ícones. A saída
/// é a única coisa da coluna em cor de alerta, e mesmo assim discreta: ela não
/// disputa com os destinos, mas também não pode ser clicada por engano achando
/// que é outra coisa.
class _RailFooter extends StatelessWidget {
  final UserModel user;
  final bool extended;
  const _RailFooter({required this.user, required this.extended});

  @override
  Widget build(BuildContext context) {
    return _RailBand(
      extended: extended,
      padding: EdgeInsets.fromLTRB(extended ? 12 : 0, 8, extended ? 12 : 0, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, thickness: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          if (extended)
            Row(
              children: [
                _Avatar(user: user),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      Text(
                        user.role.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: AppColors.textLight),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            _Avatar(user: user),
          const SizedBox(height: 4),
          // Fechada, os dois ícones empilham; aberta, ficam lado a lado com o
          // rótulo. Um `Wrap` resolve as duas sem um `if` a mais.
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              _RailAction(
                icon: Icons.lock_reset,
                label: 'Alterar senha',
                extended: extended,
                onTap: () => openChangePassword(context),
              ),
              _RailAction(
                icon: Icons.logout,
                label: 'Sair',
                extended: extended,
                color: AppColors.denied,
                onTap: () => confirmLogout(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final UserModel user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: AppColors.primaryAccent,
      radius: 16,
      child: Text(
        user.avatarInitials,
        style: TextStyle(
          color: AppColors.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Uma ação do pé da coluna: ícone só na fechada, ícone e rótulo na aberta.
///
/// Corpo 12 e cor apagada de propósito — é o terceiro nível da hierarquia, e
/// pesá-lo como um destino faria "Sair" competir com "Permutas".
class _RailAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool extended;
  final Color? color;
  final VoidCallback onTap;

  const _RailAction({
    required this.icon,
    required this.label,
    required this.extended,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.textLight;
    if (!extended) {
      return IconButton(
        icon: Icon(icon, size: 20),
        color: tint,
        tooltip: label,
        onPressed: onTap,
      );
    }
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: tint,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// O corpo de um painel, com teto de largura.
///
/// Num monitor grande o painel não deve crescer junto: linha longa demais cansa,
/// e três cartões espalhados por 2000px pedem um giro de cabeça para serem lidos
/// juntos. O que sobra vira margem.
///
/// Fica DENTRO do `RefreshIndicator` e FORA do `ListView` de propósito — o
/// indicador precisa do scroll como descendente, e o scroll precisa nascer já
/// limitado.
class BoundedContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const BoundedContent({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.contentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Cartões de resumo que reflowam: duas colunas no estreito, quatro no largo.
///
/// Os cortes são explícitos em vez de `SliverGridDelegateWithMaxCrossAxisExtent`
/// porque os painéis têm conjuntos pequenos e fechados (quatro cartões, três
/// cartões), e a largura máxima por coluna deixaria um órfão sozinho na última
/// linha justamente nas larguras intermediárias. O número de colunas nunca passa
/// da quantidade de cartões — três cartões em quatro colunas deixariam um buraco
/// à direita.
class AdaptiveCardGrid extends StatelessWidget {
  final List<Widget> children;

  /// A altura de cada cartão. Fixa porque os cartões de resumo são todos do
  /// mesmo formato (ícone, número, rótulo), e altura por conteúdo faria a linha
  /// desalinhar conforme o texto de um deles.
  final double itemHeight;
  final double spacing;

  const AdaptiveCardGrid({
    super.key,
    required this.children,
    this.itemHeight = 160,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth >= 700 ? 4 : 2)
            .clamp(1, children.length);
        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: itemHeight,
          ),
          children: children,
        );
      },
    );
  }
}

/// Em qual coluna um bloco de tela de detalhe cai, quando há espaço para duas.
enum DetailColumn {
  /// O que a coisa É — o corpo que se lê de cima a baixo.
  main,

  /// Quem, quando, em que estado, e o que fazer a respeito.
  side,
}

/// Um bloco de uma tela de detalhe, e a coluna a que ele pertence no monitor.
///
/// A coluna é declarada no bloco, e não montando duas listas, porque a ordem do
/// CELULAR é a lista única na sequência em que os blocos foram escritos — e é
/// essa ordem que carrega a prioridade pensada pela tela (a ressalva antes dos
/// pareceres, os pareceres antes dos itens). Duas listas separadas obrigariam a
/// escolher entre preservar essa ordem e ter as duas colunas.
class DetailBlock {
  final Widget child;
  final DetailColumn column;

  /// O corpo: itens, totais, o andamento. Ocupa a coluna larga.
  const DetailBlock.main(this.child) : column = DetailColumn.main;

  /// A margem: cadastro, pareceres, e os botões que agem sobre a permuta.
  const DetailBlock.side(this.child) : column = DetailColumn.side;
}

/// Uma tela de detalhe em duas colunas no monitor e uma no celular.
///
/// No estreito é exatamente a lista de hoje, na ordem de hoje: [blocks] na
/// sequência em que foi escrita. No largo, os blocos se separam pela coluna que
/// cada um declara, mantendo a ordem RELATIVA dentro de cada uma.
///
/// A divisão serve à pergunta que traz alguém a uma tela de detalhe no
/// computador: decidir. Do lado largo fica o que a permuta é; do estreito, o que
/// se sabe sobre ela e o que se pode fazer — e os dois cabem na mesma tela, em
/// vez de o botão de aprovar morar quatro rolagens abaixo dos pareceres que o
/// justificam.
class AdaptiveDetailLayout extends StatelessWidget {
  final List<DetailBlock> blocks;
  final double spacing;

  /// O corte é alto de propósito: duas colunas de cartão só valem a pena quando
  /// cada uma ainda tem largura para uma linha "nome do insumo … 107,7 sc" sem
  /// quebrar. Abaixo disso, uma coluna larga lê melhor que duas apertadas.
  final double minWidth;

  final int mainFlex;
  final int sideFlex;

  const AdaptiveDetailLayout({
    super.key,
    required this.blocks,
    this.spacing = 16,
    this.minWidth = 1000,
    this.mainFlex = 3,
    this.sideFlex = 2,
  });

  static Widget _stack(List<Widget> children, double spacing) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth) {
          return _stack(blocks.map((b) => b.child).toList(), spacing);
        }

        final main = <Widget>[];
        final side = <Widget>[];
        for (final block in blocks) {
          (block.column == DetailColumn.main ? main : side).add(block.child);
        }
        // Uma coluna vazia não vira espaço reservado: uma permuta sem nada a
        // decidir devolveria uma faixa em branco de 40% da tela.
        if (main.isEmpty) return _stack(side, spacing);
        if (side.isEmpty) return _stack(main, spacing);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: mainFlex, child: _stack(main, spacing)),
            SizedBox(width: spacing),
            Expanded(flex: sideFlex, child: _stack(side, spacing)),
          ],
        );
      },
    );
  }
}

/// Dois blocos de painel lado a lado quando há espaço, empilhados quando não há.
///
/// É o que tira o painel do admin da coluna única: "Insumos mais retirados" e
/// "Sacas a receber por grão" são leituras irmãs, e no monitor elas cabem na
/// mesma altura de tela em vez de uma rolagem abaixo da outra.
///
/// O corte é maior que o da navegação porque aqui o que compete é o CONTEÚDO:
/// dois rankings de 420px cada viram duas colunas de texto quebrado.
class AdaptiveColumns extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final double minWidth;

  const AdaptiveColumns({
    super.key,
    required this.children,
    this.spacing = 16,
    this.minWidth = 900,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                children[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: spacing),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}
