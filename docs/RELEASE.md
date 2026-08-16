# O que falta para publicar

Este arquivo é a lista do trabalho de **release** — a parte que leva o
agroBarter da máquina de quem desenvolve para a mão de quem usa. Ela ficou
deliberadamente de fora da rodada de correções de agosto/2026: mexer em
assinatura, credencial de loja e esteira de distribuição é um assunto próprio,
com decisões que não são só técnicas (quem é o titular da conta, onde a chave
fica guardada, quem pode publicar).

Nada aqui é urgente para **desenvolver**. Tudo aqui é bloqueante para
**publicar**.

---

## 1. O APK de release está assinado com a chave de DEBUG 🔴

**Onde:** [`app/android/app/build.gradle.kts`](../app/android/app/build.gradle.kts)

```kotlin
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        // Signing with the debug keys for now, so `flutter run --release` works.
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

**Por que isto é grave, e não um TODO de rotina.** A keystore de debug do
Android não é secreta: ela é gerada pelo SDK com senha conhecida (`android`) e é
a **mesma em toda máquina do mundo**. Um APK assinado com ela pode ser
reassinado por qualquer pessoa — e o Android trata a assinatura como identidade
do aplicativo. Na prática, qualquer um consegue produzir um "agroBarter
atualizado" que o aparelho de um testador aceita instalar por cima do legítimo,
com acesso ao token guardado no Keychain.

E isto não é hipotético hoje: o
[`distribute.yml`](../.github/workflows/distribute.yml) roda
`flutter build apk --release` e **entrega esse APK aos testadores** pelo Firebase
App Distribution a cada push aprovado na `main`.

Também é bloqueio duro para a Play Store, que recusa upload assinado com chave
de debug.

**O que fazer:**

1. Gerar uma keystore de release e **guardá-la fora do repositório** (a chave
   perdida não se recupera: sem ela não existe atualização do app publicado,
   só um aplicativo novo, com outra listagem e sem os usuários).
   ```bash
   keytool -genkey -v -keystore ~/agrobarter-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias agrobarter
   ```
2. Criar `app/android/key.properties` (e **adicioná-lo ao `.gitignore`**):
   ```properties
   storeFile=/caminho/absoluto/agrobarter-release.jks
   storePassword=...
   keyAlias=agrobarter
   keyPassword=...
   ```
3. Ler esse arquivo no `build.gradle.kts` e usá-lo no `buildTypes.release`,
   caindo para a chave de debug **apenas** quando o `key.properties` não
   existir — assim `flutter run --release` continua funcionando na máquina de
   quem desenvolve, sem a chave real.
4. No CI, a keystore entra como *secret* (base64) e é escrita em disco no
   passo de build. Nunca commitada.
5. Decidir quem é o **titular** da conta Play/Firebase e onde a chave fica
   guardada de verdade (cofre da empresa, não o notebook de uma pessoa). Ver
   também *Play App Signing*, que deixa o Google guardar a chave de assinatura
   e resolve o problema de perda — vale considerar antes de publicar.

---

## 2. Credencial de distribuição depreciada 🟡

**Onde:** [`.github/workflows/distribute.yml`](../.github/workflows/distribute.yml)

```yaml
--token "${{ secrets.FIREBASE_TOKEN }}"
```

O `firebase-tools --token` (login CI legado) está **descontinuado** e deixa de
funcionar sem aviso útil. O caminho atual é uma **conta de serviço**:

1. Criar a conta de serviço no projeto Firebase com o papel *Firebase App
   Distribution Admin*.
2. Guardar o JSON da chave como secret e expor via
   `GOOGLE_APPLICATION_CREDENTIALS`.
3. Trocar a linha do `--token` por essa variável.

Melhor ainda, se a conta permitir: **Workload Identity Federation** (OIDC), que
dispensa guardar chave de longa duração no GitHub.

---

## 3. O resto da esteira

Itens que aparecem junto com a primeira publicação de verdade:

- **iOS.** Não há nada configurado além do projeto padrão: falta perfil de
  provisionamento, certificado de distribuição e a conta do Apple Developer.
  O `README` já registra que o build `-d macos` exige certificado — o de
  publicação exige mais.
- **`versionCode` / `versionName`.** Hoje saem do `pubspec.yaml` (`1.0.0+1`) e
  ninguém os incrementa. Dois envios com o mesmo `versionCode` são recusados
  pela loja; o caminho é derivar do número da execução do CI ou de uma *tag*.
- **`API_URL` do build de release.** O padrão é `http://localhost:3333`
  ([`api_client.dart`](../app/lib/services/api/api_client.dart)); o APK
  distribuído hoje aponta para lugar nenhum. Precisa entrar como
  `--dart-define=API_URL=https://...` no passo de build — e **em https**, que é
  o que a política de rede do app já exige de qualquer host que não seja
  localhost.
- **Ofuscação.** `flutter build apk --obfuscate --split-debug-info=...` para o
  release público, guardando os símbolos para conseguir ler os relatórios de
  falha depois.
- **Onde a API vai rodar.** Ver a seção *Produção* do
  [`api/README.md`](../api/README.md); em especial `TRUST_PROXY` (o servidor
  avisa na subida se ela faltar), `CORS_ORIGINS` e a `DATABASE_URL` com
  `sslmode=require`. A sonda `GET /health` já existe para o balanceador.
- **Backup do banco.** Não há rotina definida. Um Postgres gerenciado resolve
  com um clique; um Postgres em VM não resolve sozinho.
- **Relatório de falhas em produção.** Nem o app nem a API mandam erro para
  lugar nenhum: o `requestId` do 500 vive no log do processo. Um Sentry (ou
  equivalente) nos dois lados é o que transforma "o app fechou" em algo
  investigável.

---

## Como usar esta lista

Quando o release entrar na pauta, comece pelo **item 1** — ele é o único com
consequência de segurança para quem já está usando o APK de teste hoje. Os
itens 2 e 3 são trabalho de esteira e podem ser feitos na mesma leva.
