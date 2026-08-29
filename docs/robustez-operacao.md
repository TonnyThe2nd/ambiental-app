# Operação resiliente do UrbanEye

## Configuração

Copie `.env.example` para `.env` e troque `JWT_SECRET`. Em produção, configure também:

- `DATABASE_URL`: conexão PostgreSQL/PostGIS com SSL conforme o provedor.
- `RABBITMQ_URL`: conexão AMQP usada pelo worker e pelo outbox poller.
- `GOOGLE_APPLICATION_CREDENTIALS`: caminho do JSON da service account Firebase montado somente no worker.
- `WORKER_PREFETCH=1`: limita memória e impede que uma instância pequena reserve vários eventos pesados.
- `OUTBOX_BATCH_SIZE=50` e `OUTBOX_POLL_SECONDS=2`: ajuste conservador para plano gratuito.

O app deve enviar `fcmToken` em `PUT /auth/me/location`; a API mantém o token junto à localização geográfica.

## Migrações e execução local

Em uma base nova, o Compose executa todos os SQL em ordem automaticamente:

```bash
docker compose up --build
```

Em uma base existente, execute explicitamente (os scripts são idempotentes):

```bash
docker compose run --rm migrate
docker compose up -d api rabbitmq worker outbox-poller
```

Validações úteis:

```bash
curl http://localhost:8000/ping
curl http://localhost:8000/health
docker compose logs -f api worker outbox-poller
```

O endpoint grava `incidents` e `outbox` em uma transação. O poller usa `FOR UPDATE SKIP LOCKED`, publicação persistente com publisher confirms e remove o evento somente após a confirmação do RabbitMQ. Falhas usam backoff limitado a uma hora.

## Firebase

Crie uma service account no Firebase, mantenha o JSON fora do Git e monte-o no container do worker. Exemplo de trecho de produção:

```yaml
services:
  worker:
    volumes:
      - ./secrets/firebase-service-account.json:/run/secrets/firebase-service-account.json:ro
    environment:
      GOOGLE_APPLICATION_CREDENTIALS: /run/secrets/firebase-service-account.json
```

Cada chamada FCM contém no máximo 500 tokens. Os lotes são paralelos e têm timeout global de 15 segundos. Uma falha/timeout não gera ACK; RabbitMQ aplica retry e, após o limite, DLQ.

## Backup diário

O workflow `.github/workflows/daily-postgres-backup.yml` cria um dump customizado e o envia ao bucket privado `backups` do Supabase. Crie o bucket e configure estes GitHub Actions secrets:

- `DATABASE_URL`
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

Teste manualmente com **Actions → Daily PostgreSQL backup → Run workflow**. Restrinja acesso ao repositório e rotacione a service-role key se houver exposição. Defina também uma política de retenção no bucket para não consumir a cota gratuita indefinidamente.

Restauração:

```bash
pg_restore --clean --if-exists --no-owner --dbname "$DATABASE_URL" urbaneye-AAAA-MM-DD.dump
```

## UptimeRobot

Crie um monitor HTTP(S) apontando para `https://SEU_HOST/ping`, intervalo de 10 minutos, timeout de 15 segundos e status esperado 200. `uptime.json` registra esses parâmetros. `/ping` é liveness barato e não consulta serviços; `/health` verifica o PostgreSQL e deve ser usado por orquestradores.

Planos gratuitos podem proibir ou neutralizar keep-alive e frequentemente não garantem persistência local. Confirme os termos do provedor e não trate o ping como garantia de ausência de cold start.

## Mobile offline-first

O incidente é salvo primeiro no Hive. `workmanager` usa WorkManager no Android e BGTaskScheduler no iOS, exige rede conectada e agenda novas tentativas em 5 minutos, 15 minutos e depois 1 hora. Os sistemas móveis podem adiar tarefas para economizar bateria; os intervalos são mínimos, não horários exatos.

No iOS, adicione `GoogleService-Info.plist`, habilite **Background fetch**, **Background processing** e **Push notifications** no Xcode. No Android, mantenha `google-services.json` e gere o APK com a configuração Firebase correta.
