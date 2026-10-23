# RevenueCat: compra única + teste de 7 dias

## Modelo comercial implementado

- Compra vitalícia não consumível, preço base pretendido 4,99 EUR.
- Teste local de 7 dias, iniciado explicitamente, sem compra ou cobrança automática.
- Consulta e eliminação das faturas existentes continuam disponíveis após o teste.
- Criar novas faturas exige teste ativo ou entitlement vitalício confirmado.

Uma compra não consumível não possui um trial renovável de subscrição. O SDK gere
a compra/restauro/entitlement; a app gere a concessão local de 7 dias. Não criar
uma subscrição semanal/mensal só para simular este produto. Trials de subscrição
são outro modelo comercial e podem passar a cobrar automaticamente.

## Código

- domain/billing_gateway.dart: contrato do SDK e oferta com preço localizado.
- domain/trial_record.dart: duração de sete períodos de 24 horas, em UTC.
- data/revenuecat_gateway.dart: configure, offerings, purchase, restore, listener.
- data/secure_trial_store.dart: início/último instante observado em armazenamento
  seguro, num único JSON versionado; valida a leitura após gravar.
- application/billing_controller.dart: estado, concorrência, trial e erros.
- features/warranties/screens/paywall_screen.dart: paywall Flutter próprio, sem
  purchases_ui_flutter, com tema claro/escuro e preço localizado da loja.
- features/paywall/presentation/paywall_screen.dart: reexport para imports antigos.
- main.dart: cria uma única instância e inicializa sem bloquear o arranque local.
- Dashboard: mostra paywall antes de nova fatura, mantendo a consulta acessível.
- Editor: volta a verificar ao guardar, incluindo quando o teste termina com o
  formulário aberto. Capturas Android recuperadas não são descartadas pelo paywall.
- Definições: estado do acesso e restauro de compras.

Os controllers vivem durante a sessão principal da app; dispose remove listener,
subscription e timer quando o proprietário terminar essa sessão (incluindo testes).

## Configurar nas lojas e no RevenueCat

1. Criar as aplicações com os identificadores reais Android/iOS.
2. No App Store Connect, criar In-App Purchase **Non-Consumable** com o ID
   `warrantybox_lifetime`. Configurar preço 4,99 EUR no território de referência.
3. Na Google Play Console, criar e ativar produto de compra única não consumível
   com o mesmo ID `warrantybox_lifetime`. Não o consumir nem definir como subscrição.
4. No RevenueCat, ligar cada app à respetiva loja com as credenciais exigidas e
   importar os produtos. Estas credenciais ficam no serviço, nunca no Flutter.
5. Criar entitlement `lifetime` e associar os dois produtos.
6. Criar uma Offering, marcá-la como Current e adicionar um package do tipo
   Lifetime (`$rc_lifetime`) com o produto certo em cada plataforma.
7. Configurar as notificações servidor-a-servidor das lojas no RevenueCat para
   atualizar reembolsos/revogações. Não requer um servidor próprio da WarrantyBox.
8. Configurar o comportamento de Restore/Transfer no RevenueCat e testar com as
   contas de loja pretendidas. A app usa identidade anónima do SDK; não inventa
   um ID novo a cada arranque e não chama logOut.

O adaptador só aceita package Lifetime com productCategory.nonSubscription e ID
esperado. O acesso só é concedido por entitlement ativo com o produto esperado
e sem data de expiração. Não confiar apenas no resultado de uma transação ou no
nome do package. Alterar IDs nas configurações abaixo se as lojas usarem outros.

Não foram criados produtos nem alteradas contas externas durante esta implementação.

## Chaves públicas de SDK

Usar apenas chaves públicas específicas da app (`appl_...` e `goog_...`), nunca
secret API keys RevenueCat ou credenciais de serviço da Google/Apple.
dart-define organiza a configuração; não transforma chaves em segredos no binário.

PowerShell:

```powershell
flutter pub get
flutter run --dart-define=REVENUECAT_ANDROID_API_KEY=goog_SUBSTITUIR
```

No macOS, para iOS:

```sh
flutter run --dart-define=REVENUECAT_IOS_API_KEY=appl_SUBSTITUIR
```

Builds de distribuição:

```sh
flutter build appbundle --dart-define=REVENUECAT_ANDROID_API_KEY=goog_SUBSTITUIR
flutter build ipa --dart-define=REVENUECAT_IOS_API_KEY=appl_SUBSTITUIR
```

Configurações opcionais:

```text
REVENUECAT_ENTITLEMENT=lifetime
REVENUECAT_LIFETIME_PRODUCT=warrantybox_lifetime
```

Sem chaves, o SDK não é configurado e os botões de compra ficam indisponíveis;
o teste local continua disponível. Em debug, é possível fornecer a chave `test_...`
do RevenueCat Test Store na variável da plataforma para testar esse ambiente.
O adaptador recusa chaves Test Store em release. Não distribuir builds de produção
com essas chaves nem considerar Test Store equivalente à validação das lojas reais.

## Configuração nativa

O projeto ainda não tem android/ e ios/ gerados neste ambiente. Depois de flutter
create, integrar os seguintes ajustes nos ficheiros existentes, sem os substituir:

### Android

Em android/app/src/main/AndroidManifest.xml, fora de application:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Verificar permissão de billing no manifest merged do plugin e manter a Activity
em `android:launchMode="singleTop"` ou `standard`. Isto permite regressar de uma
app bancária sem cancelar indevidamente a compra. Não usar singleTask/singleInstance
para o fluxo de compras. Esta UI própria não usa RevenueCat Paywalls nativo;
FlutterFragmentActivity não é exigido apenas por este ecrã.

Manter minSdk 24 e os níveis de SDK exigidos pela stack. Configurar exclusões do
Android Auto Backup para o armazenamento seguro conforme o flutter_secure_storage;
restaurar dados cifrados sem as chaves pode tornar o registo do teste ilegível.
Não chamar deleteAll nem apagar automaticamente esse registo em caso de erro.

### iOS

Manter deployment target >=15.5 devido ao OCR; ativar In-App Purchase no Runner.
Configurar Keychain Sharing/entitlements usados pelo flutter_secure_storage em
Debug/Profile/Release no Xcode conforme a documentação do plugin. Testar uma
gravação e leitura após reinício, com a assinatura/provisioning corretos.
Validar dependências via Swift Package Manager ou CocoaPods do projeto existente.

## Preço, acesso e falhas

- O preço exibido é storeProduct.priceString, recebido da loja. O código não força
  o texto 4,99 EUR para moedas/territórios diferentes. O preço real é configurado
  nas lojas; a confirmação da compra é apresentada pela própria loja.
- Cancelamento não concede acesso nem mostra sucesso. Pagamento pendente também
  não concede acesso; o listener e refresh em foreground verificam confirmação.
- Uma compra só fecha o paywall depois de confirmar o entitlement correto.
- Restaurar vazio não concede acesso. Restaurar não inicia uma compra nova.
- Não há um bool vitalício paralelo em SQLite/secure storage. CustomerInfo e a
  cache do SDK são a fonte para acesso comprado, incluindo comportamento offline.
  Uma falha de rede preserva o último acesso conhecido nesta sessão; uma resposta
  confirmada sem entitlement remove esse acesso. Testar a política de cache do SDK
  em períodos offline prolongados, sem prometer validação eterna sem Internet.
- Erros de offerings não apagam um acesso pago confirmado.
- O trial local funciona offline. O início só é considerado confirmado após
  persistência, e leituras/gravações locais são serializadas.
- Checkpoints guardam o maior instante UTC observado para dificultar recuar o
  relógio. Isto não torna um teste offline inviolável: reinstalação, limpeza do
  armazenamento e alterações do relógio podem contornar a concessão. Não há uma
  garantia de teste único por pessoa/dispositivo sem identidade e validação remota.
- Não existe controlo de trial entre dispositivos. Compras entre iOS e Android
  também não são automaticamente partilhadas usando identidades anónimas distintas;
  isso exige identificação de utilizador e política de transferência adequadas.

Não enviar talões, fotografias, texto OCR, notas ou nomes de lojas para o RevenueCat.
O serviço recebe dados de compras, identificadores e metadados do SDK: declarar
esse tratamento na política de privacidade e fichas das lojas. Antes de publicar,
adicionar os URLs reais de Termos e Política de Privacidade ao produto/paywall.
O texto do paywall identifica backup como funcionalidade futura. PDF e alertas
locais já estão ligados à UI; estes avisos não criam eventos no calendário do SO.
O título é «Guarde todas as suas faturas. Para sempre.». Sem preço carregado,
4,99 EUR é mostrado apenas como referência e comprar fica desativado. Com produto
carregado, o preço real substitui a referência, incluindo outras moedas/territórios.

## Testes e validação

```sh
dart format lib test
flutter analyze
flutter test
```

Testes de unidade usam gateway e armazenamento falsos, sem compras reais:
ativação explícita, limite exato de 7 dias, persistência/reabertura, falha de escrita,
checkpoint de relógio, compra confirmada, cancelamento, pendência, listener,
restauro vazio/válido, perda de rede, revogação e falta de configuração.
Os testes de widgets verificam os benefícios, identificação de módulos futuros,
preço localizado, compra desativada sem produto e ausência de compra ao ativar trial.

Flutter SDK não está instalado no ambiente de autoria. Os testes Dart e builds
não foram executados; transações ainda não foram validadas em sandbox/TestFlight/
Google Play Internal Testing. Verificar também: fechar/reabrir a app, restauro após
reinstalar, reembolso, compra já possuída, conta errada, aprovação parental/bancária,
modo avião e fim do trial com formulário aberto. Usar contas de teste das lojas.

Referências:
- https://www.revenuecat.com/docs/getting-started/installation/flutter
- https://www.revenuecat.com/docs/getting-started/configuring-sdk
- https://www.revenuecat.com/docs/platform-resources/non-subscriptions
- https://www.revenuecat.com/docs/test-and-launch/debugging/caching
- https://pub.dev/documentation/purchases_flutter/latest/purchases_flutter/Purchases/purchase.html
- https://pub.dev/packages/flutter_secure_storage
