import { Module } from '@nestjs/common';
import { CreditorController } from './creditor.controller';
import { CreditorService } from './creditor.service';

/**
 * O service é EXPORTADO porque `barters` o consome: a mesa da cédula devolve a
 * credora junto, para a tela do faturista montar o formulário inteiro numa
 * requisição só.
 */
@Module({
  controllers: [CreditorController],
  providers: [CreditorService],
  exports: [CreditorService],
})
export class CreditorModule {}
