import '../models/models.dart';
import '../services/api/api_client.dart';

/// Catálogo: produtos (grãos e insumos, com histórico de valores) e as CLASSES
/// de produto com sua regra de mínimo.
///
/// As classes vêm da lista de preços do fornecedor (a carga em massa cria a
/// que não existe) — aqui só se lê e se ajusta a regra de mínimo.
class CatalogRepository {
  /// O catálogo inteiro, **sem** a linha do tempo de cada produto: dela vêm só
  /// o primeiro valor e a contagem (ver [ProductModel.priceHistory]). É a
  /// chamada que o app faz a cada login e a cada refresh, então ela não pode
  /// crescer junto com o número de versões publicadas.
  Future<List<ProductModel>> listProducts() async =>
      parseProducts(await listProductsRaw());

  /// O MESMO catálogo, ainda como veio da API.
  ///
  /// O cache offline guarda o JSON CRU, e não os modelos: assim os dois lados
  /// atravessam o mesmo `fromJson`, e o que o app lê do aparelho é idêntico ao
  /// que ele leria do servidor. Um `toJson` escrito à mão daria uma segunda
  /// gramática para o mesmo dado — e o dia em que ela divergisse do parser seria
  /// o dia em que a permuta montada offline sairia com outro número.
  Future<List<Map<String, dynamic>>> listProductsRaw() async =>
      (await api.get('/products') as List).cast<Map<String, dynamic>>();

  List<ProductModel> parseProducts(List<Map<String, dynamic>> rows) =>
      rows.map(ProductModel.fromJson).toList();

  /// Um produto com a linha do tempo COMPLETA — o que o relatório de preço
  /// desenha. Buscado sob demanda, ao abrir a tela de um produto.
  Future<ProductModel> findProduct(String id) async {
    final data = await api.get('/products/$id');
    return ProductModel.fromJson(data as Map<String, dynamic>);
  }

  Future<List<ProductClassModel>> listClasses() async =>
      parseClasses(await listClassesRaw());

  Future<List<Map<String, dynamic>>> listClassesRaw() async =>
      (await api.get('/classes') as List).cast<Map<String, dynamic>>();

  List<ProductClassModel> parseClasses(List<Map<String, dynamic>> rows) =>
      rows.map(ProductClassModel.fromJson).toList();

  /// Cadastra um grão ou insumo. O servidor abre a linha do tempo de valores
  /// com o preço informado — todo produto nasce com um primeiro ponto.
  Future<ProductModel> createProduct({
    required String name,
    String sku = '',
    required String unit,
    required ProductType type,
    required double currentPrice,
    double requiredPerHa = 0,
    String? classId,
  }) async {
    final data = await api.post('/products', body: {
      'name': name,
      // Vazio o servidor gera — nenhum item fica sem código.
      if (sku.isNotEmpty) 'sku': sku,
      'unit': unit,
      'type': type.name,
      'currentPrice': currentPrice,
      'requiredPerHa': requiredPerHa,
      if (classId != null) 'classId': int.parse(classId),
    });
    return ProductModel.fromJson(data as Map<String, dynamic>);
  }

  /// Tira o produto do catálogo. As permutas já registradas não mudam: elas
  /// guardam nome, unidade e preço no próprio item.
  Future<void> deleteProduct(String id) => api.delete('/products/$id');

  // Não há reajuste de preço pelo catálogo: valor pertence à VERSÃO do Barter
  // (ver barter_program_repository.dart). O `currentPrice` que chega em
  // ProductModel é o último valor publicado — leitura, não edição.

  /// Edição parcial do cadastro do produto (classe, exigência/ha, nome...).
  /// Envie `{'classId': null}` para desvincular da classe.
  Future<ProductModel> updateProduct(String productId, Map<String, dynamic> fields) async {
    final data = await api.put('/products/$productId', body: fields);
    return ProductModel.fromJson(data as Map<String, dynamic>);
  }

  /// Ajusta a REGRA de mínimo de uma classe — a única alteração que ela aceita.
  /// Criar, renomear ou excluir classe não existe: a lista é do negócio.
  Future<ProductClassModel> updateClassRule(ProductClassModel productClass) async {
    final data = await api.put('/classes/${productClass.id}/rule', body: {
      'ruleType': productClass.ruleType.name,
      'ruleValue': productClass.ruleValue,
    });
    return ProductClassModel.fromJson(data as Map<String, dynamic>);
  }
}
