# Rastreabilidade: proposta da APS × implementação

Este documento liga cada item da proposta "EcoPulse" (APS de Desenvolvimento de Sistemas
Distribuídos) ao código que o implementa. O nome interno do código continua UrbanEye.

## Modelo do sistema distribuído (seção III da proposta)

| Pilar da proposta | Status | Onde está |
|---|---|---|
| Desacoplamento e mensageria assíncrona (RabbitMQ) | Implementado | `backend/api/src/messaging.py`, `outbox_service.py`, `worker.py` |
| Processamento e particionamento geoespacial (GeoHash) | Implementado | `shared/domain/geohash.py`, migração `013`, cabeçalhos `x-geohash`/`x-geo-partition` nos eventos, `GET /incidents/heatmap` |
| Tolerância a falhas (filas persistentes, retries, DLQ) | Implementado | filas quórum, `incidents.create.retry` (TTL 5 s), `incidents.create.dead`, `replay_dead_letters.py`, outbox com backoff |
| Comunicação bidirecional em tempo real (WebSocket + push por raio) | Implementado | `realtime/` (`/ws/incidents`), FCM no worker e em `alerts/` |
| Cache distribuído (Redis) e consistência eventual com PostgreSQL/PostGIS | Implementado | `shared/infrastructure/cache.py`, invalidação por evento em `realtime/infrastructure/event_listener.py` |

### Como o particionamento geográfico funciona

1. Cada ocorrência recebe um GeoHash de precisão 7 (~150 m) ao ser gravada.
2. O prefixo de 4 caracteres (~39 km × 19,5 km) é a **partição**: vai no cabeçalho AMQP
   `x-geo-partition` e é a chave das assinaturas do WebSocket.
3. Cada instância da API assina `incident.#` com uma fila exclusiva (fan-out entre instâncias)
   e só empurra para cada celular os eventos dos quadrantes que ele assinou.
4. O mapa de calor agrega por prefixo (precisão 3 a 7) com índice `text_pattern_ops` e é
   servido pelo cache Redis. Cada evento incrementa a versão do cache (consistência eventual).

### Protocolo do WebSocket (`/ws/incidents`)

Autenticação por `Authorization: Bearer <jwt>` no handshake (ou `?token=`).

```text
cliente  → {"action": "subscribe", "geohashes": ["6gyf", "6gyc"]}
servidor → {"type": "subscribed", "geohashes": ["6gyc", "6gyf"]}
servidor → {"type": "event", "eventType": "incident.created.v1", "data": {...}}
```

Eventos publicados: `incident.created.v1`, `incident.validation.updated.v1`,
`incident.status.updated.v1` (moderação).

## Funcionalidades mobile (seção IV)

| Funcionalidade | Status | Observação |
|---|---|---|
| Mapa interativo e camadas | Parcial | Marcadores por severidade, filtros e camada de densidade; o backend já expõe o mapa de calor. Camadas de AQI e ilhas de calor no mapa ainda não existem no app. |
| Relato colaborativo inteligente | Implementado | Foto, categoria validada no servidor, GPS e metadados ambientais (chuva, AQI, temperatura via Open-Meteo) enviados no relato. |
| Alertas de proximidade e roteamento | Parcial | Raio, entrada em área e corredor de rota no backend; o app ainda não envia a rota (`route`) em `PUT /auth/me/location`. |
| Offline-first | Implementado | Fila Hive, WorkManager, chave de idempotência SHA-256. |

## Correções feitas nesta revisão

- **Eventos de validação travavam a outbox.** `incident.validation.updated.v1` era publicado com
  `mandatory=True` sem nenhuma fila ligada; o broker devolvia a mensagem e a outbox reagendava
  o evento indefinidamente. Agora só `incident.created.v1` exige consumidor durável, e o
  assinante de tempo real consome todos os eventos `incident.#`.
- **Push perdido na retentativa do worker.** Se o FCM falhasse depois de a notificação ser
  gravada, a reentrega aplicava o cooldown contra a própria notificação e o usuário não recebia
  o push. O cooldown agora ignora notificações do mesmo incidente.
- **Mensagem de push com raio fixo "10 km"**, mesmo com raio configurável. Texto corrigido.
- **Health check da API no Render sempre em 503.** O serviço web não recebia as variáveis do
  RabbitMQ e o `/health` tentava `localhost`. O mesmo ocorria na API do Docker Compose.
- **Categoria livre e contexto ambiental sem validação.** Qualquer texto virava categoria e
  valores não numéricos em `environmentalContext` causavam erro 500 no cálculo de risco.
- **Fotos nunca chegavam ao servidor.** O app guardava a foto só no aparelho; agora ela é enviada
  para `PUT /incidents/{id}/photo` (armazenada no PostgreSQL) e servida em `GET` autenticado.
- **Metadados ambientais nunca eram enviados**, então chuva e AQI não entravam no risco.
- **Intervalo de fallback do feed não era usado.** O mapa consultava a API a cada 15 s mesmo
  com a constante de fallback de 5 minutos definida; agora o tempo real dispara as atualizações
  e a consulta periódica só vale como fallback.
