# UrbanEye

Sistema colaborativo de monitoramento ambiental urbano.

> A arquitetura distribuída, o modelo de risco, moderação, alertas por proximidade e operação
> estão descritos em [documentation/Plataforma-Vigilancia-Ambiental.md](documentation/Plataforma-Vigilancia-Ambiental.md).

## Visão geral

Aplicativo mobile em Flutter para reportar ocorrências ambientais urbanas com foto, geolocalização e classificação manual pelo usuário. Os dados são sincronizados com Firebase e visualizados em mapa interativo.

## Estrutura do projeto

```text
aps/
├── README.md
├── documentation/
│   └── Documento-de-Arquitetura-de-Software-UrbanEye.md
├── apps/
│   └── mobile/
│       ├── lib/
│       │   ├── app/
│       │   ├── core/
│       │   ├── features/
│       │   ├── services/
│       │   ├── models/
│       │   ├── repositories/
│       │   └── main.dart
│       ├── test/
│       ├── assets/
│       ├── pubspec.yaml
│       └── analysis_options.yaml
├── backend/
│   ├── functions/
│   │   ├── src/
│   │   ├── package.json
│   │   └── firebase.json
│   └── firebase/
│       ├── firestore/
│       │   ├── schema/
│       │   └── indexes/
│       ├── storage/
│       ├── auth/
│       └── rules/
├── docs/
│   ├── architecture/
│   └── roadmap/
├── scripts/
│   ├── setup.sh
│   └── deploy.sh
└── .gitignore
```

## Fases de desenvolvimento

### Fase 1 - Fundação da base
- setup do projeto Flutter
- estrutura de diretórios e módulos
- configuração de dependências
- autenticação básica e arquitetura inicial

### Fase 2 - Coleta e classificação manual
- camera service
- location service
- seleção manual de categoria pela interface
- persistência local e fila offline

### Fase 3 - Sincronização e backend
- Firebase Storage e Firestore
- Cloud Functions
- sincronização de ocorrências
- deduplicação e confirmação

### Fase 4 - Visualização e alertas
- mapa interativo e marcadores
- notificações FCM
- filtros por categoria e proximidade

### Fase 5 - Produção e qualidade
- testes unitários e de integração
- observabilidade
- otimização de performance
- deploy e documentação final

## Tecnologias principais

- Flutter / Dart
- Firebase Firestore, Storage, Auth, FCM
- Cloud Functions
- Google Maps Platform
- SQLite / Hive
- Git + GitHub

## Próximo passo

A estrutura inicial foi criada para evoluir para o desenvolvimento real do app, backend e infraestrutura.
