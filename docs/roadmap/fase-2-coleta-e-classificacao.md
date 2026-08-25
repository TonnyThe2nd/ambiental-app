# Fase 2 - Coleta e Classificação

## Objetivo

Implementar os componentes de câmera, localização, inferência e persistência local.

## Entregáveis

- camera service
- location service
- TFLite classifier
- salvamento local em fila offline
- classificação e metadados da ocorrência

## Tarefas

1. Implementar captura de imagem
2. Redimensionar para 224x224
3. Integrar TensorFlow Lite MobileNetV2
4. Gerar categoria e confiança
5. Capturar GPS e timestamp
6. Persistir ocorrência pendente em SQLite/Hive
7. Criar fila de retry e sincronização

## Critérios de aceite

- foto capturada e processada localmente
- categoria classificada com score
- ocorrência salva mesmo offline
- fila sincronizável em rede disponível
