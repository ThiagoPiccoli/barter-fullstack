import type PriceHistoryEntry from '#models/price_history_entry'
import { BaseTransformer } from '@adonisjs/core/transformers'

export default class PriceHistoryEntryTransformer extends BaseTransformer<PriceHistoryEntry> {
  toObject() {
    return this.pick(this.resource, ['price', 'changedBy', 'changedAt'])
  }
}
