#!/usr/bin/env bash
# Install and start the Legendator systemd service
# Usage: bash script/install-service.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Create .env if it doesn't exist
if [ ! -f "${APP_DIR}/.env" ]; then
  echo "Criando .env — preencha com seus valores:"
  read -sp "LEGENDATOR_RAILS_DATABASE_PASSWORD: " DB_PASS && echo
  read -sp "RAILS_MASTER_KEY: " MASTER_KEY && echo

  cat > "${APP_DIR}/.env" <<EOF
LEGENDATOR_RAILS_DATABASE_PASSWORD=${DB_PASS}
RAILS_MASTER_KEY=${MASTER_KEY}
WEB_CONCURRENCY=2
EOF
  chmod 600 "${APP_DIR}/.env"
  echo ".env criado."
else
  echo ".env já existe, pulando..."
fi

# Install service
sudo cp "${APP_DIR}/config/legendator-web.service" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable legendator-web
sudo systemctl restart legendator-web

echo ""
sudo systemctl status legendator-web --no-pager
echo ""
echo "Servico instalado e rodando."
echo "Logs: sudo journalctl -u legendator-web -f"
