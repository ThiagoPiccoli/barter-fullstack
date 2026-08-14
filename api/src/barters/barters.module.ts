import { Module } from '@nestjs/common';
import { SeasonsModule } from '../seasons/seasons.module';
import { BartersController } from './barters.controller';
import { BartersService } from './barters.service';

// Depende de `seasons` porque é a versão vigente do Barter que precifica a
// permuta — o catálogo não decide mais valor nenhum.
@Module({
  imports: [SeasonsModule],
  controllers: [BartersController],
  providers: [BartersService],
})
export class BartersModule {}
