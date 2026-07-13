import type { PrismaClient } from '@prisma/client';
import { seedDatabase } from './seed-data';

/**
 * Semeia o banco com o dataset de demonstração APENAS se ele estiver vazio.
 * Chamado na subida do servidor (main.ts) para conveniência de dev: numa
 * máquina nova ou banco recém-criado os dados já aparecem sem passo manual.
 *
 * Não sobrescreve um banco que já tem dados — se você criou/alterou registros
 * testando, eles permanecem entre reinícios. Para voltar ao dataset limpo,
 * rode `npm run db:seed` (que apaga e recria tudo).
 */
export async function seedIfEmpty(prisma: PrismaClient): Promise<boolean> {
  const existing = await prisma.user.count();
  if (existing > 0) {
    return false;
  }
  await seedDatabase(prisma);
  return true;
}
