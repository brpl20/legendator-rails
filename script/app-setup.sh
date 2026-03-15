#!/usr/bin/env bash
# Legendator Rails — App Setup (run after server-setup.sh and git clone)
# Usage: cd /var/www/legendator && bash script/app-setup.sh
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_USER="${USER}"
DOMAIN="legendator.com.br"

cd "${APP_DIR}"

# --- Verificações ---
if ! command -v ruby &>/dev/null; then
  echo "ERRO: Ruby não encontrado. Execute server-setup.sh primeiro."
  exit 1
fi

if [ -z "${LEGENDATOR_RAILS_DATABASE_PASSWORD:-}" ]; then
  read -sp "Senha do PostgreSQL (LEGENDATOR_RAILS_DATABASE_PASSWORD): " LEGENDATOR_RAILS_DATABASE_PASSWORD
  echo
  export LEGENDATOR_RAILS_DATABASE_PASSWORD
fi

if [ -z "${RAILS_MASTER_KEY:-}" ]; then
  if [ -f config/credentials/production.key ]; then
    export RAILS_MASTER_KEY=$(cat config/credentials/production.key)
  elif [ -f config/master.key ]; then
    export RAILS_MASTER_KEY=$(cat config/master.key)
  else
    echo "ERRO: RAILS_MASTER_KEY não definida e nenhum key file encontrado."
    echo "Copie o production.key para config/credentials/production.key ou exporte RAILS_MASTER_KEY."
    exit 1
  fi
fi

# --- Bundle ---
echo "==> Instalando gems..."
bundle config set --local deployment true
bundle config set --local without 'development test'
bundle install

# --- Database ---
echo "==> Rodando migrations..."
RAILS_ENV=production bin/rails db:prepare

# --- Assets ---
echo "==> Compilando assets..."
RAILS_ENV=production bin/rails assets:precompile

# --- Storage ---
mkdir -p storage

# --- Systemd services ---
echo "==> Configurando systemd services..."

RBENV_RUBY="$(rbenv which ruby | sed 's|/ruby$||')"

sudo tee /etc/systemd/system/legendator-web.service > /dev/null <<EOF
[Unit]
Description=Legendator Rails Web (Thruster + Puma)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=${APP_USER}
WorkingDirectory=${APP_DIR}
Environment=RAILS_ENV=production
Environment=SOLID_QUEUE_IN_PUMA=1
Environment=LEGENDATOR_RAILS_DATABASE_PASSWORD=${LEGENDATOR_RAILS_DATABASE_PASSWORD}
Environment=RAILS_MASTER_KEY=${RAILS_MASTER_KEY}
Environment=WEB_CONCURRENCY=2
ExecStart=${APP_DIR}/bin/thrust ${RBENV_RUBY}/bundle exec puma -C ${APP_DIR}/config/puma.rb
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=legendator-web

[Install]
WantedBy=multi-user.target
EOF

# --- Nginx ---
echo "==> Configurando Nginx..."

sudo tee /etc/nginx/sites-available/legendator > /dev/null <<EOF
upstream legendator {
    server 127.0.0.1:3000;
}

server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};

    root ${APP_DIR}/public;

    # Serve static files directly
    location /assets/ {
        expires max;
        add_header Cache-Control "public, immutable";
        gzip_static on;
    }

    location /storage/ {
        internal;
        alias ${APP_DIR}/storage/;
    }

    # Health check — bypass proxy for monitoring
    location = /up {
        proxy_pass http://legendator;
    }

    location / {
        try_files \$uri @rails;
    }

    location @rails {
        proxy_pass http://legendator;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }

    client_max_body_size 50M;
}
EOF

sudo ln -sf /etc/nginx/sites-available/legendator /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx

# --- Enable services ---
echo "==> Habilitando e iniciando services..."
sudo systemctl daemon-reload
sudo systemctl enable legendator-web
sudo systemctl start legendator-web

echo ""
echo "==> App configurado e rodando!"
echo ""
echo "Verificar status:"
echo "  sudo systemctl status legendator-web"
echo "  curl -s http://localhost:3000/up"
echo ""
echo "Último passo — SSL:"
echo "  sudo certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
echo ""
echo "Deploy futuro:"
echo "  bash script/deploy.sh"
