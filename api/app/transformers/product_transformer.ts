import type Product from '#models/product'
import { BaseTransformer } from '@adonisjs/core/transformers'
import PriceHistoryEntryTransformer from '#transformers/price_history_entry_transformer'

export default class ProductTransformer extends BaseTransformer<Product> {
  toObject() {
    return {
      ...this.pick(this.resource, [
        'id',
        'name',
        'unit',
        'type',
        'currentPrice',
        'requiredPerHa',
        'categoryId',
      ]),
      priceHistory: PriceHistoryEntryTransformer.transform(
        this.whenLoaded(this.resource.priceHistory)
      ),
    }
  }
}
