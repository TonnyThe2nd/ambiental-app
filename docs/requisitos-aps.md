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
| Mapa interativo e camadas | Implementado | Camadas liga/desliga: ocorrências, áreas de risco (raio de impacto), densidade, mapa de calor do servidor (GeoHash), qualidade do ar (US AQI) e temperatura com destaque de ilhas de calor (Open-Meteo); atalhos "Alagamentos" e "Rotas obstruídas". |
| Relato colaborativo inteligente | Implementado | Foto, categoria validada no servidor, GPS e metadados ambientais (chuva, AQI, temperatura via Open-Meteo) enviados no relato. |
| Alertas de proximidade e roteamento | Implementado | Notificação do sistema ao entrar na área de uma ocorrência com o app aberto, minimizado ou fechado; roteamento preventivo com rotas alternativas avaliadas no PostGIS e alerta de novas ocorrências no corredor da rota. |
| Offline-first | Implementado | Fila Hive, WorkManager, chave de idempotência SHA-256. |

## Correções feitas nas revisões

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

## Alerta de proximidade (entrada em área de ocorrência)

Cada ocorrência tem uma **área de impacto** (`impact_radius_m`), que depende da categoria e
da gravidade: um alagamento moderado ocupa 400 m, uma queimada crítica, 3 km (tabela em
`incidents/domain/impact.py`, espelhada em `incident_impact.dart`). Estar "numa área de
ocorrência" significa estar dentro desse raio, e não dentro do raio de alerta do usuário (10 km).

| Situação do app | Como detecta | Quem notifica |
|---|---|---|
| Aberto ou minimizado | Rastreamento contínuo do GPS (serviço em primeiro plano no Android, com notificação fixa "Monitorando áreas de risco"; atualização em segundo plano no iOS) | O próprio app, com notificação do sistema |
| Fechado (Android) | Tarefa periódica do WorkManager a cada 15 min, com a permissão "Permitir o tempo todo" | O próprio app, a partir do isolate em segundo plano |
| Sem internet | Áreas em cache no Hive (raio de 20 km, renovado a cada 10 min ou 5 km de deslocamento) | O próprio app |
| Ocorrência nova ainda fora do cache | O servidor avalia a posição enviada (`PUT /auth/me/location`) e devolve as entradas | O app, com os dados devolvidos pelo servidor |

A avaliação só notifica na **transição de fora para dentro**, com margem de 50 m para sair
(evita repetição com o GPS oscilando na borda) e no máximo um aviso por ocorrência a cada
6 horas. Como o app notifica, ele envia `localGeofencing: true` e o servidor registra o
histórico sem mandar push, evitando notificação duplicada.

Limites conhecidos: com o app fechado, o Android executa tarefas periódicas no mínimo a cada
15 minutos e pode adiá-las em modo de economia de bateria; no iOS o alerta com o app
encerrado pelo usuário depende do push do servidor.

## Roteamento preventivo

1. No mapa, tocar e segurar sobre o destino e escolher "A pé" ou "Carro".
2. O app busca até 3 rotas alternativas no OSRM (`routing.openstreetmap.de`, configurável por
   `--dart-define=ROUTING_BASE_URL=...`).
3. `POST /routes/assess` cruza cada rota com as ocorrências ativas no PostGIS
   (`ST_DWithin` entre a linha da rota e a área de impacto) e recomenda a de menor risco.
   Alagamento, árvore caída, erosão e fogo pesam o dobro, e uma ocorrência crítica dessas
   marca a rota como bloqueada.
4. "Iniciar rota e receber alertas" envia a rota em `PUT /auth/me/location`; por 2 horas o
   worker avisa sobre novas ocorrências no corredor da rota.

### Segunda revisão (mapa e alertas)

- **Alerta com o app em segundo plano quase nunca funcionava.** A permissão de localização em
  segundo plano era pedida dentro da própria tarefa em segundo plano, onde o Android não
  consegue mostrar o pedido; a checagem falhava em silêncio. Agora a permissão é pedida na
  tela, com explicação e atalho para as configurações.
- **"Entrar na área" usava o raio de alerta do usuário (10 km)**, então qualquer ocorrência da
  cidade contava como "você está na área". Agora usa a área de impacto da ocorrência.
- **O mapa recriava o feed e a conexão a cada filtro ou arrasto**, porque o stream era criado
  dentro do `build`. Agora só é refeito quando o centro se desloca mais de 5 km.
