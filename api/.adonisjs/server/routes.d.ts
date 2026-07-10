import '@adonisjs/core/types/http'

type ParamValue = string | number | bigint | boolean

export type ScannedRoutes = {
  ALL: {
    'auth.login': { paramsTuple?: []; params?: {} }
    'auth.logout': { paramsTuple?: []; params?: {} }
    'me': { paramsTuple?: []; params?: {} }
    'producers.index': { paramsTuple?: []; params?: {} }
    'producers.show': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'products.index': { paramsTuple?: []; params?: {} }
    'products.show': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'categories.index': { paramsTuple?: []; params?: {} }
    'barters.index': { paramsTuple?: []; params?: {} }
    'barters.show': { paramsTuple: [ParamValue]; params: {'code': ParamValue} }
    'barters.store': { paramsTuple?: []; params?: {} }
    'producers.store': { paramsTuple?: []; params?: {} }
    'producers.update': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'producers.destroy': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'sellers.index': { paramsTuple?: []; params?: {} }
    'sellers.store': { paramsTuple?: []; params?: {} }
    'sellers.update': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'sellers.destroy': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'categories.store': { paramsTuple?: []; params?: {} }
    'categories.update': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'categories.destroy': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'products.store': { paramsTuple?: []; params?: {} }
    'products.update': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'products.updatePrice': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'barters.review': { paramsTuple: [ParamValue]; params: {'code': ParamValue} }
  }
  GET: {
    'me': { paramsTuple?: []; params?: {} }
    'producers.index': { paramsTuple?: []; params?: {} }
    'producers.show': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'products.index': { paramsTuple?: []; params?: {} }
    'products.show': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'categories.index': { paramsTuple?: []; params?: {} }
    'barters.index': { paramsTuple?: []; params?: {} }
    'barters.show': { paramsTuple: [ParamValue]; params: {'code': ParamValue} }
    'sellers.index': { paramsTuple?: []; params?: {} }
  }
  HEAD: {
    'me': { paramsTuple?: []; params?: {} }
    'producers.index': { paramsTuple?: []; params?: {} }
    'producers.show': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'products.index': { paramsTuple?: []; params?: {} }
    'products.show': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'categories.index': { paramsTuple?: []; params?: {} }
    'barters.index': { paramsTuple?: []; params?: {} }
    'barters.show': { paramsTuple: [ParamValue]; params: {'code': ParamValue} }
    'sellers.index': { paramsTuple?: []; params?: {} }
  }
  POST: {
    'auth.login': { paramsTuple?: []; params?: {} }
    'auth.logout': { paramsTuple?: []; params?: {} }
    'barters.store': { paramsTuple?: []; params?: {} }
    'producers.store': { paramsTuple?: []; params?: {} }
    'sellers.store': { paramsTuple?: []; params?: {} }
    'categories.store': { paramsTuple?: []; params?: {} }
    'products.store': { paramsTuple?: []; params?: {} }
    'barters.review': { paramsTuple: [ParamValue]; params: {'code': ParamValue} }
  }
  PUT: {
    'producers.update': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'sellers.update': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'categories.update': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'products.update': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'products.updatePrice': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
  }
  DELETE: {
    'producers.destroy': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'sellers.destroy': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
    'categories.destroy': { paramsTuple: [ParamValue]; params: {'id': ParamValue} }
  }
}
declare module '@adonisjs/core/types/http' {
  export interface RoutesList extends ScannedRoutes {}
}