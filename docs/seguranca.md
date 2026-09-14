# Segurança e conformidade — UrbanEye

Procedimentos operacionais que acompanham as proteções já implementadas no código.
O que está aqui **não é automatizável pelo repositório**: depende de console externo,
de segredo que nunca entra no Git ou de decisão de operação.

---

## 1. Restringir a chave de API do Firebase

A chave em `apps/mobile/android/app/google-services.json` **não é um vazamento**: chave de
cliente Firebase é feita para ficar dentro do app e não dá acesso privilegiado sozinha. O
que falta é a restrição no console — sem ela, qualquer pessoa que extraia a chave do APK
consome a cota do projeto.

No [Google Cloud Console](https://console.cloud.google.com/apis/credentials), projeto
`aps-ambiental`, na chave usada pelo app Android:

1. **Restrições de aplicativo → Apps Android.** Adicionar:
   - nome do pacote: `com.urbaneye.urbaneye_mobile`
   - impressão digital SHA-1 do certificado de **release** (o keystore próprio, não o de
     debug). Obter com:
     ```bash
     keytool -list -v -keystore ~/urbaneye-release.jks -alias urbaneye | grep SHA1
     ```
   - repetir com o SHA-1 de debug apenas enquanto o time precisar rodar builds locais.
2. **Restrições de API.** Limitar à lista do que o app realmente usa:
   Firebase Cloud Messaging API, Firebase Installations API, Firebase Remote Config
   (se aplicável) e Cloud Storage for Firebase. Tudo o mais fica fora.
3. Verificar em **APIs e serviços → Painel** se alguma API antiga continua habilitada sem
   uso; desabilitar reduz a superfície.

Refazer o passo 1 sempre que o certificado de release mudar — inclusive ao migrar para o
*Play App Signing*, cujo SHA-1 é o da chave gerenciada pelo Google, não o do keystore local.

---

## 2. Keystore de release do Android

O `build.gradle.kts` lê `android/key.properties` (ignorado pelo Git). Veja o modelo em
`apps/mobile/android/key.properties.example`.

```bash
keytool -genkey -v -keystore ~/urbaneye-release.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias urbaneye
```

- O `.jks` e o `key.properties` **nunca** entram no repositório.
- Guardar uma cópia em cofre de senhas: perder o keystore significa não conseguir mais
  publicar atualizações do app existente na Play Store.
- Sem `key.properties`, o build de release sai **sem assinatura** — de propósito, para o
  erro aparecer no build e não na loja. Não voltar a apontar para `signingConfigs.debug`:
  a chave de debug é pública e compartilhada por todos os projetos Flutter, o que permite
  a qualquer um assinar um APK que o Android aceita como "atualização" deste app.

---

## 3. Variáveis de ambiente sensíveis da API

| Variável | Efeito |
| --- | --- |
| `JWT_SECRET` | Obrigatória, mínimo 32 caracteres. A API recusa subir sem ela. |
| `JWT_EXPIRE_MINUTES` | Vida do token (60 por padrão). Quanto menor, menor a janela de um token vazado. |
| `ENV` | `production` desliga `/docs` e `/openapi.json` e liga o `Strict-Transport-Security`. |
| `ALLOWED_ORIGINS` | Origens do app web autorizadas no CORS, separadas por vírgula. Vazio cai em `http://localhost:3000` — **nunca** `*`. |

---

## 4. Sessões e revogação de token

O JWT carrega um `jti` e a tabela `revoked_tokens` guarda os tokens invalidados antes de
expirarem (migração `008`). Com isso:

- `POST /auth/logout` encerra a sessão **no servidor**, não só no aparelho;
- `DELETE /auth/me` revoga o token junto com a exclusão da conta;
- não é mais preciso trocar o `JWT_SECRET` — o que deslogaria todo mundo — para cortar uma
  sessão comprometida.

A tabela é limpa a cada revogação: token expirado já é recusado pela própria validação da
assinatura, então só interessa guardar o que ainda estaria vivo.

---

## 5. Exclusão de conta (LGPD art. 18, VI)

`DELETE /auth/me` anonimiza `name`, `email`, `password_hash`, `latitude`/`longitude`,
`location`, `fcm_token` e `alert_route`, apaga as notificações e marca `deleted_at`. Contas
marcadas não autenticam, não recebem alertas e não aparecem em nenhuma consulta de usuário.

As ocorrências **permanecem** no mapa: são informação pública de interesse coletivo e
deixam de ter vínculo identificável com quem denunciou. A chave estrangeira
`incidents.reported_by` passou a ser `ON DELETE SET NULL`, de forma que uma remoção física
do registro (pedido de eliminação total) também é possível sem quebrar o banco.

---

## 6. Backup diário

O workflow `.github/workflows/daily-postgres-backup.yml` cifra o dump com
`gpg --symmetric --cipher-algo AES256` **antes** do upload. Secrets necessários:

- `DATABASE_URL`
- `BACKUP_ENCRYPTION_PASSPHRASE` — separado do acesso ao bucket, para que vazar um não
  entregue o outro
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`

A retenção padrão é de 30 dias e pode ser ajustada na variável de repositório
`BACKUP_RETENTION_DAYS`.

Restaurar:

```bash
gpg --decrypt urbaneye-AAAA-MM-DD.dump.gpg > urbaneye.dump
pg_restore --no-owner --no-acl --dbname "$DATABASE_URL" urbaneye.dump
```

Guardar a passphrase em cofre de senhas: sem ela o backup é irrecuperável.

---

## 7. O que já está correto (não mexer)

- **Argon2id** via `pwdlib.PasswordHash.recommended()`.
- **Proteção contra timing attack no login**: hash dummy quando o e-mail não existe, para
  o tempo de resposta não revelar se a conta existe.
- **`JWT_SECRET` validado no boot**: `RuntimeError` se tiver menos de 32 caracteres —
  falha rápido em vez de rodar inseguro.
- **JWT no `flutter_secure_storage`** (Keychain/Keystore), não em SharedPreferences.