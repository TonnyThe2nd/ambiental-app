# Fase 3 - Sincronização e Backend

## Objetivo

Conectar o app ao Firebase e implementar as regras de sincronização e processamento em nuvem.

## Entregáveis

- Firestore schema
- Firebase Storage integration
- Cloud Functions
- deduplicação e agregação
- sincronização com retry

## Tarefas

1. Criar coleções Firestore
2. Configurar upload de imagem no Storage
3. Implementar sincronizador para envio
4. Criar `agregarOcorrencia` Cloud Function
5. Implementar `enviarAlertas`
6. Configurar FCM e regras de segurança

## Critérios de aceite

- ocorrências sincronizam com sucesso
- duplicidade reduzida via backend
- alertas enviados para usuários próximos
- regras de security validadas
