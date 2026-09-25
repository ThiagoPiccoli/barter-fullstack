import { Module } from '@nestjs/common';
import { CreditorModule } from '../creditor/creditor.module';
import { InsuranceModule } from '../insurance/insurance.module';
import { SeasonsModule } from '../seasons/seasons.module';
import { BartersController } from './barters.controller';
import { BartersService } from './barters.service';

// Depende de `seasons` porque é a versão vigente do Barter que precifica a
// permuta — o catálogo não decide mais valor nenhum; e de `creditor` porque a
// mesa da cédula devolve a credora junto, para a tela do faturista montar o
// formulário inteiro numa requisição só.
//
// E de `insurance` porque a permuta que nasce num Barter com seguro precisa da
// taxa da praça do produtor para montar a linha do seguro — ver `create`.
@Module({
  imports: [SeasonsModule, CreditorModule, InsuranceModule],
  controllers: [BartersController],
  providers: [BartersService],
})
export class BartersModule {}
