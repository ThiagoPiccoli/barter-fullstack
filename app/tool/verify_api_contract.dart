// Verificação do CONTRATO entre o app e a API, usando o código real do app.
//
// Os testes de `test/` provam que os parsers entendem um JSON de exemplo; a
// suíte da API prova que ela responde o que promete. O que ninguém provava é
// que as duas pontas se encontram — e é exatamente aí que um campo renomeado
// ou um envelope alterado passa despercebido até alguém abrir o app.
//
// Este script sobe os repositórios de verdade (mesmo ApiClient, mesmos
// modelos) contra um servidor rodando e exercita os caminhos que dependem do
// formato: paginação, provisionamento de consultor e catálogo de produtos.
//
//   cd api && npm run start:dev          # servidor em :3333 com o seed
//   cd app && dart run tool/verify_api_contract.dart
//
// Não substitui o teste de integração de UI (integration_test/): aqui não há
// tela nenhuma, só o contrato de dados.
import 'dart:io';

import 'package:barter_app/models/models.dart';
import 'package:barter_app/repositories/barter_repository.dart';
import 'package:barter_app/repositories/catalog_repository.dart';
import 'package:barter_app/repositories/consultant_repository.dart';
import 'package:barter_app/repositories/producer_repository.dart';
import 'package:barter_app/services/api/api_client.dart';

int _failures = 0;

void check(String what, bool ok, [String detail = '']) {
  final mark = ok ? '  ok  ' : ' FALHA';
  stdout.writeln('$mark  $what${detail.isEmpty ? '' : '  ($detail)'}');
  if (!ok) _failures++;
}

Future<void> main() async {
  stdout.writeln('Contrato app ↔ API em ${ApiClient.baseUrl}\n');

  try {
    await _run();
  } on ApiException catch (e) {
    stdout.writeln('\nInterrompido: ${e.message} (HTTP ${e.statusCode})');
    stdout.writeln('O servidor está no ar com o dataset de demonstração?');
    exitCode = 1;
    return;
  }

  stdout.writeln(_failures == 0
      ? '\nTudo certo: o app e a API falam a mesma língua.'
      : '\n$_failures verificação(ões) falharam.');
  exitCode = _failures == 0 ? 0 : 1;
}

Future<void> _run() async {
  /* ── Sessão ───────────────────────────────────────────────────────── */
  final login = await api.post('/auth/login', body: {
    'email': 'admin@barter.com.br',
    'password': '123456',
  }) as Map<String, dynamic>;
  api.token = login['token'] as String;
  final admin = UserModel.fromJson(login['user'] as Map<String, dynamic>);
  check('login devolve usuário e token', admin.role == UserRole.admin, admin.name);

  /* ── Listas paginadas ─────────────────────────────────────────────── */
  // O app remonta as páginas numa lista só; se o `meta` mudasse de forma, o
  // laço pararia cedo e a tela mostraria menos registros do que existem.
  final barters = await BarterRepository().list();
  final producers = await ProducerRepository().list();
  check('permutas chegam completas', barters.isNotEmpty, '${barters.length} registro(s)');
  check('produtores chegam completos', producers.isNotEmpty, '${producers.length} registro(s)');

  // Confere contra o meta.total que o servidor informa para a mesma coleção.
  final firstPage = await api.get('/barters', query: {'limit': '1'});
  check('paginação não perde registros', (firstPage as List).length == 1);

  final tiny = await api.getAll('/barters', pageSize: 2);
  check('mesmo com página de 2, o total bate', tiny.length == barters.length,
      '${tiny.length} vs ${barters.length}');

  /* ── Catálogo ─────────────────────────────────────────────────────── */
  final catalog = CatalogRepository();
  final products = await catalog.listProducts();
  final categories = await catalog.listCategories();
  check('catálogo com histórico de valores',
      products.every((p) => p.priceHistory.isNotEmpty), '${products.length} produto(s)');
  check('categorias com regra legível', categories.isNotEmpty, '${categories.length} pasta(s)');

  final created = await catalog.createProduct(
    name: 'Insumo de Verificação',
    unit: 'litro',
    type: ProductType.input,
    currentPrice: 12.34,
    requiredPerHa: 0,
    categoryId: categories.first.id,
  );
  check('produto criado nasce com o primeiro ponto do histórico',
      created.priceHistory.length == 1 && created.currentPrice == 12.34);
  check('produto criado respeita a categoria', created.categoryId == categories.first.id);

  await catalog.deleteProduct(created.id);
  final afterDelete = await catalog.listProducts();
  check('produto excluído sai do catálogo',
      afterDelete.every((p) => p.id != created.id), '${afterDelete.length} produto(s)');

  /* ── Provisionamento de consultor ─────────────────────────────────── */
  final consultants = ConsultantRepository();
  final email = 'verificacao.${DateTime.now().millisecondsSinceEpoch}@barter.com.br';
  final provisioned = await consultants.create(UserModel(
    id: '',
    name: 'Consultor de Verificação',
    email: email,
    phone: '',
    branch: 'Filial de Teste',
    role: UserRole.consultant,
    avatarInitials: 'CV',
    createdAt: DateTime.now(),
  ));

  check('criação devolve a senha provisória',
      provisioned.provisionalPassword.length >= 8, provisioned.provisionalPassword);
  check('consultor novo nasce obrigado a trocar a senha',
      provisioned.consultant.mustChangePassword);

  // A senha precisa realmente abrir a conta — e ser diferente a cada consultor.
  final second = await consultants.create(UserModel(
    id: '',
    name: 'Outro Consultor',
    email: 'outro.$email',
    phone: '',
    branch: 'Filial de Teste',
    role: UserRole.consultant,
    avatarInitials: 'OC',
    createdAt: DateTime.now(),
  ));
  check('cada consultor recebe uma senha diferente',
      provisioned.provisionalPassword != second.provisionalPassword);

  final reset = await consultants.resetPassword(provisioned.consultant.id);
  check('reset gera outra senha e volta a exigir troca',
      reset.provisionalPassword != provisioned.provisionalPassword &&
          reset.consultant.mustChangePassword,
      reset.provisionalPassword);

  // A listagem NÃO pode carregar a senha de ninguém.
  final listed = await consultants.list();
  check('listagem de consultores não expõe senha',
      listed.every((c) => c.email.isNotEmpty && c.id.isNotEmpty));

  await consultants.delete(provisioned.consultant.id);
  await consultants.delete(second.consultant.id);
  check('consultores de verificação removidos', true);
}
