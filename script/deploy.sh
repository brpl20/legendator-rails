#!/usr/bin/env bash
# Legendator Rails — Deploy Script (run on server)
# Usage: bash ~/legendator-rails/script/deploy.sh

APP_DIR="/home/brpl/legendator-rails"
cd "${APP_DIR}"

export PATH="/usr/local/rvm/rubies/ruby-3.4.4/bin:/usr/local/rvm/gems/ruby-3.4.4/bin:/usr/local/bin:/usr/bin:/bin"
export GEM_HOME="/usr/local/rvm/gems/ruby-3.4.4"
export GEM_PATH="/usr/local/rvm/gems/ruby-3.4.4:/usr/local/rvm/gems/ruby-3.4.4@global"

set -eo pipefail

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

if curl -sf -o /dev/null -w "%{http_code}" http://localhost:3001/ | grep -q "200\|301\|302"; then
  echo "==> Deploy OK! App is online."
else
  echo "==> WARNING: Health check failed. Check logs:"
  echo "    sudo journalctl -u legendator-web -n 50 --no-pager"
  exit 1
fi
