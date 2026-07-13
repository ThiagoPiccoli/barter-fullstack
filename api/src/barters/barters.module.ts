import { Module } from '@nestjs/common';
import { BartersController } from './barters.controller';
import { BartersService } from './barters.service';

@Module({
  controllers: [BartersController],
  providers: [BartersService],
})
export class BartersModule {}
