import type Barter from '#models/barter'
import { BaseTransformer } from '@adonisjs/core/transformers'
import BarterItemTransformer from '#transformers/barter_item_transformer'

export default class BarterTransformer extends BaseTransformer<Barter> {
  toObject() {
    return {
      ...this.pick(this.resource, [
        'id',
        'code',
        'sellerId',
        'sellerName',
        'sellerBranch',
        'producerId',
        'producerName',
        'status',
        'adminNote',
        'reviewedBy',
        'reviewedAt',
        'createdAt',
      ]),
      items: BarterItemTransformer.transform(this.whenLoaded(this.resource.items)),
    }
  }
}
