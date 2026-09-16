# Arquitetura DDD do UrbanEye

## Objetivo

O UrbanEye adota um **monólito modular** no backend e módulos orientados a feature no aplicativo. DDD aqui significa proteger regras de negócio da API, banco, mensageria, Firebase e Flutter; não significa criar microserviços prematuramente.

## Contextos delimitados

| Contexto | Responsabilidade | Conceitos principais |
|---|---|---|
| Identidade | cadastro, sessão, papéis e preferências | usuário, papel, autenticação, localização |
| Incidentes | registro, risco, ciclo de vida e validação | incidente, severidade, risco, voto, revisão |
| Alertas | elegibilidade, persistência e entrega de avisos | notificação, raio, rota, cooldown, push |
| Monitoramento | observações ambientais externas e histórico | observação, região, chuva, qualidade do ar |
| Operações | dashboards, métricas e saúde operacional | resumo, hotspot, tendência, outbox |

```text
presentation -> application -> domain
      |              |
      +-------> infrastructure (implementa portas da aplicação)
```

O domínio não importa FastAPI, Pydantic, psycopg, RabbitMQ, Firebase ou Flutter. Aplicação coordena casos de uso e declara portas. Infraestrutura implementa portas. Apresentação traduz HTTP/UI para comandos e respostas.

## Backend

```text
backend/api/src/
├── identity/{domain,application,infrastructure,presentation}
├── incidents/{domain,application,infrastructure,presentation}
├── alerts/{domain,application,infrastructure,presentation}
├── monitoring/{domain,application,infrastructure,presentation}
└── shared/{domain,infrastructure}
```

Os módulos `auth.py`, `database.py`, `models.py` e `risk_analysis.py` são fachadas de compatibilidade para imports e entrypoints existentes. Código novo importa do contexto proprietário. `main.py`, `worker.py` e a outbox são adaptadores de entrada.

### Composition root e apresentação HTTP

`main.py` configura middlewares e conecta routers a casos de uso. Cada contexto
expõe seu router em `presentation/router.py`; endpoints não devem ser adicionados
diretamente à composition root.

O monitoramento exemplifica o fluxo completo:

```text
monitoring/presentation/router.py
              |
              v
monitoring/application/GetSystemHealth -- depende de --> HealthCheck (porta)
              ^
              |
monitoring/infrastructure/{PostgresHealthCheck,RabbitMqHealthCheck}
```

Falhas de PostgreSQL ou RabbitMQ são traduzidas pelo caso de uso para um relatório
de saúde; o router decide apenas o status HTTP. O caso de uso pode ser testado com
implementações em memória, sem FastAPI, banco ou broker.

## Aplicativo Flutter

```text
apps/mobile/lib/
├── app/                         # composição e navegação
├── core/device/                 # geolocalização compartilhada
└── features/
    ├── auth/{domain,application,presentation}
    ├── incident/{domain,application,data,infrastructure,presentation}
    ├── alerts/application/
    ├── map/presentation/
    └── weather/{data,presentation}/
```

`AppInitializer` é a composition root: cria adaptadores e injeta dependências. Telas recebem capacidades prontas e não instanciam banco ou clientes HTTP.

### Direção das dependências no mobile

```text
presentation -> application -> domain
                         ^
                         |
                  infrastructure
```

- `domain` contém entidades e portas e não importa Flutter, HTTP ou plugins;
- `application` mantém estado e coordena casos de uso através das portas;
- `infrastructure` implementa HTTP, armazenamento seguro, GPS, câmera e outros plugins;
- `presentation` observa o estado de aplicação e traduz interações do usuário;
- somente `AppInitializer` instancia implementações concretas.

No contexto de identidade, `AuthGateway` e `AuthSessionStore` são portas do
domínio. `HttpAuthGateway` e `SecureAuthSessionStore` são adaptadores. O
`AuthService` não conhece JSON, endpoints nem o plugin de armazenamento.

## Regras para evolução

1. Regra de negócio entra em `domain` e é testável sem rede ou banco.
2. Fluxo que coordena entidades e portas entra em `application`.
3. SQL, HTTP, Hive, GPS, Firebase e RabbitMQ entram em `infrastructure`/`data`.
4. FastAPI e widgets Flutter ficam em `presentation`.
5. Contextos se integram por contratos, não pelas classes internas uns dos outros.
6. Fachadas de compatibilidade não recebem novas regras.

## Decisões preservadas

- Os caminhos da API HTTP não mudaram.
- PostgreSQL/PostGIS é a fonte autoritativa atual.
- Outbox + RabbitMQ mantêm entrega assíncrona e idempotência.
- Hive mantém a fila offline-first.
- Firebase permanece como canal de push, não como banco primário atual.

## Alertas por entrada em área

O aplicativo envia a posição ao iniciar uma sessão, a cada deslocamento relevante (mínimo de
250 metros) e em tarefas periódicas de segundo plano. O endpoint de localização persiste a
posição e executa `EvaluateUserProximity`. O adaptador PostgreSQL usa `ST_DWithin` para encontrar
incidentes ativos dentro do raio configurado pelo cidadão e cria uma notificação idempotente.
Depois do commit, `FirebasePushNotificationGateway` entrega o push ao token do dispositivo.

A chave única `(user_id, incident_id)` garante uma notificação por ocorrência. Preferências de
categoria, severidade mínima, horário silencioso e autoria são aplicadas antes da criação.
