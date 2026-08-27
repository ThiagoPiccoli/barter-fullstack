import { Body, Controller, Get, HttpCode, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import type { User } from '@prisma/client';
import { Throttle } from '@nestjs/throttler';
import { AllowProvisionalPassword, AnyRole, CurrentUser, Public } from '../common/decorators';
import { toUserJson, type UserWithManager } from '../common/serializers';
import { loginThrottle } from '../common/throttling';
import { AuthService } from './auth.service';
import { ChangePasswordDto, LoginDto } from './dto/login.dto';

@Controller()
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Throttle(loginThrottle)
  @Post('auth/login')
  @HttpCode(200)
  async login(@Body() dto: LoginDto) {
    const { user, token } = await this.authService.login(dto.email, dto.password);
    return { user: toUserJson(user), token };
  }

  /** Desistir e sair precisa funcionar mesmo com a senha ainda provisória. */
  @AllowProvisionalPassword()
  @AnyRole()
  @Post('auth/logout')
  @HttpCode(200)
  async logout(@Req() request: Request & { tokenHash?: string }) {
    if (request.tokenHash) {
      await this.authService.logout(request.tokenHash);
    }
    return { message: 'Logged out successfully' };
  }

  /** É por aqui que o app descobre que a senha ainda é provisória. */
  @AllowProvisionalPassword()
  @AnyRole()
  @Get('me')
  me(@CurrentUser() user: UserWithManager) {
    return toUserJson(user);
  }

  /**
   * Troca da própria senha — o caminho que tira o usuário da senha provisória.
   * Derruba as outras sessões e mantém a atual, então quem troca continua
   * usando o app sem refazer login.
   */
  @AllowProvisionalPassword()
  @AnyRole()
  @Post('auth/password')
  @HttpCode(200)
  async changePassword(
    @CurrentUser() user: User,
    @Body() dto: ChangePasswordDto,
    @Req() request: Request & { tokenHash?: string },
  ) {
    const updated = await this.authService.changePassword(
      user,
      dto.currentPassword,
      dto.newPassword,
      request.tokenHash,
    );
    return toUserJson(updated);
  }
}
