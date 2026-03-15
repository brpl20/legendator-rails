#!/usr/bin/env bash
# Legendator Rails — Deploy Script (run for updates)
# Usage: cd /var/www/legendator && bash script/deploy.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${APP_DIR}"

echo "==> Pulling latest code..."
git pull origin main

echo "==> Installing gems..."
bundle install

echo "==> Running migrations..."
RAILS_ENV=production bin/rails db:migrate

echo "==> Precompiling assets..."
RAILS_ENV=production bin/rails assets:precompile

echo "==> Restarting app..."
sudo systemctl restart legendator-web

echo "==> Waiting for app to boot..."
sleep 3

if curl -sf http://localhost:3000/up > /dev/null 2>&1; then
  echo "==> Deploy concluído! App está online."
else
  echo "==> AVISO: Health check falhou. Verifique os logs:"
  echo "    sudo journalctl -u legendator-web -n 50 --no-pager"
fi
