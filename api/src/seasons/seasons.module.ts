import { Module } from '@nestjs/common';
import { BarterVersionsController } from './barter-versions.controller';
import { SeasonsController } from './seasons.controller';
import { SeasonsService } from './seasons.service';

/**
 * O lançamento do Barter. Dois controllers, um service — o mesmo arranjo de
 * `users/`: safra e versão são portas diferentes para a mesma regra, e separar
 * o service em dois só espalharia a invariante de "uma vigente por vez".
 *
 * Exporta o service porque `barters/` depende dele para precificar a permuta.
 */
@Module({
  controllers: [SeasonsController, BarterVersionsController],
  providers: [SeasonsService],
  exports: [SeasonsService],
})
export class SeasonsModule {}
