import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { SessionCleanupService } from './session-cleanup.service';

@Module({
  controllers: [AuthController],
  providers: [AuthService, SessionCleanupService],
})
export class AuthModule {}
