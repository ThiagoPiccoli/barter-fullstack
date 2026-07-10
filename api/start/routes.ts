/*
|--------------------------------------------------------------------------
| Routes file
|--------------------------------------------------------------------------
|
| API do Barter (permuta de grãos por insumos), versão v1.
|
| Papéis: `seller` (vendedor) registra permutas para a própria carteira de
| produtores; `admin` gerencia cadastros/valores e revisa permutas. Não há
| signup público — vendedores são provisionados pelo admin.
|
*/

import { middleware } from '#start/kernel'
import router from '@adonisjs/core/services/router'
import { controllers } from '#generated/controllers'

router.get('/', () => {
  return { name: 'Barter API', docs: '/api/v1' }
})

router
  .group(() => {
    /** Público: apenas login. */
    router.post('auth/login', [controllers.AccessTokens, 'store']).as('auth.login')

    /** Autenticado (vendedor ou admin). */
    router
      .group(() => {
        router.post('auth/logout', [controllers.AccessTokens, 'destroy']).as('auth.logout')
        router.get('me', [controllers.Profile, 'show']).as('me')

        // Carteira de produtores (lista/detalhe escopados por papel)
        router.get('producers', [controllers.Producers, 'index']).as('producers.index')
        router.get('producers/:id', [controllers.Producers, 'show']).as('producers.show')

        // Catálogo (produtos com histórico de valores) e pastas de insumos
        router.get('products', [controllers.Products, 'index']).as('products.index')
        router.get('products/:id', [controllers.Products, 'show']).as('products.show')
        router.get('categories', [controllers.Categories, 'index']).as('categories.index')

        // Permutas: listar/detalhar (escopado) e registrar (vendedor)
        router.get('barters', [controllers.Barters, 'index']).as('barters.index')
        router.get('barters/:code', [controllers.Barters, 'show']).as('barters.show')
        router.post('barters', [controllers.Barters, 'store']).as('barters.store')

        /** Só admin: cadastros, valores de referência e revisão de permutas. */
        router
          .group(() => {
            router.post('producers', [controllers.Producers, 'store']).as('producers.store')
            router.put('producers/:id', [controllers.Producers, 'update']).as('producers.update')
            router
              .delete('producers/:id', [controllers.Producers, 'destroy'])
              .as('producers.destroy')

            router.get('sellers', [controllers.Sellers, 'index']).as('sellers.index')
            router.post('sellers', [controllers.Sellers, 'store']).as('sellers.store')
            router.put('sellers/:id', [controllers.Sellers, 'update']).as('sellers.update')
            router.delete('sellers/:id', [controllers.Sellers, 'destroy']).as('sellers.destroy')

            router.post('categories', [controllers.Categories, 'store']).as('categories.store')
            router
              .put('categories/:id', [controllers.Categories, 'update'])
              .as('categories.update')
            router
              .delete('categories/:id', [controllers.Categories, 'destroy'])
              .as('categories.destroy')

            router.post('products', [controllers.Products, 'store']).as('products.store')
            router.put('products/:id', [controllers.Products, 'update']).as('products.update')
            router
              .put('products/:id/price', [controllers.Products, 'updatePrice'])
              .as('products.updatePrice')

            router
              .post('barters/:code/review', [controllers.Barters, 'review'])
              .as('barters.review')
          })
          .use(middleware.admin())
      })
      .use(middleware.auth())
  })
  .prefix('/api/v1')
