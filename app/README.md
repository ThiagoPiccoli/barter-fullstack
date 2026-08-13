# agroBarter (Flutter)

App do agroBarter (permuta de grãos por insumos) integrado à API NestJS deste
repositório (`../api`). Ver o [README raiz](../README.md) para subir tudo e o
[docs/frontend-review.md](../docs/frontend-review.md) para a revisão de
arquitetura.

## Rodando

```bash
# 1) API no ar (noutro terminal):
cd ../api && npm run db:seed && npm run start:dev

# 2) App:
flutter run                                              # simulador/desktop (localhost)
flutter run --dart-define=API_URL=http://192.168.0.10:3333  # aparelho físico (IP da máquina)
flutter run --dart-define=API_URL=http://10.0.2.2:3333      # emulador Android
```

Login de demonstração: `admin@agrobarter.com.br` / `123456` (admin) ou
`joao.silva@agrobarter.com.br` / `123456` (consultor).

## Camadas

- `lib/services/api/api_client.dart` — HTTP + token + erros (`ApiException`)
- `lib/repositories/` — um repositório por recurso (HTTP → modelos)
- `lib/data/app_data.dart` — cache em memória carregado no login; telas leem
  de forma síncrona e toda mutação passa pela API
- `lib/screens/`, `lib/widgets/`, `lib/theme/` — UI

## Testes

```bash
flutter test                                             # widgets
flutter test integration_test/app_flow_test.dart -d macos  # E2E (exige API + seed fresco)
```

O teste E2E percorre login de 3 usuários, o escopo das carteiras e cria uma
permuta real no servidor (PRM-2026-009) — re-rode o seed para zerar o banco.
