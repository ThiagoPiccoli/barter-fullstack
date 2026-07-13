import { Body, Controller, Get, HttpCode, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import type { User } from '@prisma/client';
import { CurrentUser, Public } from '../common/decorators';
import { toUserJson } from '../common/serializers';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';

@Controller()
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Post('auth/login')
  @HttpCode(200)
  async login(@Body() dto: LoginDto) {
    const { user, token } = await this.authService.login(dto.email, dto.password);
    return { user: toUserJson(user), token };
  }

  @Post('auth/logout')
  @HttpCode(200)
  async logout(@Req() request: Request & { tokenHash?: string }) {
    if (request.tokenHash) {
      await this.authService.logout(request.tokenHash);
    }
    return { message: 'Logged out successfully' };
  }

  @Get('me')
  me(@CurrentUser() user: User) {
    return toUserJson(user);
  }
}
