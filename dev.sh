#!/bin/bash
# Sobe a stack inteira do Barter de uma vez: API NestJS + app Flutter no
# simulador iOS. A API roda em background; o `flutter run` fica no primeiro
# plano para você continuar usando hot reload (r / R / q).
#
# Uso:
#   ./dev.sh                  # simulador iPhone (auto-detecta o já bootado)
#   ./dev.sh --xcode          # também abre o Runner.xcworkspace no Xcode
#   ./dev.sh --device macos   # roda em outro alvo (macos, chrome, UDID...)
#   ./dev.sh --api-only       # só a API, em primeiro plano
#   ./dev.sh --skip-pods      # pula o pod install quando você sabe que está ok
#
# Ctrl-C (ou sair do flutter run com 'q') derruba a API junto.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="$ROOT/api"
APP_DIR="$ROOT/app"
API_PORT="${PORT:-3333}"
API_LOG="$ROOT/.dev-api.log"

OPEN_XCODE=false
API_ONLY=false
SKIP_PODS=false
DEVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --xcode)     OPEN_XCODE=true; shift ;;
    --api-only)  API_ONLY=true; shift ;;
    --skip-pods) SKIP_PODS=true; shift ;;
    --device|-d) DEVICE="${2:?--device precisa de um valor}"; shift 2 ;;
    -h|--help)   sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "Argumento desconhecido: $1 (use --help)" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$1" >&2; }

# ---------------------------------------------------------------- API

API_PID=""
cleanup() {
  if [[ -n "$API_PID" ]] && kill -0 "$API_PID" 2>/dev/null; then
    step "Derrubando a API (pid $API_PID)"
    # O nest start --watch cria filhos; mata o grupo inteiro.
    kill -- "-$API_PID" 2>/dev/null || kill "$API_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

step "API: dependências e banco"
cd "$API_DIR"
[[ -d node_modules ]] || npm install
[[ -f .env ]] || { cp .env.example .env; warn ".env não existia — copiei de .env.example, confira os valores."; }
npx prisma generate >/dev/null
# Aplica migrations pendentes sem prompt (o migrate dev pode querer resetar).
npx prisma migrate deploy

if lsof -ti "tcp:$API_PORT" >/dev/null 2>&1; then
  warn "Já tem algo escutando na porta $API_PORT — reaproveitando, não vou subir outra API."
else
  if $API_ONLY; then
    step "API em primeiro plano (http://localhost:$API_PORT)"
    exec npm run start:dev
  fi
  step "Subindo a API em background (log: $API_LOG)"
  : > "$API_LOG"
  # setsid-like: roda em process group próprio para o cleanup pegar os filhos.
  set -m
  npm run start:dev >>"$API_LOG" 2>&1 &
  API_PID=$!
  set +m

  printf 'Aguardando http://localhost:%s' "$API_PORT"
  for _ in $(seq 1 60); do
    if curl -sf "http://localhost:$API_PORT" >/dev/null 2>&1; then
      printf ' ok\n'
      break
    fi
    if ! kill -0 "$API_PID" 2>/dev/null; then
      printf '\n'
      warn "A API morreu durante o boot. Últimas linhas do log:"
      tail -30 "$API_LOG" >&2
      exit 1
    fi
    printf '.'
    sleep 1
  done
fi

# ---------------------------------------------------------------- device

if [[ -z "$DEVICE" ]]; then
  step "Procurando simulador iOS"
  # Prioriza um iPhone já bootado; senão pega o primeiro iPhone disponível.
  DEVICE=$(xcrun simctl list devices available \
    | grep -E '^[[:space:]]+iPhone.*\(Booted\)' \
    | sed -n 's/.*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -1)

  if [[ -z "$DEVICE" ]]; then
    DEVICE=$(xcrun simctl list devices available \
      | grep -E '^[[:space:]]+iPhone' \
      | sed -n 's/.*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -1)
    [[ -n "$DEVICE" ]] || { warn "Nenhum simulador iPhone disponível. Instale um pelo Xcode."; exit 1; }
    echo "Bootando $DEVICE..."
    open -a Simulator
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || sleep 5
  else
    echo "Simulador já bootado: $DEVICE"
    open -a Simulator
  fi
fi

# ---------------------------------------------------------------- app

step "App: dependências"
cd "$APP_DIR"
flutter pub get

# pod install só quando o alvo é iOS e algo mudou (Pods ausente ou Podfile
# mais novo que o lock). É o passo lento, não vale rodar sempre.
if [[ "$DEVICE" != "macos" && "$DEVICE" != "chrome" ]] && ! $SKIP_PODS; then
  if [[ ! -d ios/Pods || ios/Podfile -nt ios/Podfile.lock ]]; then
    step "pod install (Podfile mudou ou Pods ausente)"
    (cd ios && pod install)
  fi
fi

if $OPEN_XCODE; then
  step "Abrindo o Xcode"
  open ios/Runner.xcworkspace
fi

step "flutter run -d $DEVICE"
echo "API: http://localhost:$API_PORT  |  log: $API_LOG"
echo ""
flutter run -d "$DEVICE" --dart-define=API_URL="http://localhost:$API_PORT"
