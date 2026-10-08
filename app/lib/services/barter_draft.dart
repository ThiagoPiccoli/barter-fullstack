/// A PERMUTA SENDO MONTADA — tudo o que se pode perguntar sobre ela antes de
/// existir no servidor.
///
/// Isto era ~180 linhas de getters dentro do `State` da tela de nova permuta. A
/// CONTA já estava no lugar certo (`barter_math.dart`, espelho do servidor); o
/// que morava na tela era a COMPOSIÇÃO — quais insumos estão precificados por
/// esta versão, que classes carregam régua, se a praça do produtor tem seguro,
/// quantas sacas isso tudo dá, e o que ainda impede o envio. Regra, não layout:
/// refazer a tela significava reescrevê-la junto, e ela só tinha teste através
/// de widget.
///
/// É uma classe SEM ESTADO PRÓPRIO: recebe o que a tela tem em mãos e responde.
/// Nada aqui lê `AppData`, nem guarda o que o usuário digitou — quem faz isso
/// continua sendo a tela, que é de quem o `setState` é.
///
/// A MOEDA é a da LENTE, e atravessa todas as respostas: a retaguarda soma em
/// R$, o consultor em sacas (ver `ValueLens`, na API, e `costPerSack`). As duas
/// passam pela mesma conta — o que muda é a unidade em que ela entra.
library;

import '../models/models.dart';
import 'barter_math.dart';

class BarterDraft {
  /// A versão que precifica: a vigente DA CULTURA escolhida numa permuta nova,
  /// a da permuta numa remontagem. `null` é "Barter fechado" (ou cultura ainda
  /// não escolhida), e aí não há o que montar.
  final BarterVersionModel? version;

  /// O produtor escolhido. `null` antes da primeira etapa — e é por isso que
  /// quase toda resposta aqui tem um caminho para "ainda não dá para saber".
  final ProducerModel? producer;

  /// O que o consultor escolheu, por produto. É a única coisa que muda a cada
  /// toque, e é da TELA: aqui ela entra como leitura.
  final Map<String, double> quantities;

  /// O catálogo inteiro de insumos. O recorte do que é permutável nesta gestão
  /// é feito aqui ([catalog]), porque é regra: insumo fora da tabela da versão
  /// não tem preço acordado, e o servidor recusa.
  final List<ProductModel> allInputs;

  /// As classes de insumo, com as réguas de mínimo delas.
  final List<ProductClassModel> classes;

  /// A ÁREA PLANTADA (ha) da cultura que a permuta cobre — o que o consultor
  /// informa. É a régua de tudo o que é "por hectare": os mínimos, o seguro e o
  /// teto do penhor. Zero enquanto ele não informou.
  final double plantedAreaHa;

  /// O SEGURO, quando a versão o oferece como OPCIONAL: o que o produtor
  /// escolheu. Ignorado nas outras políticas.
  final bool wantsInsurance;

  /// A TAXA DE SEGURO do MUNICÍPIO escolhido na opção do seguro — o do
  /// cadastro do produtor até o consultor trocar —, quando ele está na base.
  ///
  /// Ela entra pronta porque a busca é I/O (o cache do app); o que é regra —
  /// se ela se aplica, quanto custa e o que fazer quando falta — está aqui.
  final InsuranceRateModel? insuranceRate;

  /// A BASE DE SEGUROS tem algum município para escolher?
  ///
  /// É o que separa as duas faltas: sem taxa no município escolhido, falta
  /// ESCOLHER outro; sem município nenhum na base, o seguro opcional nem se
  /// liga. `null` deduz da taxa em mãos (quem não passa a base inteira).
  final bool? hasInsuranceRates;

  /// O que veio de FORA DO BARTER nesta permuta: os pedidos que o admin
  /// atendeu. Não está no catálogo (é item cotado para esta permuta só), mas
  /// foi retirado — e as sacas o pagam.
  final double offBarterCost;

  const BarterDraft({
    required this.version,
    required this.producer,
    required this.quantities,
    required this.allInputs,
    required this.classes,
    this.plantedAreaHa = 0,
    this.wantsInsurance = false,
    this.insuranceRate,
    this.hasInsuranceRates,
    this.offBarterCost = 0,
  });

  /// Os insumos que ESTA versão põe na mesa. Fora dela, o insumo existe no
  /// cadastro e não tem valor acordado.
  List<ProductModel> get catalog {
    final current = version;
    if (current == null) return const [];
    return allInputs.where((input) => current.priceOf(input.id) != null).toList();
  }

  ProductModel? productById(String id) {
    for (final input in catalog) {
      if (input.id == id) return input;
    }
    return null;
  }

  /// Os insumos escolhidos, precificados PELA VERSÃO — a entrada da matemática
  /// da permuta (`barter_math.dart`, espelho do cálculo do servidor).
  List<PricedInput> get pricedInputs => [
        for (final entry in quantities.entries)
          if (entry.value > 0)
            PricedInput(
              productId: entry.key,
              quantity: entry.value,
              unitPrice: version?.priceOf(entry.key)?.perUnit ?? 0,
              classId: productById(entry.key)?.classId,
            ),
      ];

  /// Custo dos insumos escolhidos, na moeda da lente — o valor que a permuta
  /// paga.
  double get inputsCost => inputCost(pricedInputs);

  /// A versão OFERECE o seguro como opcional — e aí a tela mostra o interruptor.
  bool get insuranceOffered => version?.insuranceOptional == true && producer != null;

  /// O seguro opcional não pode ser ligado: a base não tem município nenhum
  /// para escolher. A opção aparece BLOQUEADA, com o aviso — a permuta pode
  /// seguir sem seguro.
  bool get insuranceBlocked =>
      insuranceOffered && !(hasInsuranceRates ?? insuranceRate != null);

  /// ESTA PERMUTA LEVA SEGURO? A política é da VERSÃO: obrigatório leva sempre;
  /// opcional leva quando o produtor quis (e a praça tem taxa).
  bool get insuranceApplies {
    if (producer == null || version == null) return false;
    if (version!.insuranceRequired) return true;
    return insuranceOffered && wantsInsurance && !insuranceBlocked;
  }

  /// A permuta LEVA seguro e o município escolhido NÃO tem taxa na base (ou
  /// nenhum foi escolhido).
  ///
  /// É a recusa que o servidor vai dar no registro, antecipada: sem ela, o
  /// consultor monta a permuta inteira com o produtor ao lado e só descobre o
  /// problema ao salvar.
  bool get insuranceMissing => insuranceApplies && insuranceRate == null;

  /// O custo do seguro na moeda da lente — área plantada × taxa da praça. A
  /// mesma conta do servidor (`insuranceCostFor`).
  double get insuranceCost {
    final rate = insuranceRate;
    if (!insuranceApplies || rate == null) return 0;
    return rate.showsCurrency ? rate.costFor(plantedAreaHa) : rate.sacksFor(plantedAreaHa);
  }

  /// O que vai no campo `insurance` do registro: a escolha, só no opcional.
  bool? get insuranceChoice => insuranceOffered ? (wantsInsurance && !insuranceBlocked) : null;

  /// O SEGURO PAGO EM GRÃO: o custo dele em sacas da cultura da permuta.
  ///
  /// É como ele aparece na tela, para as duas lentes: a apólice entra no total
  /// e é paga na mesma entrega que paga os insumos, então a pergunta do
  /// produtor ("quanto o seguro me custa?") se responde em sacas.
  double get insuranceSacks {
    final current = version;
    if (current == null || insuranceCost <= 0) return 0;
    return sacksToCover(insuranceCost, current.costPerSack);
  }

  /// SACAS da cultura escolhida necessárias para cobrir o custo.
  ///
  /// Mesmo arredondamento do servidor: o número da tela é o que será gravado. O
  /// seguro e o item de fora do Barter entram aqui, e só aqui — os dois são
  /// custo que a empresa adianta, e as réguas das pastas não os enxergam.
  double get sacksNeeded {
    final current = version;
    if (current == null) return 0;
    return sacksToCover(inputsCost + offBarterCost + insuranceCost, current.costPerSack);
  }

  /// Quantidade mínima obrigatória de um insumo para esta permuta: taxa por
  /// hectare × área plantada. Zero sem área ou sem exigência.
  double minimumFor(String productId) {
    final input = productById(productId);
    if (producer == null || input == null || plantedAreaHa <= 0) return 0;
    return minQuantityFor(input.requiredPerHa, plantedAreaHa);
  }

  /// Há algum insumo com exigência por área para este produtor?
  bool get hasRequiredInputs => catalog.any((input) => minimumFor(input.id) > 0);

  /// O QUE A PERMUTA JÁ NASCE CARREGANDO: os insumos exigidos por área, no
  /// mínimo de cada um.
  ///
  /// É o pré-preenchimento da escolha do produtor, e é regra: eles são
  /// obrigatórios, e começar em zero faria o consultor descobrir isso um a um,
  /// na recusa do envio.
  Map<String, double> get requiredMinimums => {
        for (final input in catalog)
          if (minimumFor(input.id) > 0) input.id: minimumFor(input.id),
      };

  /// A quantidade que uma escolha PODE ter: nunca abaixo do mínimo obrigatório.
  double clampToMinimum(String productId, double quantity) {
    final min = minimumFor(productId);
    return quantity < min ? min : quantity;
  }

  /// As classes que carregam uma régua capaz de travar o envio.
  List<ProductClassModel> get ruledClasses =>
      classes.where((productClass) => productClass.hasRule).toList();

  /// Custo dos insumos escolhidos que pertencem a uma classe.
  double spendOn(String classId) => classSpend(pricedInputs, classId);

  /// O mínimo exigido por uma classe, dado o estado atual da permuta.
  ///
  /// Sem área plantada informada, a régua por hectare não tem base de cálculo —
  /// o servidor sempre tem, porque a permuta chega com a área.
  double requiredOn(ProductClassModel productClass) {
    if (plantedAreaHa <= 0 && productClass.ruleType == ClassRuleType.valuePerHa) return 0;
    return classRequired(
      ClassRule.values.byName(productClass.ruleType.name),
      productClass.ruleValue,
      totalCost: inputsCost,
      areaHa: plantedAreaHa,
    );
  }

  /// O mínimo da classe foi atingido? (com a tolerância de centavos)
  bool isMet(ProductClassModel productClass) {
    final required = requiredOn(productClass);
    if (required <= 0) return true;
    return spendOn(productClass.id) >= required - moneyEpsilon;
  }

  /// Progresso (0–1) rumo ao mínimo da classe — proporção, nunca R$.
  ///
  /// Com a permuta VAZIA fica em zero, e não em 100%: a régua percentual sobre
  /// um custo zero dá exigência zero — matematicamente cumprida —, mas
  /// "exigência atingida" antes do primeiro insumo é a tela dizendo que ele
  /// terminou sem ter começado.
  double progressOn(ProductClassModel productClass) {
    if (inputsCost <= 0) return 0;
    final required = requiredOn(productClass);
    if (required <= 0) return 1;
    return (spendOn(productClass.id) / required).clamp(0.0, 1.0);
  }

  /// A classe aparece como cumprida NA TELA? Só depois de haver permuta — mesmo
  /// motivo de [progressOn]. Quem decide o ENVIO é [isMet], que não muda: a
  /// permuta vazia já é barrada por não ter insumo nenhum.
  bool isMetOnScreen(ProductClassModel productClass) => inputsCost > 0 && isMet(productClass);

  /// As classes ainda abaixo do mínimo — o que falta para a permuta poder sair.
  List<ProductClassModel> get unmetClasses =>
      ruledClasses.where((productClass) => !isMet(productClass)).toList();

  /// Quantos insumos foram escolhidos.
  int get chosenCount => quantities.values.where((quantity) => quantity > 0).length;

  /// A PERMUTA PODE SER ENVIADA?
  ///
  /// As travas do servidor, na ordem em que ele as aplica: há Barter aberto na
  /// cultura, há produtor, há área plantada, há ao menos um insumo, e as réguas
  /// das classes estão cumpridas. O seguro obrigatório sem taxa na praça entra
  /// junto porque é recusa certa no registro — e descobri-la aqui é de graça.
  bool get canSubmit =>
      version != null &&
      version!.isOpen &&
      producer != null &&
      plantedAreaHa > 0 &&
      chosenCount > 0 &&
      unmetClasses.isEmpty &&
      !insuranceMissing;
}
