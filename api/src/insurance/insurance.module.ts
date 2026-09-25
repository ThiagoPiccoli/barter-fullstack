import { Module } from '@nestjs/common';
import { SeasonsModule } from '../seasons/seasons.module';
import { InsuranceController } from './insurance.controller';
import { InsuranceService } from './insurance.service';

/**
 * A base de seguros por município.
 *
 * Depende de `seasons` por um motivo só: a cotação da saca do Barter vigente, que
 * é o que converte R$/ha em sacas/ha para quem não vê valores.
 *
 * Exporta o service porque `barters/` o consulta no registro da permuta — é lá
 * que a taxa da praça do produtor vira a linha do seguro.
 */
@Module({
  imports: [SeasonsModule],
  controllers: [InsuranceController],
  providers: [InsuranceService],
  exports: [InsuranceService],
})
export class InsuranceModule {}
