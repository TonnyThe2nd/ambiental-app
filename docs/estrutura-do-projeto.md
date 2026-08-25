# Organização das Pastas e Arquivos do Projeto UrbanEye

## Visão geral

Este documento descreve a estrutura proposta para o projeto UrbanEye, cobrindo a organização do código do aplicativo mobile, do backend em Firebase, dos módulos de infraestrutura, dos scripts de suporte e da documentação técnica.

A estrutura foi pensada para facilitar:

- manutenção do código;
- evolução por módulos e features;
- separação de responsabilidades;
- desenvolvimento em equipe;
- integração com Flutter, Firebase e Google Maps;
- versionamento e deploy disciplinado.

---

## Estrutura do repositório

```text
aps/
├── README.md
├── .gitignore
├── documentation/
│   └── Documento-de-Arquitetura-de-Software-UrbanEye.md
├── apps/
│   └── mobile/
│       ├── android/
│       ├── ios/
│       ├── lib/
│       │   ├── app/
│       │   │   ├── app.dart
│       │   │   ├── routes/
│       │   │   │   └── app_routes.dart
│       │   │   ├── theme/
│       │   │   │   ├── app_theme.dart
│       │   │   │   └── colors.dart
│       │   │   └── bootstrap/
│       │   │       └── app_initializer.dart
│       │   ├── core/
│       │   │   ├── config/
│       │   │   │   ├── app_config.dart
│       │   │   │   ├── firebase_options.dart
│       │   │   │   └── environment.dart
│       │   │   ├── constants/
│       │   │   │   ├── app_constants.dart
│       │   │   │   └── error_messages.dart
│       │   │   ├── exceptions/
│       │   │   │   ├── app_exception.dart
│       │   │   │   └── network_exception.dart
│       │   │   ├── utils/
│       │   │   │   ├── date_utils.dart
│       │   │   │   ├── location_utils.dart
│       │   │   │   └── validators.dart
│       │   │   ├── services/
│       │   │   │   ├── connectivity_service.dart
│       │   │   │   └── logger_service.dart
│       │   │   └── widgets/
│       │   │       ├── app_loader.dart
│       │   │       └── empty_state.dart
│       │   ├── features/
│       │   │   ├── auth/
│       │   │   │   ├── data/
│       │   │   │   │   ├── datasources/
│       │   │   │   │   │   └── auth_remote_data_source.dart
│       │   │   │   │   ├── models/
│       │   │   │   │   │   └── user_model.dart
│       │   │   │   │   └── repositories/
│       │   │   │   │       └── auth_repository.dart
│       │   │   │   ├── domain/
│       │   │   │   │   ├── entities/
│       │   │   │   │   │   └── user.dart
│       │   │   │   │   └── usecases/
│       │   │   │   │       └── sign_in_usecase.dart
│       │   │   │   └── presentation/
│       │   │   │       ├── pages/
│       │   │   │       │   └── login_page.dart
│       │   │   │       ├── controllers/
│       │   │   │       │   └── auth_controller.dart
│       │   │   │       └── widgets/
│       │   │   │           └── auth_form.dart
│       │   │   ├── home/
│       │   │   │   ├── presentation/
│       │   │   │   │   └── pages/
│       │   │   │   │       └── home_page.dart
│       │   │   │   └── widgets/
│       │   │   │       └── bottom_nav.dart
│       │   │   ├── camera/
│       │   │   │   ├── data/
│       │   │   │   │   ├── datasources/
│       │   │   │   │   │   └── camera_data_source.dart
│       │   │   │   │   └── repositories/
│       │   │   │   │       └── camera_repository.dart
│       │   │   │   ├── domain/
│       │   │   │   │   ├── entities/
│       │   │   │   │   │   └── incident_photo.dart
│       │   │   │   │   └── usecases/
│       │   │   │   │       └── capture_photo_usecase.dart
│       │   │   │   └── presentation/
│       │   │   │       ├── pages/
│       │   │   │       │   └── camera_page.dart
│       │   │   │       └── controllers/
│       │   │   │           └── camera_controller.dart
│       │   │   ├── incident/
│       │   │   │   ├── data/
│       │   │   │   │   ├── models/
│       │   │   │   │   │   └── incident_model.dart
│       │   │   │   │   ├── datasources/
│       │   │   │   │   │   └── incident_remote_data_source.dart
│       │   │   │   │   └── repositories/
│       │   │   │   │       └── incident_repository.dart
│       │   │   │   ├── domain/
│       │   │   │   │   ├── entities/
│       │   │   │   │   │   └── incident.dart
│       │   │   │   │   ├── usecases/
│       │   │   │   │   │   ├── create_incident_usecase.dart
│       │   │   │   │   │   └── sync_incidents_usecase.dart
│       │   │   │   │   └── validators/
│       │   │   │   │       └── incident_validator.dart
│       │   │   │   └── presentation/
│       │   │   │       ├── pages/
│       │   │   │       │   ├── incident_form_page.dart
│       │   │   │       │   └── incident_detail_page.dart
│       │   │   │       ├── controllers/
│       │   │   │       │   └── incident_controller.dart
│       │   │   │       └── widgets/
│       │   │   │           └── incident_card.dart
│       │   │   ├── map/
│       │   │   │   ├── data/
│       │   │   │   │   └── repositories/
│       │   │   │   │       └── map_repository.dart
│       │   │   │   ├── presentation/
│       │   │   │   │   ├── pages/
│       │   │   │   │   │   └── map_page.dart
│       │   │   │   │   └── controllers/
│       │   │   │   │       └── map_controller.dart
│       │   │   │   └── widgets/
│       │   │   │       └── incident_markers.dart
│       │   │   ├── notifications/
│       │   │   │   ├── data/
│       │   │   │   │   └── services/
│       │   │   │   │       └── notification_service.dart
│       │   │   │   └── presentation/
│       │   │   │       └── pages/
│       │   │   │           └── notifications_page.dart
│       │   │   └── settings/
│       │   │       └── presentation/
│       │   │           └── pages/
│       │   │               └── settings_page.dart
│       │   ├── services/
│       │   │   ├── classification/
│       │   │   │   └── category_service.dart
│       │   │   ├── camera/
│       │   │   │   └── camera_service.dart
│       │   │   ├── location/
│       │   │   │   └── location_service.dart
│       │   │   ├── sync/
│       │   │   │   ├── sync_service.dart
│       │   │   │   ├── sync_queue.dart
│       │   │   │   └── retry_policy.dart
│       │   │   ├── firebase/
│       │   │   │   ├── firestore_service.dart
│       │   │   │   ├── storage_service.dart
│       │   │   │   └── firebase_auth_service.dart
│       │   │   └── push/
│       │   │       └── fcm_service.dart
│       │   ├── models/
│       │   │   ├── occurrence_model.dart
│       │   │   ├── user_model.dart
│       │   │   └── local_occurrence_model.dart
│       │   ├── repositories/
│       │   │   ├── local/
│       │   │   │   ├── local_occurrence_repository.dart
│       │   │   │   └── local_database.dart
│       │   │   ├── remote/
│       │   │   │   ├── occurrence_remote_repository.dart
│       │   │   │   └── firebase_repository.dart
│       │   │   └── abstractions/
│       │   │       ├── occurrence_repository.dart
│       │   │       └── user_repository.dart
│       │   ├── main.dart
│       │   ├── app_initializer.dart
│       │   └── injection.dart
│       ├── test/
│       │   ├── unit/
│       │   │   ├── services/
│       │   │   ├── repositories/
│       │   │   └── models/
│       │   ├── widget/
│       │   │   └── screens/
│       │   └── integration/
│       │       └── app_flow_test.dart
│       ├── assets/
│       │   ├── images/
│       │   │   ├── icons/
│       │   │   └── splash/
│       │   ├── categories/
│       │   │   └── incident_categories.json
│       │   └── fonts/
│       ├── pubspec.yaml
│       ├── analysis_options.yaml
│       └── README.md
│
├── backend/
│   ├── functions/
│   │   ├── src/
│   │   │   ├── index.ts
│   │   │   ├── triggers/
│   │   │   │   ├── occurrence_trigger.ts
│   │   │   │   └── alerts_trigger.ts
│   │   │   ├── services/
│   │   │   │   ├── occurrence_service.ts
│   │   │   │   ├── deduplication_service.ts
│   │   │   │   └── notification_service.ts
│   │   │   ├── utils/
│   │   │   │   ├── geo_utils.ts
│   │   │   │   └── validators.ts
│   │   │   └── config/
│   │   │       └── firebase.ts
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── firebase.json
│   │   └── .eslintrc.json
│   └── firebase/
│       ├── firestore/
│       │   ├── schema/
│       │   │   ├── ocorrencias.schema.json
│       │   │   ├── usuarios.schema.json
│       │   │   └── logs.schema.json
│       │   ├── indexes/
│       │   │   └── firestore.indexes.json
│       │   └── seed/
│       │       └── seed_data.json
│       ├── storage/
│       │   ├── rules/
│       │   │   └── storage.rules
│       │   └── folders/
│       │       └── README.md
│       ├── auth/
│       │   └── README.md
│       └── rules/
│           └── firestore.rules
│
├── docs/
│   ├── architecture/
│   │   ├── arquitetura-geral.md
│   │   └── diagramas.md
│   ├── roadmap/
│   │   ├── fase-1-fundacao.md
│   │   ├── fase-2-coleta-e-classificacao.md
│   │   ├── fase-3-sincronizacao-e-backend.md
│   │   └── fase-4-mapa-e-alertas.md
│   └── estrutura-do-projeto.md
├── scripts/
│   ├── setup.sh
│   ├── deploy.sh
│   ├── bootstrap_firebase.sh
│   └── generate_model_assets.sh
├── documentation/
│   └── Documento-de-Arquitetura-de-Software-UrbanEye.md
└── .github/
    ├── workflows/
    │   ├── ci.yml
    │   └── cd.yml
    └── pull_request_template.md
```

---

## Descrição das pastas principais

### 1) Raiz do projeto

A raiz do repositório deve concentrar:

- `README.md`: visão geral do projeto e guia inicial;
- `.gitignore`: arquivos e diretórios a serem ignorados pelo Git;
- `documentation/`: arquivos de arquitetura e documentação de negócio;
- `apps/`: aplicação mobile e demais projetos de cliente;
- `backend/`: infraestrutura e regras do backend em nuvem;
- `docs/`: documentação técnica e roadmap do desenvolvimento;
- `scripts/`: automações para setup, deploy e manutenção;
- `.github/`: templates e pipelines de integração contínua.

### 2) Pasta `apps/mobile`

É a principal pasta da aplicação Flutter. Ela deve manter todo o pacote mobile isolado e separado das demais camadas do sistema.

#### Estrutura interna

- `lib/`: código principal da aplicação;
- `android/` e `ios/`: configurações nativas do Flutter;
- `test/`: testes unitários, de widget e integração;
- `assets/`: imagens, fontes e recursos do app;
- `pubspec.yaml`: dependências e configuração do Flutter;
- `analysis_options.yaml`: regras de lint e qualidade do código;
- `README.md`: instruções específicas para execução do app.

#### Organização por módulos

A estrutura dentro de `lib/` segue uma lógica modular em camadas:

- `app/`: configuração da aplicação, rotas e tema;
- `core/`: utilitários, configurações globais, serviços base e widgets reutilizáveis;
- `features/`: módulos funcionais do sistema, cada um com sua própria divisão em `data`, `domain`, `presentation`;
- `services/`: serviços de câmera, geolocalização, Firebase, sincronização, ML e notificações;
- `models/`: modelos de domínio e DTOs;
- `repositories/`: abstrações e implementações de acesso a dados;
- `main.dart`: ponto de entrada da aplicação.

### 3) Pasta `backend/functions`

Contém a lógica serverless em TypeScript/Node.js para Cloud Functions do Firebase.

#### Funções esperadas

- `agregarOcorrencia`: deduplicação e agregação de ocorrências;
- `enviarAlertas`: disparo de notificações para usuários próximos;
- `atualizarContadorConfirmacoes`: incrementa confirmações e consolida estado;
- `processarLogs`: centralização de auditoria e observabilidade.

#### Arquivos típicos

- `index.ts`: ponto de entrada das funções;
- `src/triggers/`: gatilhos de Firestore e eventos de autenticação;
- `src/services/`: lógica de domínio do backend;
- `src/utils/`: utilidades geográficas, validações e helpers.
- `package.json`: dependências e scripts do backend.
- `tsconfig.json`: configuração TypeScript.

### 4) Pasta `backend/firebase`

Representa a parte de configuração e regras de infraestrutura do Firebase.

#### Firestore

- `schema/`: definições dos documentos e coleções;
- `indexes/`: índices necessários para consultas de geolocalização e filtros;
- `seed/`: dados iniciais para ambiente de desenvolvimento.

#### Storage

- `rules/`: regras de acesso e segurança para upload/download de imagens;
- `folders/`: organização de buckets e arquivos de referência.

#### Auth e Rules

- `auth/`: documentação e regras de autenticação;
- `rules/`: regras do Firestore e do Storage.

### 5) Pasta `docs`

Arquiva toda a documentação técnica e roadmap do projeto.

- `architecture/`: documentação de arquitetura e diagramas;
- `roadmap/`: fases de desenvolvimento;
- `estrutura-do-projeto.md`: organização da estrutura atual do repositório.

### 6) Pasta `scripts`

Contém automações e utilitários para facilitar setup e deploy.

- `setup.sh`: prepara o ambiente local;
- `deploy.sh`: automatiza deploy e operações de infraestrutura;
- `bootstrap_firebase.sh`: cria base do Firebase;
- `generate_categories_assets.sh`: prepara o catálogo de categorias do app.

---

## Convenções de nomeação

Para manter o projeto sustentável, a organização segue as seguintes convenções:

- módulos em inglês;
- arquivos com nomes descritivos e em camelCase ou snake_case, conforme padrão do ecossistema;
- pastas por feature em vez de por tipo de arquivo;
- separação clara entre `data`, `domain`, `presentation` em cada feature;
- nomenclatura consistente para repositórios, serviços e controladores.

### Exemplos

- `camera_service.dart`
- `incident_repository.dart`
- `map_page.dart`
- `agregarOcorrencia.ts`
- `firestore.rules`

---

## Arquivos essenciais esperados

### Mobile

- `main.dart`
- `app.dart`
- `firebase_options.dart`
- `category_service.dart`
- `location_service.dart`
- `sync_service.dart`
- `incident_model.dart`
- `local_database.dart`

### Backend

- `index.ts`
- `occurrence_trigger.ts`
- `alerts_trigger.ts`
- `deduplication_service.ts`
- `notification_service.ts`
- `firestore.rules`
- `storage.rules`

### Infraestrutura

- `pubspec.yaml`
- `package.json`
- `firebase.json`
- `tsconfig.json`
- `firestore.indexes.json`

---

## Filosofia de organização

A estrutura do projeto foi desenhada para refletir o padrão de desenvolvimento em aplicações modernas com Flutter + Firebase:

1. separação por feature;
2. isolamento do backend e do app;
3. centralização de documentação técnica e roadmap;
4. manutenção de dados locais, remotos e de sincronização em módulos distintos;
5. flexibilidade para testes, deploy e evolução de infra.

Essa organização permite que o time evolua o projeto em fases sem misturar responsabilidades, reduzindo acoplamento e tornando a manutenção mais segura.

---

## Próximo passo prático

A estrutura atual já está preparada para receber o desenvolvimento real do projeto. O próximo passo recomendável é:

- criar o app Flutter em `apps/mobile` com `flutter create`;
- configurar `pubspec.yaml` com dependências do Firebase, Google Maps e geolocator;
- criar o primeiro conjunto de módulos de domínio e do backend serverless.

Com isso, a organização proposta passa de um esquema documental para uma base operacional de desenvolvimento.
