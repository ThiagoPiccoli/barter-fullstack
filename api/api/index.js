// A FUNÇÃO que a Vercel empacota. Ela é de propósito trivial, e em JavaScript.
//
// Tudo que importa mora em `src/serverless.ts`, compilado pelo `tsc` no passo
// de build (`vercel.json` → buildCommand). O empacotador de funções da Vercel
// usa esbuild, que não emite `emitDecoratorMetadata`; se o código do Nest
// passasse por ele, a injeção de dependência quebraria em produção. Aqui não há
// decorator nenhum para perder — só um `require` do que o tsc já compilou.
module.exports = require('../dist/src/serverless.js').default;
