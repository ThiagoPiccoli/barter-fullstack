import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import type { User } from '@prisma/client';

/** Restringe a rota a administradores. Usar depois do AuthGuard global. */
@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const user = context.switchToHttp().getRequest().user as User | undefined;
    if (user?.role !== 'admin') {
      throw new ForbiddenException('Apenas administradores podem executar esta ação');
    }
    return true;
  }
}
