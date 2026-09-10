import { Module } from '@nestjs/common';
import { CreditorModule } from '../creditor/creditor.module';
import { SeasonsModule } from '../seasons/seasons.module';
import { BartersController } from './barters.controller';
import { BartersService } from './barters.service';

// Depende de `seasons` porque é a versão vigente do Barter que precifica a
// permuta — o catálogo não decide mais valor nenhum; e de `creditor` porque a
// mesa da cédula devolve a credora junto, para a tela do faturista montar o
// formulário inteiro numa requisição só.
@Module({
  imports: [SeasonsModule, CreditorModule],
  controllers: [BartersController],
  providers: [BartersService],
})
export class BartersModule {}
