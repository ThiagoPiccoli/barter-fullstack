import '../models/models.dart';
import '../services/api/api_client.dart';

/// Catálogo: produtos (grãos e insumos, com histórico de valores) e as
/// "pastas" de insumos com regra de mínimo. Escritas são do admin.
class CatalogRepository {
  Future<List<ProductModel>> listProducts() async {
    final data = await api.get('/products') as List;
    return data.cast<Map<String, dynamic>>().map(ProductModel.fromJson).toList();
  }

  Future<List<InputCategoryModel>> listCategories() async {
    final data = await api.get('/categories') as List;
    return data.cast<Map<String, dynamic>>().map(InputCategoryModel.fromJson).toList();
  }

  /// Cadastra um grão ou insumo. O servidor abre a linha do tempo de valores
  /// com o preço informado — todo produto nasce com um primeiro ponto.
  Future<ProductModel> createProduct({
    required String name,
    required String unit,
    required ProductType type,
    required double currentPrice,
    double requiredPerHa = 0,
    String? categoryId,
  }) async {
    final data = await api.post('/products', body: {
      'name': name,
      'unit': unit,
      'type': type.name,
      'currentPrice': currentPrice,
      'requiredPerHa': requiredPerHa,
      if (categoryId != null) 'categoryId': int.parse(categoryId),
    });
    return ProductModel.fromJson(data as Map<String, dynamic>);
  }

  /// Tira o produto do catálogo. As permutas já registradas não mudam: elas
  /// guardam nome, unidade e preço no próprio item.
  Future<void> deleteProduct(String id) => api.delete('/products/$id');

  /// Reajusta o valor de referência; o servidor acrescenta o ponto na linha
  /// do tempo e devolve o produto atualizado.
  Future<ProductModel> updatePrice(String productId, double price) async {
    final data = await api.put('/products/$productId/price', body: {'price': price});
    return ProductModel.fromJson(data as Map<String, dynamic>);
  }

  /// Edição parcial do cadastro do produto (categoria, exigência/ha, nome...).
  /// Envie `{'categoryId': null}` para desvincular da pasta.
  Future<ProductModel> updateProduct(String productId, Map<String, dynamic> fields) async {
    final data = await api.put('/products/$productId', body: fields);
    return ProductModel.fromJson(data as Map<String, dynamic>);
  }

  Future<InputCategoryModel> createCategory(InputCategoryModel category) async {
    final data = await api.post('/categories', body: _categoryPayload(category));
    return InputCategoryModel.fromJson(data as Map<String, dynamic>);
  }

  Future<InputCategoryModel> updateCategory(InputCategoryModel category) async {
    final data = await api.put('/categories/${category.id}', body: _categoryPayload(category));
    return InputCategoryModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteCategory(String id) => api.delete('/categories/$id');

  Map<String, dynamic> _categoryPayload(InputCategoryModel c) => {
        'name': c.name,
        'ruleType': c.ruleType.name,
        'ruleValue': c.ruleValue,
      };
}
