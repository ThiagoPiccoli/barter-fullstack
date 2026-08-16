/**
 * COBERTURA DE VERDADE — as duas suítes numa execução só.
 *
 * O `npm test` mede só a unidade, e o relatório que saía dele era enganoso ao
 * ponto de não servir para nada: ele contava TODOS os arquivos de `src/` como
 * alvo, mas rodava apenas os `*.spec.ts`. Os testes e2e — que são onde services
 * e controllers realmente são exercitados — ficavam de fora da execução e
 * dentro do denominador. Daí `barters.service.ts` aparecer com 0% enquanto
 * existia uma suíte inteira de permuta passando por ele.
 *
 * Um número errado é pior que nenhum: ele convida a "melhorar a cobertura"
 * escrevendo teste onde já havia, e a discutir meta sobre um valor que ninguém
 * verificou. `projects` resolve porque a instrumentação é uma só, compartilhada
 * pelas duas suítes, e a soma sai correta sem precisar juntar relatórios.
 *
 * `--runInBand` não é opcional: os e2e compartilham um banco Postgres e se
 * atropelam em paralelo (cada spec apaga e re-semeia).
 */
const transform = { '^.+\\.(t|j)s$': 'ts-jest' };
const shared = {
  rootDir: '.',
  testEnvironment: 'node',
  moduleFileExtensions: ['js', 'json', 'ts'],
  transform,
};

module.exports = {
  rootDir: '.',
  projects: [
    { ...shared, displayName: 'unidade', testMatch: ['<rootDir>/src/**/*.spec.ts'] },
    { ...shared, displayName: 'e2e', testMatch: ['<rootDir>/test/**/*.e2e-spec.ts'] },
  ],
  collectCoverage: true,
  collectCoverageFrom: [
    'src/**/*.ts',
    // O que não é código de decisão sai do denominador: as próprias specs, os
    // módulos do Nest (só fiação de DI) e os DTOs (declaração de decorators).
    // Mantê-los dentro empurrava o número para baixo sem apontar risco nenhum.
    //
    // Os DTOs estavam nesta lista só no comentário: a linha que os exclui não
    // existia, e ninguém percebeu porque o texto já dizia que sim.
    '!src/**/*.spec.ts',
    '!src/**/*.module.ts',
    '!src/**/dto/*.ts',
    '!src/main.ts',
  ],
  coverageDirectory: 'coverage',
  coverageReporters: ['text-summary', 'text', 'lcov'],
};
