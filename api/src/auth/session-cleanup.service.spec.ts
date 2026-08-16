import type { PrismaService } from '../prisma/prisma.service';
import { SessionCleanupService } from './session-cleanup.service';

/**
 * A FAXINA das sessões mortas.
 *
 * O que se testa aqui não é a segurança — o AuthGuard já recusa sessão vencida
 * antes de esta classe existir. É a SOBRA: a sessão que ninguém tenta usar de
 * novo (aparelho trocado, app desinstalado, consultor que saiu) nunca é
 * visitada pelo guard e ficaria no banco para sempre.
 */
describe('faxina de sessões', () => {
  /** O filtro que a faxina monta — é o que estes testes conferem. */
  interface DeleteWhere {
    where: { OR: [{ expiresAt: { lte: Date } }, { lastUsedAt: { lte: Date } }] };
  }

  const prismaComDeleteMany = (result: { count: number } | Error) => {
    const deleteMany = jest.fn((_args: DeleteWhere) =>
      result instanceof Error ? Promise.reject(result) : Promise.resolve(result),
    );
    return { prisma: { accessToken: { deleteMany } } as unknown as PrismaService, deleteMany };
  };

  it('apaga o que venceu por prazo E o que ficou parado', async () => {
    const { prisma, deleteMany } = prismaComDeleteMany({ count: 3 });

    const removidas = await new SessionCleanupService(prisma).sweep();

    expect(removidas).toBe(3);
    const { where } = deleteMany.mock.calls[0][0];
    // Os dois critérios são os mesmos do AuthGuard. Se divergissem, existiria
    // sessão que a faxina apaga e o guard aceitaria — ou o contrário.
    expect(where.OR).toHaveLength(2);
    expect(where.OR[0].expiresAt.lte).toBeInstanceOf(Date);
    expect(where.OR[1].lastUsedAt.lte).toBeInstanceOf(Date);
  });

  /**
   * Banco fora do ar não pode derrubar o servidor por causa da faxina: ela roda
   * de novo em seis horas e nada depende de ela ter rodado. O erro vira log.
   */
  it('falha do banco não escapa da faxina', async () => {
    const { prisma } = prismaComDeleteMany(new Error('conexão recusada'));

    await expect(new SessionCleanupService(prisma).sweep()).resolves.toBe(0);
  });

  /**
   * O temporizador precisa ser `unref`: sem isso a suíte de testes e qualquer
   * `Ctrl+C` ficariam seis horas esperando o próximo ciclo.
   */
  it('o temporizador não segura o processo de pé', () => {
    const { prisma } = prismaComDeleteMany({ count: 0 });
    const service = new SessionCleanupService(prisma);
    const unref = jest.spyOn(global, 'setInterval');

    service.onModuleInit();
    const timer = unref.mock.results[0].value as NodeJS.Timeout;
    expect(timer.hasRef()).toBe(false);

    service.onModuleDestroy();
    unref.mockRestore();
  });
});
