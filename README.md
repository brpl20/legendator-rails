# Legendator Rails

Web application for translating SRT subtitles using AI, with PIX payment integration (Banco Inter).

## Architecture

```
Upload .srt -> Calculate cost -> Generate PIX QR -> Payment confirmed -> Translate -> Download
```

- **legendator-gem** handles AI translation (chunking, fallback, consistency check)
- **legendator-rails** handles the web flow, payments, and job processing

## Requirements

- Ruby 3.1+
- PostgreSQL
- Rails 8.1+
- Banco Inter API credentials (mTLS certificates)
- OpenRouter API key (or OpenAI)

## Setup

```sh
bundle install
rails db:create db:migrate
```

### Environment variables

Copy `.env.example` to `.env` and fill in:

```
INTER_BASE_URL=https://cdpj.partners.bancointer.com.br
INTER_CLIENT_ID=your-client-id
INTER_CLIENT_SECRET=your-client-secret
INTER_CHAVE_PIX=your-pix-key
INTER_CERT_PATH=inter/certificate.crt
INTER_KEY_PATH=inter/key.key
```

### Rails credentials

```sh
rails credentials:edit
```

Required keys:

```yaml
openrouter:
  api_key: sk-or-...

openai:
  api_key: sk-...  # used as fallback provider

pricing:
  markup_percentage: 200
  financial_markup: 10
  minimum_brl: 1.00
  fallback_exchange_rate: 5.50
```

## AI Provider Fallback

The app is configured with a 4-level fallback cascade. Each level retries 3 times with exponential backoff before moving to the next:

```
1. OpenRouter / GPT-4.1 Mini (primary)
   2. OpenRouter / Gemini 2.5 Flash
      3. OpenRouter / DeepSeek V3
         4. OpenAI direct / GPT-4.1 Mini
```

If the entire cascade fails, the job retries 3 more times via ActiveJob. Total: up to 36 attempts before marking as failed.

Configuration in `config/initializers/legendator.rb`.

## Running tests

```sh
bundle exec rspec
```

## Deployment

Deployed via Kamal (Docker). See `config/deploy.yml`.

```sh
kamal setup    # first deploy
kamal deploy   # subsequent deploys
```

## Production Checklist

Items already implemented:

- [x] AI provider fallback cascade (4 providers)
- [x] Retry with exponential backoff in AI client
- [x] ActiveJob retry on transient translation failures
- [x] Payment idempotency (duplicate webhooks don't re-enqueue jobs)
- [x] Payment expiration check before confirmation
- [x] Exchange rate API timeout (5s) with fallback rate
- [x] Consistency checker on translated output
- [x] Webhook txid validation

Pending items for future hardening:

- [ ] Webhook signature verification from Banco Inter (requires Inter API docs on HMAC signatures)
- [ ] Error monitoring/alerting integration (Sentry, Rollbar, or similar)
- [ ] Rate limiting on upload and webhook endpoints (Rack::Attack)
- [ ] Email notification when translation completes (mailer exists but is not wired up)
- [ ] Admin dashboard for viewing translations, payments, and error rates
- [ ] File lifecycle management (auto-purge translated files after N days)
- [ ] CDN for static assets in production
- [ ] Database connection pool tuning for concurrent jobs

**Important:** Before deploying, push the gem changes to GitHub and update the Gemfile from `path:` back to `git:` source.
