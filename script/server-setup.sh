#!/usr/bin/env bash
# Legendator Rails — VPS Initial Setup Script
# Run this on a fresh Ubuntu 22.04/24.04 VPS (Hostinger or similar)
# Usage: bash server-setup.sh
set -euo pipefail

APP_DIR="/var/www/legendator"
APP_USER="${USER}"
RUBY_VERSION="3.4.2"
DOMAIN="legendator.com.br"

echo "==> Atualizando sistema..."
sudo apt update && sudo apt upgrade -y

echo "==> Instalando dependências de build..."
sudo apt install -y build-essential libssl-dev libreadline-dev zlib1g-dev \
  libpq-dev libffi-dev libyaml-dev git curl nginx certbot python3-certbot-nginx

# --- Ruby via rbenv ---
echo "==> Instalando rbenv + Ruby ${RUBY_VERSION}..."
if [ ! -d "$HOME/.rbenv" ]; then
  git clone https://github.com/rbenv/rbenv.git ~/.rbenv
  echo 'eval "$(~/.rbenv/bin/rbenv init - bash)"' >> ~/.bashrc
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(~/.rbenv/bin/rbenv init - bash)"
  git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
else
  export PATH="$HOME/.rbenv/bin:$PATH"
  eval "$(~/.rbenv/bin/rbenv init - bash)"
  echo "rbenv já instalado, pulando..."
fi

if ! rbenv versions | grep -q "${RUBY_VERSION}"; then
  rbenv install "${RUBY_VERSION}"
fi
rbenv global "${RUBY_VERSION}"

echo "Ruby $(ruby -v)"

# --- PostgreSQL ---
echo "==> Instalando PostgreSQL..."
sudo apt install -y postgresql postgresql-contrib

echo "==> Criando databases..."
echo "ATENÇÃO: Defina uma senha forte para o banco!"
read -sp "Senha do PostgreSQL para legendator_rails: " DB_PASSWORD
echo

sudo -u postgres psql <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'legendator_rails') THEN
    CREATE USER legendator_rails WITH PASSWORD '${DB_PASSWORD}';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE legendator_rails_production OWNER legendator_rails'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'legendator_rails_production')\gexec

SELECT 'CREATE DATABASE legendator_rails_production_cache OWNER legendator_rails'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'legendator_rails_production_cache')\gexec

SELECT 'CREATE DATABASE legendator_rails_production_queue OWNER legendator_rails'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'legendator_rails_production_queue')\gexec

SELECT 'CREATE DATABASE legendator_rails_production_cable OWNER legendator_rails'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'legendator_rails_production_cable')\gexec
SQL

# --- App directory ---
echo "==> Preparando diretório do app..."
sudo mkdir -p "${APP_DIR}"
sudo chown "${APP_USER}:${APP_USER}" "${APP_DIR}"

echo ""
echo "==> Setup do servidor concluído!"
echo ""
echo "Próximos passos manuais:"
echo "  1. Clone o repo:  git clone <repo-url> ${APP_DIR}"
echo "  2. cd ${APP_DIR}"
echo "  3. Execute:  bash script/app-setup.sh"
echo ""
echo "Guarde estas informações:"
echo "  DB_PASSWORD=${DB_PASSWORD}"
echo "  APP_DIR=${APP_DIR}"
