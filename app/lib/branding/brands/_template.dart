import 'package:flutter/material.dart';

import '../brand.dart';

/// MOLDE PARA UM NOVO CLIENTE — não é usado pelo app.
///
/// Como reskinnar em cinco passos:
///
///  1. Copie este arquivo para `lib/branding/brands/<cliente>.dart`.
///  2. Renomeie `templateBrand` para `<cliente>Brand`.
///  3. Preencha os valores marcados com `TROQUE`.
///  4. Em `lib/branding/active_brand.dart`, troque o import e a constante.
///  5. Ajuste nome/ícone nativos (veja `lib/branding/README.md`).
///
/// Nenhum outro arquivo do app precisa ser tocado.
const Brand templateBrand = Brand(
  identity: BrandIdentity(
    // O logotipo é bicolor: o prefixo sai no acento, o sufixo no tom de
    // conteúdo. Escolha o ponto de quebra onde o nome tem sentido próprio
    // ("agro|Barter", "coop|Trade"). Se o nome não se divide, deixe o prefixo
    // vazio — o logotipo cai para uma cor só sem quebrar o layout.
    wordmarkPrefix: 'novo', // TROQUE
    wordmarkSuffix: 'Cliente', // TROQUE
    monogram: 'nC', // TROQUE — 1 a 3 caracteres
    tagline: 'Assinatura sob o logotipo', // TROQUE
    appTitle: 'novoCliente — Permuta de Grãos', // TROQUE
    legalName: 'novoCliente', // TROQUE
    // Precisa bater com os e-mails semeados em `api/prisma/seed-data.ts`.
    emailDomain: 'cliente.com.br', // TROQUE
  ),

  palette: BrandPalette(
    // --- Institucional ---------------------------------------------------
    // Comece por estas quatro; o resto costuma sobreviver como está.
    primary: Color(0xFF14532D), // TROQUE — domina app bar e botões
    primaryMedium: Color(0xFF166D3B), // TROQUE — fim do gradiente
    primaryLight: Color(0xFF1E7A42), // TROQUE — realces em fundo claro
    primaryAccent: Color(0xFF84CC16), // TROQUE — o prefixo do logotipo
    primarySurface: Color(0xFFECFDF3), // TROQUE — fundo tênue da primária
    // Se o acento for vivo demais para texto sobre branco, ponha aqui um tom
    // escurecido dele. Vale checar 4.5:1 de contraste antes de fechar.
    accentOnLight: Color(0xFF4D7C0F), // TROQUE

    // --- Superfícies e conteúdo ------------------------------------------
    background: Color(0xFFF6F7F5),
    surface: Color(0xFFFFFFFF),
    textDark: Color(0xFF1A1D1A),
    textMedium: Color(0xFF5A625A),
    textLight: Color(0xFF9AA39A),

    // --- Conteúdo sobre a cor institucional ------------------------------
    // Só mexa se a primária do cliente for clara: aí estes tons precisam
    // virar escuros, senão o cabeçalho fica ilegível.
    onPrimary: Color(0xFFFFFFFF),
    onPrimaryMuted: Color(0xCCFFFFFF),
    onPrimarySubtle: Color(0xAAFFFFFF),
    onPrimaryFaint: Color(0x55FFFFFF),
    onPrimaryOverlay: Color(0x1FFFFFFF),

    // --- Estados da permuta ----------------------------------------------
    // Verde/âmbar/vermelho são convenção; mude só se a marca exigir.
    approved: Color(0xFF15803D),
    pending: Color(0xFFB45309),
    denied: Color(0xFFB91C1C),
    approvedBg: Color(0xFFECFDF3),
    pendingBg: Color(0xFFFEF6E7),
    deniedBg: Color(0xFFFEECEC),

    // --- Traços e estados neutros ----------------------------------------
    divider: Color(0xFFD8DDD8),
    borderSubtle: Color(0xFFE4E8E4),
    cardShadow: Color(0x14000000),
    disabledBg: Color(0xFFEEF0EE),
    disabledFg: Color(0xFFA8B0A8),

    // --- Os dois lados do negócio ----------------------------------------
    // Mantenha grão e insumo distinguíveis entre si e da primária: o app
    // inteiro usa esse par para dizer o que custa e o que paga.
    grain: Color(0xFFB45309),
    grainBg: Color(0xFFFEF3E2),
    input: Color(0xFF0F766E),
    inputBg: Color(0xFFE6F4F3),
    balance: Color(0xFF14532D), // TROQUE junto com a primária

    // --- Séries de gráfico -------------------------------------------------
    dataSeries: [
      Color(0xFFB45309),
      Color(0xFFEAB308),
      Color(0xFFA16207),
      Color(0xFF6D4C41),
      Color(0xFF475569),
      Color(0xFF4D7C0F),
    ],
  ),

  // Vocabulário. Trocar `consultor` por `vendedor` ou `RTV` aqui renomeia o
  // papel em todas as telas de uma vez.
  copy: BrandCopy(
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

  // Personalidade do desenho: raios menores = mais institucional, maiores =
  // mais jovem. Um número aqui muda o app inteiro.
  shape: BrandShape(
    card: 14,
    button: 12,
    field: 12,
    chip: 20,
    logoTile: 10,
  ),
);
