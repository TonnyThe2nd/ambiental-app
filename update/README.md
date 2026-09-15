# Atualizações Android

Antes de criar uma tag, aumente `version` em `apps/mobile/pubspec.yaml`.
Por exemplo: `1.0.3+3` (o número após `+` precisa superar todo release anterior).
A tag deve corresponder à versão antes do `+`: `v1.0.3`.
O workflow lê ambos os valores do pubspec e mantém a assinatura existente.

```powershell
git add .
git commit -m "nova atualização"
git push origin master
git tag v1.0.3
git push origin v1.0.3
```

Configure os Secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`
e `KEY_ALIAS`. Use sempre o mesmo keystore do aplicativo instalado.
O token do Actions precisa de `contents: write` e permissão para fazer push
na `master`; regras de proteção da branch devem permitir esse bot.
O repositório e os arquivos da Release precisam ser públicos para acesso sem login.

O arquivo `latest.json` inicial é um bootstrap da versão instalada (1.0.0+2):
o hash zerado não representa um APK publicado. A primeira tag com versionCode
maior que 2 o substitui por URL e hash reais. Não distribua esse manifesto como
uma atualização para versões anteriores. Não edite URL/hash manualmente.
Para exigir uma atualização, defina `mandatory: true` antes de criar a tag;
o workflow copia essa política do commit marcado pela tag.

O APK é publicado antes do manifesto. Releases concorrentes são serializadas,
versionCodes inferiores não sobrescrevem o manifesto e pushes do manifesto não
acionam este workflow, que aceita somente tags `v*`. Conflitos na master falham
sem force-push. É possível reexecutar a execução após resolver permissões/conflitos.

O app consulta uma vez por sessão após a inicialização e compara versionCode.
Erros de consulta não bloqueiam o app. O diálogo obrigatório não pode ser fechado;
a instalação continua exigindo confirmação nativa. No primeiro uso, o Android
pode pedir autorização para instalar desta fonte: habilite e toque Atualizar
novamente. Cancelar o instalador não é tratado como instalação concluída.
APKs ficam somente no cache privado de atualizações e são limpos na próxima
consulta/download. Valide instalação e atualização em um Android físico,
incluindo permissão negada e cancelamento, antes de distribuir.

Referências: [FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider)
e [package_info_plus](https://pub.dev/packages/package_info_plus).
