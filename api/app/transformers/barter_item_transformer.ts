import type BarterItem from '#models/barter_item'
import { BaseTransformer } from '@adonisjs/core/transformers'

export default class BarterItemTransformer extends BaseTransformer<BarterItem> {
  toObject() {
    return this.pick(this.resource, [
      'kind',
      'productId',
      'productName',
      'unit',
      'quantity',
      'unitValue',
    ])
  }
}
