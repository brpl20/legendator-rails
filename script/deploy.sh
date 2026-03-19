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
for i in 1 2 3 4 5 6; do
  sleep 3
  HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" http://localhost:3001/ 2>/dev/null || true)
  if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
    echo "==> Deploy OK! App is online (HTTP $HTTP_CODE)."
    exit 0
  fi
  echo "    Attempt $i: HTTP $HTTP_CODE, retrying..."
done
echo "==> WARNING: Health check failed. Check logs:"
echo "    sudo journalctl -u legendator-web -n 50 --no-pager"
exit 1
