# Fase 2 - Coleta e Classificação

## Objetivo

Implementar os componentes de câmera, localização, seleção manual de categoria e persistência local.

## Entregáveis

- camera service
- location service
- fluxo de seleção manual de categoria
- salvamento local em fila offline
- metadados e validação da ocorrência

## Tarefas

1. Implementar captura de imagem
2. Definir categorias de ocorrência disponíveis
3. Criar seleção manual pela interface do usuário
4. Capturar GPS e timestamp
5. Persistir ocorrência pendente em SQLite/Hive
6. Criar fila de retry e sincronização

## Critérios de aceite

- foto capturada e validada
- categoria escolhida manualmente pelo usuário
- ocorrência salva mesmo offline
- fila sincronizável em rede disponível
