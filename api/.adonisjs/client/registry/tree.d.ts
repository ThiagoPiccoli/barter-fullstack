/* eslint-disable prettier/prettier */
import type { routes } from './index.ts'

export interface ApiDefinition {
  auth: {
    login: typeof routes['auth.login']
    logout: typeof routes['auth.logout']
  }
  me: typeof routes['me']
  producers: {
    index: typeof routes['producers.index']
    show: typeof routes['producers.show']
    store: typeof routes['producers.store']
    update: typeof routes['producers.update']
    destroy: typeof routes['producers.destroy']
  }
  products: {
    index: typeof routes['products.index']
    show: typeof routes['products.show']
    store: typeof routes['products.store']
    update: typeof routes['products.update']
    updatePrice: typeof routes['products.updatePrice']
  }
  categories: {
    index: typeof routes['categories.index']
    store: typeof routes['categories.store']
    update: typeof routes['categories.update']
    destroy: typeof routes['categories.destroy']
  }
  barters: {
    index: typeof routes['barters.index']
    show: typeof routes['barters.show']
    store: typeof routes['barters.store']
    review: typeof routes['barters.review']
  }
  sellers: {
    index: typeof routes['sellers.index']
    store: typeof routes['sellers.store']
    update: typeof routes['sellers.update']
    destroy: typeof routes['sellers.destroy']
  }
}
