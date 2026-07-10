import type Producer from '#models/producer'
import { BaseTransformer } from '@adonisjs/core/transformers'

export default class ProducerTransformer extends BaseTransformer<Producer> {
  toObject() {
    return this.pick(this.resource, [
      'id',
      'name',
      'sellerId',
      'document',
      'phone',
      'farmName',
      'city',
      'areaHa',
      'createdAt',
      'initials',
    ])
  }
}
