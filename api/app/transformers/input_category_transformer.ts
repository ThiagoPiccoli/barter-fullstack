import type InputCategory from '#models/input_category'
import { BaseTransformer } from '@adonisjs/core/transformers'

export default class InputCategoryTransformer extends BaseTransformer<InputCategory> {
  toObject() {
    return this.pick(this.resource, ['id', 'name', 'ruleType', 'ruleValue'])
  }
}
