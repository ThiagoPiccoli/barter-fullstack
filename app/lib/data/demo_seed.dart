/// A senha das contas do DATASET DE DEMONSTRAÇÃO da API.
///
/// Espelha a `SEED_PASSWORD` de `api/prisma/seed-data.ts`. As duas pontas
/// precisam concordar, e o valor aparece em três lugares deste lado — o
/// preenchimento rápido da tela de login (só em debug), o teste de integração e
/// o verificador de contrato —, então ele mora aqui em vez de ser digitado de
/// novo em cada um.
///
/// Era `123456`, que é o primeiro item da lista de senhas proibidas do
/// servidor: o sistema criava contas com uma senha que ele próprio recusaria.
///
/// Isto NÃO é credencial de produção. O dataset só é carregado quando a API
/// sobe fora de `NODE_ENV=production`, e nenhuma conta real usa este valor.
const String demoSeedPassword = 'demo-2026-agro';
