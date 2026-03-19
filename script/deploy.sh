#!/usr/bin/env bash
# Legendator Rails — Deploy Script (run on server)
# Usage: bash ~/legendator-rails/script/deploy.sh
set -euo pipefail

APP_DIR="/home/brpl/legendator-rails"
cd "${APP_DIR}"

source /usr/local/rvm/scripts/rvm

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
sleep 5

if curl -sf http://localhost:3001/up > /dev/null 2>&1; then
  echo "==> Deploy OK! App is online."
else
  echo "==> WARNING: Health check failed. Check logs:"
  echo "    sudo journalctl -u legendator-web -n 50 --no-pager"
  exit 1
fi
