/* eslint-disable prettier/prettier */
import type { AdonisEndpoint } from '@tuyau/core/types'
import type { Registry } from './schema.d.ts'
import type { ApiDefinition } from './tree.d.ts'

const placeholder: any = {}

const routes = {
  'auth.login': {
    methods: ["POST"],
    pattern: '/api/v1/auth/login',
    tokens: [{"old":"/api/v1/auth/login","type":0,"val":"api","end":""},{"old":"/api/v1/auth/login","type":0,"val":"v1","end":""},{"old":"/api/v1/auth/login","type":0,"val":"auth","end":""},{"old":"/api/v1/auth/login","type":0,"val":"login","end":""}],
    types: placeholder as Registry['auth.login']['types'],
  },
  'auth.logout': {
    methods: ["POST"],
    pattern: '/api/v1/auth/logout',
    tokens: [{"old":"/api/v1/auth/logout","type":0,"val":"api","end":""},{"old":"/api/v1/auth/logout","type":0,"val":"v1","end":""},{"old":"/api/v1/auth/logout","type":0,"val":"auth","end":""},{"old":"/api/v1/auth/logout","type":0,"val":"logout","end":""}],
    types: placeholder as Registry['auth.logout']['types'],
  },
  'me': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/me',
    tokens: [{"old":"/api/v1/me","type":0,"val":"api","end":""},{"old":"/api/v1/me","type":0,"val":"v1","end":""},{"old":"/api/v1/me","type":0,"val":"me","end":""}],
    types: placeholder as Registry['me']['types'],
  },
  'producers.index': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/producers',
    tokens: [{"old":"/api/v1/producers","type":0,"val":"api","end":""},{"old":"/api/v1/producers","type":0,"val":"v1","end":""},{"old":"/api/v1/producers","type":0,"val":"producers","end":""}],
    types: placeholder as Registry['producers.index']['types'],
  },
  'producers.show': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/producers/:id',
    tokens: [{"old":"/api/v1/producers/:id","type":0,"val":"api","end":""},{"old":"/api/v1/producers/:id","type":0,"val":"v1","end":""},{"old":"/api/v1/producers/:id","type":0,"val":"producers","end":""},{"old":"/api/v1/producers/:id","type":1,"val":"id","end":""}],
    types: placeholder as Registry['producers.show']['types'],
  },
  'products.index': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/products',
    tokens: [{"old":"/api/v1/products","type":0,"val":"api","end":""},{"old":"/api/v1/products","type":0,"val":"v1","end":""},{"old":"/api/v1/products","type":0,"val":"products","end":""}],
    types: placeholder as Registry['products.index']['types'],
  },
  'products.show': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/products/:id',
    tokens: [{"old":"/api/v1/products/:id","type":0,"val":"api","end":""},{"old":"/api/v1/products/:id","type":0,"val":"v1","end":""},{"old":"/api/v1/products/:id","type":0,"val":"products","end":""},{"old":"/api/v1/products/:id","type":1,"val":"id","end":""}],
    types: placeholder as Registry['products.show']['types'],
  },
  'categories.index': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/categories',
    tokens: [{"old":"/api/v1/categories","type":0,"val":"api","end":""},{"old":"/api/v1/categories","type":0,"val":"v1","end":""},{"old":"/api/v1/categories","type":0,"val":"categories","end":""}],
    types: placeholder as Registry['categories.index']['types'],
  },
  'barters.index': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/barters',
    tokens: [{"old":"/api/v1/barters","type":0,"val":"api","end":""},{"old":"/api/v1/barters","type":0,"val":"v1","end":""},{"old":"/api/v1/barters","type":0,"val":"barters","end":""}],
    types: placeholder as Registry['barters.index']['types'],
  },
  'barters.show': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/barters/:code',
    tokens: [{"old":"/api/v1/barters/:code","type":0,"val":"api","end":""},{"old":"/api/v1/barters/:code","type":0,"val":"v1","end":""},{"old":"/api/v1/barters/:code","type":0,"val":"barters","end":""},{"old":"/api/v1/barters/:code","type":1,"val":"code","end":""}],
    types: placeholder as Registry['barters.show']['types'],
  },
  'barters.store': {
    methods: ["POST"],
    pattern: '/api/v1/barters',
    tokens: [{"old":"/api/v1/barters","type":0,"val":"api","end":""},{"old":"/api/v1/barters","type":0,"val":"v1","end":""},{"old":"/api/v1/barters","type":0,"val":"barters","end":""}],
    types: placeholder as Registry['barters.store']['types'],
  },
  'producers.store': {
    methods: ["POST"],
    pattern: '/api/v1/producers',
    tokens: [{"old":"/api/v1/producers","type":0,"val":"api","end":""},{"old":"/api/v1/producers","type":0,"val":"v1","end":""},{"old":"/api/v1/producers","type":0,"val":"producers","end":""}],
    types: placeholder as Registry['producers.store']['types'],
  },
  'producers.update': {
    methods: ["PUT"],
    pattern: '/api/v1/producers/:id',
    tokens: [{"old":"/api/v1/producers/:id","type":0,"val":"api","end":""},{"old":"/api/v1/producers/:id","type":0,"val":"v1","end":""},{"old":"/api/v1/producers/:id","type":0,"val":"producers","end":""},{"old":"/api/v1/producers/:id","type":1,"val":"id","end":""}],
    types: placeholder as Registry['producers.update']['types'],
  },
  'producers.destroy': {
    methods: ["DELETE"],
    pattern: '/api/v1/producers/:id',
    tokens: [{"old":"/api/v1/producers/:id","type":0,"val":"api","end":""},{"old":"/api/v1/producers/:id","type":0,"val":"v1","end":""},{"old":"/api/v1/producers/:id","type":0,"val":"producers","end":""},{"old":"/api/v1/producers/:id","type":1,"val":"id","end":""}],
    types: placeholder as Registry['producers.destroy']['types'],
  },
  'sellers.index': {
    methods: ["GET","HEAD"],
    pattern: '/api/v1/sellers',
    tokens: [{"old":"/api/v1/sellers","type":0,"val":"api","end":""},{"old":"/api/v1/sellers","type":0,"val":"v1","end":""},{"old":"/api/v1/sellers","type":0,"val":"sellers","end":""}],
    types: placeholder as Registry['sellers.index']['types'],
  },
  'sellers.store': {
    methods: ["POST"],
    pattern: '/api/v1/sellers',
    tokens: [{"old":"/api/v1/sellers","type":0,"val":"api","end":""},{"old":"/api/v1/sellers","type":0,"val":"v1","end":""},{"old":"/api/v1/sellers","type":0,"val":"sellers","end":""}],
    types: placeholder as Registry['sellers.store']['types'],
  },
  'sellers.update': {
    methods: ["PUT"],
    pattern: '/api/v1/sellers/:id',
    tokens: [{"old":"/api/v1/sellers/:id","type":0,"val":"api","end":""},{"old":"/api/v1/sellers/:id","type":0,"val":"v1","end":""},{"old":"/api/v1/sellers/:id","type":0,"val":"sellers","end":""},{"old":"/api/v1/sellers/:id","type":1,"val":"id","end":""}],
    types: placeholder as Registry['sellers.update']['types'],
  },
  'sellers.destroy': {
    methods: ["DELETE"],
    pattern: '/api/v1/sellers/:id',
    tokens: [{"old":"/api/v1/sellers/:id","type":0,"val":"api","end":""},{"old":"/api/v1/sellers/:id","type":0,"val":"v1","end":""},{"old":"/api/v1/sellers/:id","type":0,"val":"sellers","end":""},{"old":"/api/v1/sellers/:id","type":1,"val":"id","end":""}],
    types: placeholder as Registry['sellers.destroy']['types'],
  },
  'categories.store': {
    methods: ["POST"],
    pattern: '/api/v1/categories',
    tokens: [{"old":"/api/v1/categories","type":0,"val":"api","end":""},{"old":"/api/v1/categories","type":0,"val":"v1","end":""},{"old":"/api/v1/categories","type":0,"val":"categories","end":""}],
    types: placeholder as Registry['categories.store']['types'],
  },
  'categories.update': {
    methods: ["PUT"],
    pattern: '/api/v1/categories/:id',
    tokens: [{"old":"/api/v1/categories/:id","type":0,"val":"api","end":""},{"old":"/api/v1/categories/:id","type":0,"val":"v1","end":""},{"old":"/api/v1/categories/:id","type":0,"val":"categories","end":""},{"old":"/api/v1/categories/:id","type":1,"val":"id","end":""}],
    types: placeholder as Registry['categories.update']['types'],
  },
  'categories.destroy': {
    methods: ["DELETE"],
    pattern: '/api/v1/categories/:id',
    tokens: [{"old":"/api/v1/categories/:id","type":0,"val":"api","end":""},{"old":"/api/v1/categories/:id","type":0,"val":"v1","end":""},{"old":"/api/v1/categories/:id","type":0,"val":"categories","end":""},{"old":"/api/v1/categories/:id","type":1,"val":"id","end":""}],
    types: placeholder as Registry['categories.destroy']['types'],
  },
  'products.store': {
    methods: ["POST"],
    pattern: '/api/v1/products',
    tokens: [{"old":"/api/v1/products","type":0,"val":"api","end":""},{"old":"/api/v1/products","type":0,"val":"v1","end":""},{"old":"/api/v1/products","type":0,"val":"products","end":""}],
    types: placeholder as Registry['products.store']['types'],
  },
  'products.update': {
    methods: ["PUT"],
    pattern: '/api/v1/products/:id',
    tokens: [{"old":"/api/v1/products/:id","type":0,"val":"api","end":""},{"old":"/api/v1/products/:id","type":0,"val":"v1","end":""},{"old":"/api/v1/products/:id","type":0,"val":"products","end":""},{"old":"/api/v1/products/:id","type":1,"val":"id","end":""}],
    types: placeholder as Registry['products.update']['types'],
  },
  'products.updatePrice': {
    methods: ["PUT"],
    pattern: '/api/v1/products/:id/price',
    tokens: [{"old":"/api/v1/products/:id/price","type":0,"val":"api","end":""},{"old":"/api/v1/products/:id/price","type":0,"val":"v1","end":""},{"old":"/api/v1/products/:id/price","type":0,"val":"products","end":""},{"old":"/api/v1/products/:id/price","type":1,"val":"id","end":""},{"old":"/api/v1/products/:id/price","type":0,"val":"price","end":""}],
    types: placeholder as Registry['products.updatePrice']['types'],
  },
  'barters.review': {
    methods: ["POST"],
    pattern: '/api/v1/barters/:code/review',
    tokens: [{"old":"/api/v1/barters/:code/review","type":0,"val":"api","end":""},{"old":"/api/v1/barters/:code/review","type":0,"val":"v1","end":""},{"old":"/api/v1/barters/:code/review","type":0,"val":"barters","end":""},{"old":"/api/v1/barters/:code/review","type":1,"val":"code","end":""},{"old":"/api/v1/barters/:code/review","type":0,"val":"review","end":""}],
    types: placeholder as Registry['barters.review']['types'],
  },
} as const satisfies Record<string, AdonisEndpoint>

export { routes }

export const registry = {
  routes,
  $tree: {} as ApiDefinition,
}

declare module '@tuyau/core/types' {
  export interface UserRegistry {
    routes: typeof routes
    $tree: ApiDefinition
  }
}
