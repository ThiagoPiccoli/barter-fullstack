import 'package:flutter/material.dart';

import '../brand.dart';

/// **agroBarter** — marca padrão do produto.
///
/// Direção visual "Campo": verde-floresta institucional com um acento
/// folha/lima. O logotipo é bicolor — `agro` no acento, `Barter` no tom de
/// conteúdo — e é essa quebra que dá o nome sua leitura de duas partes.
///
/// Este arquivo é o molde de todos os outros clientes. Para criar um, copie
/// `_template.dart` (não este) e aponte `active_brand.dart` para o novo arquivo.
const Brand agroBarterBrand = Brand(
  identity: BrandIdentity(
    // O logotipo é lido como duas palavras coladas: o prefixo em minúscula
    // pesa menos e o sufixo capitalizado carrega o nome do produto.
    wordmarkPrefix: 'agro',
    wordmarkSuffix: 'Barter',
    monogram: 'aB',
    tagline: 'Permuta de grãos por insumos',
    appTitle: 'agroBarter — Permuta de Grãos',
    legalName: 'agroBarter',
    // Precisa bater com os e-mails semeados pela API (`api/prisma/seed-data.ts`),
    // senão os atalhos de login da tela de entrada apontam para contas que não
    // existem.
    emailDomain: 'agrobarter.com.br',
  ),

  palette: BrandPalette(
    // --- Institucional ---------------------------------------------------
    primary: Color(0xFF14532D), // verde-floresta profundo
    primaryMedium: Color(0xFF166D3B), // fecha o gradiente do cabeçalho
    primaryLight: Color(0xFF1E7A42), // ícones e realces sobre fundo claro
    primaryAccent: Color(0xFF84CC16), // folha/lima — o "agro" do logotipo
    primarySurface: Color(0xFFECFDF3), // chip e cartão selecionado
    // O acento vivo não tem contraste sobre branco; sobre superfície clara o
    // logotipo troca para este tom sem perder a leitura de duas cores.
    accentOnLight: Color(0xFF4D7C0F),

    // --- Superfícies e conteúdo ------------------------------------------
    background: Color(0xFFF6F7F5), // off-white levemente esverdeado
    surface: Color(0xFFFFFFFF),
    textDark: Color(0xFF1A1D1A),
    textMedium: Color(0xFF5A625A),
    textLight: Color(0xFF9AA39A),

    // --- Conteúdo sobre a cor institucional ------------------------------
    onPrimary: Color(0xFFFFFFFF),
    onPrimaryMuted: Color(0xCCFFFFFF),
    onPrimarySubtle: Color(0xAAFFFFFF),
    onPrimaryFaint: Color(0x55FFFFFF),
    onPrimaryOverlay: Color(0x1FFFFFFF),

    // --- Estados da permuta ----------------------------------------------
    // Índigo para "na mesa do gerente": ele precisa se distinguir do âmbar de
    // "aguardando revisão" à primeira vista, porque as duas etapas são de pessoas
    // diferentes — e é justamente na lista misturada que a diferença importa.
    // Um segundo tom de âmbar teria mantido as duas indistinguíveis.
    atManager: Color(0xFF4338CA),
    atManagerBg: Color(0xFFEEF0FF),
    approved: Color(0xFF15803D),
    // Âmbar mais claro que `grain` de propósito: os dois aparecem lado a lado
    // no painel, e com o mesmo tom um selo de revisão se confundia com um
    // marcador de grão.
    pending: Color(0xFFD97706),
    denied: Color(0xFFB91C1C),
    approvedBg: Color(0xFFECFDF3),
    pendingBg: Color(0xFFFFF7ED),
    deniedBg: Color(0xFFFEECEC),

    // --- Traços e estados neutros ----------------------------------------
    divider: Color(0xFFD8DDD8),
    borderSubtle: Color(0xFFE4E8E4),
    cardShadow: Color(0x14000000),
    disabledBg: Color(0xFFEEF0EE),
    disabledFg: Color(0xFFA8B0A8),

    // --- Os dois lados do negócio ----------------------------------------
    // Insumo retirado define o custo; grão de pagamento cobre esse custo.
    // Precisam ser distinguíveis entre si e da institucional.
    grain: Color(0xFFB45309), // âmbar/terra
    grainBg: Color(0xFFFEF3E2),
    input: Color(0xFF0F766E), // verde-azulado
    inputBg: Color(0xFFE6F4F3),
    balance: Color(0xFF14532D),

    // --- Séries de gráfico (sacas por grão) -------------------------------
    // Abre no tom de `grain` — o primeiro grão do painel herda a cor do
    // conceito — e depois abre o leque para tons distinguíveis entre si.
    dataSeries: [
      Color(0xFFB45309), // soja
      Color(0xFFEAB308), // milho
      Color(0xFF92400E), // trigo
      Color(0xFF6D4C41), // aveia
      Color(0xFF475569), // demais
      Color(0xFF4D7C0F), // folga
    ],
  ),

  copy: BrandCopy(
    program: 'barter',
    programTitle: 'Barter',
    season: 'safra',
    seasonTitle: 'Safra',
    barter: 'permuta',
    barterTitle: 'Permuta',
    barterPlural: 'permutas',
    barterPluralTitle: 'Permutas',
    grain: 'grão',
    grainTitle: 'Grão',
    grainPlural: 'grãos',
    grainPluralTitle: 'Grãos',
    input: 'insumo',
    inputTitle: 'Insumo',
    inputPlural: 'insumos',
    inputPluralTitle: 'Insumos',
    producer: 'produtor',
    producerTitle: 'Produtor',
    producerPlural: 'produtores',
    producerPluralTitle: 'Produtores',
    consultant: 'consultor',
    consultantTitle: 'Consultor',
    consultantPlural: 'consultores',
    consultantPluralTitle: 'Consultores',
    consultantShort: 'Cons.',
    sack: 'saca',
    sackPlural: 'sacas',
    organization: 'cooperativa',
  ),

  shape: BrandShape(
    card: 14,
    button: 12,
    field: 12,
    chip: 20,
    logoTile: 10,
  ),
);
