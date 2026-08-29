# UrbanEye com PostgreSQL

O aplicativo Flutter não acessa o PostgreSQL diretamente. Ele usa a API Python
em `backend/api`, preservando credenciais e regras de validação fora do cliente.

## Executar localmente

Com Docker em execução, a partir da raiz do projeto:

```powershell
docker compose up --build
```

Isso sobe PostgreSQL na porta `5432`, RabbitMQ nas portas `5672` e `15672`, a
API e um worker de eventos. A migração cria a tabela `incidents` e a API fica em
`http://localhost:8000`. A documentação interativa estará em `/docs` e o painel
do RabbitMQ em `http://localhost:15672` (`urbaneye` / `urbaneye` apenas localmente).

Para executar somente a API pelo terminal, primeiro suba o PostgreSQL e crie o
arquivo de ambiente local:

```powershell
docker compose up -d postgres rabbitmq
Copy-Item backend/api/.env.example backend/api/.env
cd backend/api
pip install -r requirements.txt
# Em dois terminais separados:
uvicorn src.main:app --reload
python -m src.worker
```

O arquivo `.env.example` serve apenas como modelo; as variáveis usadas pela API
local devem estar em `.env`. Não versione credenciais reais.

No emulador Android, o padrão do app é `http://10.0.2.2:8000`. Para aparelho
físico, Web ou outra máquina, informe a URL acessível da API ao executar:

```powershell
flutter run --dart-define=API_BASE_URL=https://sua-api.exemplo.com
```

Use HTTPS em produção e remova `android:usesCleartextTraffic="true"` do
manifesto após deixar de usar HTTP local.

## Endpoints

- `POST /auth/register`: cria usuário com senha Argon2id e retorna JWT.
- `POST /auth/login`: autentica e retorna JWT bearer com expiração.
- `GET /auth/me`: retorna o usuário autenticado.
- `POST /incidents`: valida e publica uma ocorrência; retorna `202 Accepted`.
- `GET /incidents`: lista as ocorrências para o mapa.
- `GET /health`: verifica PostgreSQL e RabbitMQ.

O Hive continua sendo a fila local offline; o serviço de sincronização tenta
enviar pendências quando há conexão.

As rotas de ocorrências exigem `Authorization: Bearer <token>`. A API extrai o
usuário do JWT e inclui seu UUID no evento; o cliente não pode escolher o autor
do registro. No aplicativo, JWT e sessão ficam no armazenamento seguro do
sistema operacional. Defina `JWT_SECRET` por secret manager em produção.

## Processamento assíncrono

O fluxo de escrita é `celular → API → RabbitMQ → worker → PostgreSQL`. A API
confirma ao aplicativo somente depois que o RabbitMQ aceita a mensagem por
publisher confirm. O worker confirma a mensagem após o commit no banco.

As filas são duráveis e do tipo quorum, e as mensagens são persistentes. Falhas
temporárias passam pela fila de retry com atraso de cinco segundos. Após cinco
falhas, o evento vai para `incidents.create.dead`, onde pode ser inspecionado e
reprocessado. O UUID criado no celular é a chave primária, tornando o consumo
idempotente em caso de reentrega.

Para aumentar consumidores conforme o volume de celulares:

```powershell
docker compose up -d --scale worker=3
```

Em produção, use credenciais em um secret manager, TLS para HTTP/AMQP, limite de
requisições, autenticação, observabilidade e um cluster RabbitMQ com pelo menos
três nós para que filas quorum ofereçam alta disponibilidade real.
