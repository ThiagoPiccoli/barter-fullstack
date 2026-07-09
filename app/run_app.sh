#!/bin/bash
# Abre o simulador iOS (iPhone 17) e roda o app Barter nele.
# Uso: ./run_app.sh

set -e

DEVICE_ID="EB4B44C8-E7C9-423D-AA36-BA9BA8501F0D"
DEVICE_NAME="iPhone 17"

echo "Verificando se o simulador '$DEVICE_NAME' está aberto..."

if ! xcrun simctl list devices booted | grep -q "$DEVICE_ID"; then
  echo "Abrindo o Simulator e iniciando '$DEVICE_NAME'..."
  open -a Simulator
  xcrun simctl boot "$DEVICE_ID"
  sleep 5
else
  echo "Simulador já está aberto."
fi

echo "Rodando o app (aguarde 'Xcode build done.' aparecer)..."
echo ""
flutter run -d "$DEVICE_ID"
