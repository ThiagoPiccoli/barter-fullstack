import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';

/**
 * Paginação das coleções que crescem com o uso.
 *
 * Nem toda lista precisa disto. O catálogo (produtos, categorias) e a lista de
 * consultores são limitados pelo tamanho da operação e o app precisa deles
 * inteiros para montar a tela de permuta — paginá-los só criaria complexidade.
 * Já as PERMUTAS e os PRODUTORES crescem a cada safra e não têm teto: é aí que
 * uma resposta sem limite acaba carregando o banco inteiro numa requisição.
 */

/** Quanto uma página devolve quando o cliente não pede um tamanho. */
export const DEFAULT_PAGE_SIZE = 100;

/** Teto por requisição: acima disso a API recusa, em vez de aceitar e cortar. */
export const MAX_PAGE_SIZE = 500;

export class PaginationQuery {
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'O parâmetro "limit" precisa ser um número inteiro' })
  @Min(1, { message: 'O parâmetro "limit" precisa ser no mínimo 1' })
  @Max(MAX_PAGE_SIZE, { message: `O parâmetro "limit" não pode passar de ${MAX_PAGE_SIZE}` })
  limit?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: 'O parâmetro "offset" precisa ser um número inteiro' })
  @Min(0, { message: 'O parâmetro "offset" não pode ser negativo' })
  offset?: number;
}

/** Janela efetiva de uma consulta, já com os padrões aplicados. */
export function windowOf(query: PaginationQuery): { take: number; skip: number } {
  return { take: query.limit ?? DEFAULT_PAGE_SIZE, skip: query.offset ?? 0 };
}

/**
 * Página de resultados. O EnvelopeInterceptor reconhece este tipo e responde
 * `{ data: [...], meta: { total, limit, offset } }` — `data` continua sendo o
 * array, então quem já consumia a lista não quebra, e `meta.total` diz quantos
 * registros existem além da página.
 */
export class Paginated<T> {
  constructor(
    readonly items: T[],
    readonly total: number,
    readonly limit: number,
    readonly offset: number,
  ) {}

  /**
   * Guarda de tipo para o interceptor. `instanceof` sozinho estreitaria para
   * `Paginated<any>` e espalharia `any` por quem lê os itens; aqui a resposta
   * é `Paginated<unknown>`, que é a verdade — o interceptor não sabe (nem
   * precisa saber) o que a página carrega.
   */
  static is(value: unknown): value is Paginated<unknown> {
    return value instanceof Paginated;
  }

  /** Reaproveita a janela para outra forma de item (ex.: entidade → JSON). */
  map<U>(transform: (item: T) => U): Paginated<U> {
    return new Paginated(this.items.map(transform), this.total, this.limit, this.offset);
  }
}
