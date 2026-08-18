import 'package:flutter_test/flutter_test.dart';

import 'package:agrobarter_app/services/tax_regime.dart';

/// ESPELHO de `api/src/producers/tax-regime.spec.ts` — os mesmos números, do
/// mesmo jeito que os dois `barter_math` se espelham.
///
/// O risco de ter a tabela de alíquotas dos dois lados é ela divergir em
/// silêncio: a tela mostraria 1,63% na fazenda e a permuta sairia gravada com
/// outro percentual. Estes testes existem para que mudar um lado quebre o outro.
void main() {
  const cpf = '123.456.789-00'; // 11 dígitos
  const cnpj = '12.345.678/0001-90'; // 14 dígitos

  test('a pontuação não decide PF ou PJ — a contagem de dígitos decide', () {
    expect(isCompanyDocument(cpf), isFalse);
    expect(isCompanyDocument('CNPJ 12.345.678/0001-90'), isTrue);
    // Documento em branco ou incompleto (o formulário sendo digitado) cai em
    // PF, que é o caso da maioria — e se corrige quando o número fica completo.
    expect(isCompanyDocument(''), isFalse);
    expect(isCompanyDocument('123'), isFalse);
  });

  test('pessoa física na comercialização: 1,32 + 0,11 + 0,20 = 1,63%', () {
    expect(taxRateOf(TaxRegime.comercializacao, cpf), 1.63);
  });

  test('pessoa jurídica na comercialização: 1,98 + 0,25 = 2,23%', () {
    expect(taxRateOf(TaxRegime.comercializacao, cnpj), 2.23);
  });

  test('quem recolhe pela folha ainda paga o Senar sobre a entrega', () {
    expect(taxRateOf(TaxRegime.folha, cpf), 0.2);
    expect(taxRateOf(TaxRegime.folha, cnpj), 0.25);
  });

  test('imposto é valor × alíquota, arredondado em centavos', () {
    // A entrega da PRM-2026-001: 251,4141 sacas × R$ 148,50 = R$ 37.335,00.
    expect(taxAmountOf(37335.0, 1.63), 608.56);
    expect(taxAmountOf(37335.0, 0.2), 74.67);
  });

  test('a mesma conta serve para sacas — a alíquota é percentual', () {
    expect(taxAmountOf(251.4141, 1.63), 4.1);
  });

  test('entrega ou alíquota inexistentes não geram imposto', () {
    expect(taxAmountOf(0, 1.63), 0);
    expect(taxAmountOf(37335.0, 0), 0);
    expect(taxAmountOf(-100, 1.63), 0);
  });

  test('regime desconhecido do servidor cai no padrão legal', () {
    expect(taxRegimeFrom('comercializacao'), TaxRegime.comercializacao);
    expect(taxRegimeFrom('folha'), TaxRegime.folha);
    // Um regime que esta versão do app não conhece não pode derrubar a lista de
    // produtores — mesmo cuidado do status da permuta.
    expect(taxRegimeFrom('presumido'), TaxRegime.comercializacao);
    expect(taxRegimeFrom(null), TaxRegime.comercializacao);
  });

  test('o rótulo do regime da folha não promete isenção', () {
    expect(TaxRegime.folha.label, 'Sobre a folha de pagamento');
    expect(TaxRegime.folha.description, contains('Senar'));
    expect(TaxRegime.folha.apiValue, 'folha');
  });
}
