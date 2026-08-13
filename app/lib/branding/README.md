# Marca (white-label)

O app é reskinnável: **um arquivo por cliente** define cor, nome, logotipo e
vocabulário. Nenhuma tela conhece um hex ou um nome comercial.

```
lib/branding/
  brand.dart            contratos: Brand, BrandIdentity, BrandPalette, BrandCopy, BrandShape
  active_brand.dart     A CHAVE DE TROCA — aponta para o cliente ativo
  brand_wordmark.dart   logotipo bicolor (monograma + nome + assinatura)
  brands/
    agrobarter.dart     marca padrão do produto
    _template.dart      molde documentado para copiar
```

O fluxo é sempre o mesmo:

```
brands/<cliente>.dart  →  active_brand.dart  →  AppColors / AppTheme / BrandWordmark  →  telas
```

## Reskinnar para uma nova empresa

1. **Copie o molde**

   ```sh
   cp lib/branding/brands/_template.dart lib/branding/brands/cooperativa_x.dart
   ```

2. **Preencha os campos marcados com `TROQUE`** e renomeie a constante
   `templateBrand` para `cooperativaXBrand`.

3. **Aponte a chave de troca** em `lib/branding/active_brand.dart`:

   ```dart
   import 'brands/cooperativa_x.dart';
   const Brand brand = cooperativaXBrand;
   ```

4. **Rode.** Cores, logotipo, assinatura, títulos e o PDF do comprovante já
   saem com a marca nova.

5. **Ajuste o que vive fora do Dart** (nome e ícone que o sistema operacional
   mostra) — veja a tabela no fim.

## Conferir a marca nova

```sh
flutter test tool/brand_preview.dart --update-goldens
```

Regenera `docs/brand/{wordmark,palette,components}.png` renderizando os widgets
de verdade: o logotipo nos dois fundos, a paleta inteira com os hexes e uma
folha de componentes no tema. É a forma mais rápida de ver o reskin antes de
subir o app — e de flagrar colisão de cor (foi assim que `pending` e `grain`
apareceram idênticos).

O gerador fica fora de `test/` de propósito: renderização de fonte varia entre
máquinas, e na suíte padrão ele viraria um teste instável.

## O que cada parte controla

| Campo | Onde aparece |
|---|---|
| `identity.wordmarkPrefix` / `wordmarkSuffix` | Logotipo bicolor, cabeçalho do PDF |
| `identity.monogram` | Ladrilho quadrado ao lado do nome |
| `identity.tagline` | Login, tela de abertura, cabeçalho do PDF |
| `identity.appTitle` | Título da janela / aba do navegador |
| `identity.legalName` | Rodapé de copyright |
| `identity.emailDomain` | E-mails de exemplo no login |
| `palette.*` | Todas as cores do app e do comprovante em PDF |
| `copy.*` | Vocabulário: permuta, grão, insumo, produtor, consultor |
| `shape.*` | Raios de canto (personalidade do desenho) |

## As duas regras que sustentam isso

**1. Nenhum `Color(0x...)` fora de `brands/`.** Se uma tela precisa de um tom
novo, o campo entra em `BrandPalette` e é exposto em `AppColors` — nunca escrito
direto na tela. Uma cor literal numa tela é uma cor que o próximo cliente herda
do anterior.

Para conferir que a regra não foi quebrada:

```sh
grep -rn "Color(0x" lib --include="*.dart" | grep -v "^lib/branding/brands/"
```

O resultado esperado é vazio.

**2. Conteúdo sobre a cor institucional usa os tokens `onPrimary*`,
não branco literal.** `onPrimary`, `onPrimaryMuted`, `onPrimarySubtle`,
`onPrimaryFaint` e `onPrimaryOverlay` formam a escala de contraste sobre
`primary`. Uma marca de fundo **claro** só precisa invertê-los no seu arquivo
para o app inteiro continuar legível — com branco literal espalhado pelas telas,
isso seria impossível.

## Cores que pedem atenção

- **`accentOnLight`** — o acento vivo (lima, âmbar) quase nunca tem contraste
  suficiente sobre branco. Este é o tom escurecido que o logotipo usa sobre
  superfície clara. Vale checar 4.5:1 antes de fechar.
- **`grain` e `input`** — são semânticas, não decorativas: o app inteiro usa
  esse par para separar *o que custa* (insumo retirado) de *o que paga* (grão).
  Precisam ser distinguíveis entre si e da institucional.
- **`dataSeries`** — série categórica dos gráficos, cíclica. Qualquer grão
  cadastrado ganha cor sem precisar de código.

## Fora do Dart

Estes quatro pontos não são alcançados pelo arquivo de marca e mudam a cada
implantação:

| O quê | Onde |
|---|---|
| Nome no Android | `android/app/src/main/AndroidManifest.xml` → `android:label` |
| Nome no iOS | `ios/Runner/Info.plist` → `CFBundleDisplayName` |
| Nome e cores no web | `web/manifest.json`, `web/index.html` |
| Ícone do app | `android/app/src/main/res/mipmap-*/`, `ios/Runner/Assets.xcassets/`, `web/icons/` |

O identificador de pacote (`applicationId` no Android, bundle id no iOS) também
precisa ser único por cliente se os apps forem publicados em paralelo.

Os e-mails de exemplo do login saem de `identity.emailDomain` e precisam bater
com as contas semeadas pela API em `api/prisma/seed-data.ts`.
