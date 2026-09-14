# Firestore não é usado no UrbanEye

A persistência do sistema é **PostgreSQL** (`backend/database/migrations`), acessado pela
API em `backend/api`. Nada no aplicativo nem no backend lê ou escreve no Firestore.

As regras que existiam aqui (`firestore.rules`, `firestore.indexes.json`) publicavam uma
coleção `ocorrencias` que nenhum código consumia. Isso abria um caminho de escrita real e
autenticado para um banco que ninguém lê — e induzia a erro quem (pessoa ou agente de IA)
lesse o repositório e concluísse que as ocorrências iam para lá. Por isso foram removidas,
junto com a seção `firestore` do `firebase.json`.

Do Firebase o projeto usa apenas:

- **Cloud Messaging (FCM)** para os alertas de proximidade;
- **Storage** para as fotos das ocorrências (`backend/firebase/storage/storage.rules`).

Se um dia o Firestore passar a ser usado de fato, as regras voltam junto com o código que
as consome — nunca antes.