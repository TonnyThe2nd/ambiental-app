# Funcionalidades prioritárias: arquitetura e operação

## Fluxo distribuído

1. O mobile persiste a ocorrência no Hive antes de tentar enviá-la.
2. A API grava incidente e evento `incident.created.v1` na mesma transação (transactional outbox).
3. O publicador confirma a entrega no RabbitMQ; o worker é idempotente por `eventId`.
4. O worker seleciona usuários por PostGIS, preferências, severidade, cooldown, horário e rota, persiste a notificação e entrega via FCM.
5. Validações comunitárias recalculam confiança/prioridade na mesma transação e emitem `incident.validation.updated.v1` pela outbox.
6. O mapa busca apenas mudanças posteriores ao seu cursor `updated_since` e mescla por ID.

## Alertas inteligentes

O usuário pode configurar raio, categorias, severidade mínima, cooldown e horário silencioso. A localização pode incluir uma linha de rota, um corredor em metros e `routeTtlMinutes` (5–1440 minutos, padrão de 120). Um incidente é elegível quando está no raio da posição ou no corredor de uma rota ainda não expirada. Omitir `route` preserva a rota atual; enviar uma lista vazia remove imediatamente o corredor anterior. Alertas críticos atravessam o horário silencioso; os demais aguardam eventos futuros, evitando interrupções indevidas. A tabela de notificações registra o motivo (`proximity` ou `route`) e o risco usado na decisão.

## Validação comunitária

Cada usuário possui no máximo um voto mutável por incidente e não pode votar no próprio relato. Confirmações, rejeições e complementos são ponderados pelo `trust_score` do participante. A confiança começa neutra em 50, é limitada a 0–100 e compõe a prioridade com o risco ambiental (65% risco, 35% confiança). Limiares promovem o workflow para `validado`, `em_analise` ou `rejeitado`.

## Mapa em tempo real

O endpoint `/incidents` aceita `updated_since`, `categories`, `severities`, `active_only` e `limit`. O app mantém cache por ID, aplica deltas a cada 15 segundos, ordena por prioridade, filtra categoria/severidade e desenha uma camada de densidade por células geográficas. O detalhe do marcador permite confirmar, complementar ou rejeitar.

## Offline e sincronização

A chave idempotente SHA-256 e o ID estável evitam duplicatas no servidor. A fila local usa retry exponencial com jitter e `nextAttemptAt`; itens são ordenados por severidade e prioridade. Em rede móvel, itens não críticos de baixa prioridade são adiados. O trabalho em segundo plano exige rede e bateria não baixa. O backend complementa isso com retry/DLQ no broker e backoff da outbox.

## Operação e evolução

- Aplicar a migração `006_smart_alerts_community_map.sql` antes de publicar API/worker.
- Configurar credenciais Firebase Admin e `FCM_ENABLED=true` para push real.
- Para rotas longas, aplicar simplificação geométrica antes do envio; a validade já é controlada por TTL no servidor.
- Em escala maior, trocar o polling incremental por WebSocket/SSE ou stream de eventos, mantendo o mesmo cursor como mecanismo de recuperação.
- A complementação já aceita comentário/evidência na API; a UI atual envia o voto rápido e pode ganhar formulário de mídia numa iteração posterior.
