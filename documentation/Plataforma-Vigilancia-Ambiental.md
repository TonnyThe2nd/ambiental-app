# UrbanEye como plataforma de vigilância ambiental

## Decisões implementadas

O fluxo mobile continua local-first: uma ocorrência recebe UUID e chave idempotente estável,
fica no Hive e é sincronizada em segundo plano. A API persiste ocorrência e evento na mesma
transação (transactional outbox); o publicador confirma a entrega no RabbitMQ e aplica backoff.
O consumidor usa filas quorum, retry com TTL, DLQ, chave de evento processado e restrição única
por usuário/incidente. Essa combinação fornece entrega *at least once* sem alertas persistidos duplicados.

A triagem calcula risco de 0 a 100 por categoria, clima/qualidade do ar e proximidade de área
sensível. O resultado auditável classifica `leve`, `moderado` ou `critico` e registra impactos em
saúde pública, ecossistema e comunidade. Estações, hospitais, escolas, rios e unidades de
conservação podem ser cadastrados em `sensitive_areas` com raio de proteção e criticidade.

Alertas consideram localização PostGIS, raio individual, categorias, gravidade mínima e cooldown.
O contexto externo é armazenado em JSON no incidente e as séries normalizadas ficam em
`environmental_observations`, permitindo integrar provedores meteorológicos sem acoplar o domínio
a uma API específica e construir risco histórico regional.

## Componentes e responsabilidades

- Flutter: captura, fila offline, upload e preferências do cidadão.
- API FastAPI: autenticação/RBAC, comandos, consultas, moderação e dashboard.
- PostGIS/geolocalização: distância, áreas sensíveis e hotspots.
- Serviço de eventos: outbox e RabbitMQ; contratos versionados `incident.created.v1`.
- Worker de notificações: filtros geográficos, inbox idempotente, persistência e FCM.
- Análise: regras de risco em `risk_analysis.py`, isoladas para evolução futura.
- Operação: `/health`, `/operations/metrics`, logs estruturáveis por processo e DLQ replayável.

## API operacional

- `PUT /auth/me/alert-preferences`: raio, categorias, severidade mínima e frequência.
- `POST /incidents/{id}/reviews`: fluxo de verificação para moderador/administrador.
- `GET /dashboard/summary?days=30`: recortes, tendência diária e hotspots geográficos.
- `GET /operations/metrics`: backlog/retries da outbox e volume processado (administrador).
- `POST/GET /environmental-observations`: ingestão idempotente e histórico climático/ambiental regional.

Papéis são `cidadao`, `moderador` e `administrador`; novos usuários começam como cidadãos. A
promoção de papel deve ser feita por processo administrativo auditado, não por endpoint público.
O `trust_score` começa em 50 e deixa preparada a evolução por validações confirmadas, qualidade
dos reportes e contribuições. Campanhas e contribuições suportam pontuação, histórico e educação.

## Próximas extensões recomendadas

Executar API, poller e worker separadamente (já definidos no Compose), exportar métricas para
Prometheus/OpenTelemetry, manter um adaptador agendado para fonte climática oficial, criar UI web
consumindo o dashboard e automatizar retenção/replay da DLQ. FCM é opcional localmente e exige
credencial de serviço apenas no worker.
