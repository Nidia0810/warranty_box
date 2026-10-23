# PDF e notificações locais

Serviços em lib/core/services/pdf_service.dart e notification_service.dart.
Compatíveis com o Warranty do projeto: preco em cêntimos, dataExpiracao civil e
fotoPath relativo à pasta de documentos. Não usam RevenueCat nem enviam dados.
Os serviços estão ligados à UI. Os detalhes da garantia têm Ver / imprimir PDF e
Partilhar PDF. O formulário grava primeiro em SQLite e só depois configura os
alertas futuros a 30 e 7 dias. Definições > Notificações locais pede autorização e
sincroniza os avisos. main.dart cria uma única instância de cada serviço e app.dart
injeta-as nos ecrãs, incluindo os caminhos de recuperação de captura Android.

Uma falha/recusa de notificações não desfaz a gravação: regressa ao Dashboard com
um aviso e sem induzir uma segunda gravação. O Dashboard volta a sincronizar no
arranque/foreground sem pedir permissões. Ao eliminar, tenta cancelar os avisos
da garantia antes de atualizar a janela. A exportação PDF continua disponível
para consultar os dados pessoais mesmo depois de o teste grátis terminar.

## PDF

```dart
import 'core/services/pdf_service.dart';

final pdfService = PdfService();

// Num botão da UI, com tratamento de erro e indicador de progresso:
await pdfService.preview(context, warranty);
await pdfService.printWarranty(warranty);
await pdfService.shareWarranty(warranty);

// Para um futuro fluxo de backup/exportação em ficheiro:
final bytes = await pdfService.generateWarrantyPdf(warranty);
```

Cada chamada é uma ação separada: não executar as quatro em sequência num botão.
preview apresenta PdfPreview, que inclui ações de imprimir e partilhar.
printWarranty devolve false se o utilizador cancelar o diálogo de impressão.
shareWarranty abre o seletor do sistema; o resultado não confirma entrega ao destinatário.

No iPad, passar bounds de um RenderBox do botão para posicionar a partilha:

```dart
final box = context.findRenderObject() as RenderBox;
await pdfService.shareWarranty(
  warranty,
  bounds: box.localToGlobal(Offset.zero) & box.size,
);
```

Usar o BuildContext do botão/Builder correspondente, não de um widget sem RenderBox.
Capturar PdfExportException para mostrar message e outras exceções para erros de
plataforma. Não mostrar sucesso quando a geração ou partilha falha.

O relatório tem dados, estado calculado no momento de exportação e uma página de
anexo com a fotografia inteira. É uma imagem numa página PDF, não um ficheiro
original embutido. Não existe uma exportação global de todas as garantias nesta API.
Uma garantia sem imagem gera só o relatório; uma imagem referenciada mas em falta
ou ilegível causa erro explícito, sem gerar um relatório incompleto silenciosamente.

As imagens são lidas apenas dentro de invoices/, convertidas em PNG localmente e
reduzidas proporcionalmente até 4096 píxeis no maior lado. O ficheiro original não
é alterado. Fontes HEIC/HEIF dependem do codec do dispositivo; se falhar, usar JPEG
ou PNG. Imagens com mais de 40 MB são rejeitadas antes de descodificar.
Talões muito compridos ficam ajustados à página: conferir a legibilidade no preview.

Não há downloads de fontes. Helvetica é usada por defeito para português comum.
Para outros alfabetos/emoji, fornecer regularFont e boldFont com fontes locais
compatíveis, por exemplo pw.Font.ttf(await rootBundle.load(...)), declarando os
assets no pubspec. Não usar PdfGoogleFonts em tempo de execução para um fluxo offline.

printing precisa das dependências nativas instaladas pelo Flutter. Em projetos iOS
com CocoaPods, aplicar use_frameworks! dentro do target Runner se exigido pelo
README de printing, preservando o restante Podfile. Em macOS, usar o entitlement
com.apple.security.print; o alvo principal deste projeto continua a ser iOS/Android.
Não é necessária permissão geral de armazenamento: o PDF é gerado em memória e
o utilizador escolhe o destino na impressão/partilha. O destino escolhido pode ser
um serviço remoto; a geração do relatório continua local.

## Notificações

Manter uma instância partilhada na composição da app, depois de
WidgetsFlutterBinding.ensureInitialized(). Inicializar não solicita permissões:

```dart
final notifications = NotificationService();
await notifications.initialize(onTap: (warrantyId) {
  // Encaminhar o ID para a navegação quando o Navigator estiver disponível.
});
final launchedWarrantyId = notifications.initialWarrantyId;
// Se não for null, consumir depois do primeiro frame para abrir a garantia.
```

Não bloquear o arranque do catálogo se a configuração nativa dos alertas falhar.
Tratar a exceção e permitir voltar a tentar depois de configurar o dispositivo.
Registar o callback antes de usar o serviço; não existe navegação automática.

Ao ativar alertas num botão/switch explícito:

```dart
final result = await notifications.scheduleWarrantyAlerts(
  warranty,
  daysBefore: [30, 7],
  hour: 9,
  requestPermission: true,
);
if (!result.permissionGranted) {
  // Mostrar instruções para autorizar notificações nas definições do SO.
}
```

Neste fluxo, os alertas são automáticos e a autorização é controlada pelo SO.
Se for acrescentada uma preferência de alertas da app, guardá-la separadamente.
Não voltar a abrir diálogos de permissões em cada arranque/foreground.
Quando a preferência já está ativa, usar requestPermission: false (predefinição).

Para um catálogo completo, usar a janela móvel recomendada:

```dart
final warranties = await repository.findAll();
final result = await notifications.syncWarrantyAlerts(warranties);
// result.scheduledIds: alertas agendados; result.deferredCount: adiados pela janela.
```

Esta chamada recebe o catálogo COMPLETO: não passar só resultados de pesquisa,
porque cancela os alertas WarrantyBox ausentes dessa lista. Sincronizar no arranque,
no foreground e após guardar, editar, eliminar, restaurar backups ou mudar fuso/
preferências. Quando o utilizador desativa alertas, cancelar os pendentes:

```dart
await notifications.cancelWarrantyAlerts(warrantyId);
await notifications.cancelAllWarrantyAlerts();
```

Não executar as duas chamadas sem necessidade; a segunda cancela todos os alertas
pendentes deste módulo. Não apaga notificações de outros módulos nem garante limpar
as notificações que já foram apresentadas na central do sistema.

O serviço usa a zona IANA do telefone, não assume Lisboa, e subtrai dias civis
antes de aplicar a hora local. Não agenda instantes já passados nem recorrências.
Horários ambíguos/inexistentes na mudança de hora seguem a normalização de timezone;
usar 09:00 evita normalmente essas transições. Reagendar após mudar de fuso.
IDs são determinísticos, com deteção de colisões entre pendentes; payload identifica
a garantia para cancelar mesmo depois de mudar a antecedência.

Por privacidade, o corpo não inclui produto/loja por defeito; showProductName: true
é opcional. A visibilidade Android é privada. O SO controla a exibição no ecrã
bloqueado e a entrega; modo Foco/Não incomodar, poupança de bateria ou force-stop
podem impedir ou atrasar avisos. inexactAllowWhileIdle não garante hora exata e
não pede permissões de alarmes exatos. São notificações locais, não eventos criados
no calendário do sistema.

iOS admite até 64 notificações pendentes. syncWarrantyAlerts conserva os próximos
60 (ou menos se outros módulos ocuparem vagas) e reporta o resto como adiado.
Reaberturas da app repõem a janela; sem reabrir não existe garantia de reposição
dos adiados. A versão por garantia rejeita exceder 64 antes de cancelar os alertas
anteriores. Android também tem limites de fabricante; a sincronização usa 60.
Agendamento e cancelamento nativos não são transacionais: perante erro, sincronizar
de novo; o serviço não devolve sucesso de uma sincronização parcialmente concluída.

## Android: configuração obrigatória

O projeto ainda não tem android/ gerado. Depois de flutter create, integrar no
android/app/build.gradle.kts, mantendo a restante configuração Flutter:

```kotlin
android {
    compileSdk = 36 // ou superior exigido pelas dependências
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    // Alinhar também o target JVM Kotlin com Java 17 na DSL do projeto.
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Manter minSdk 24. A documentação de flutter_local_notifications 22.3.2 recomenda
AGP >=8.11.1; verificar a versão gerada pelo Flutter sem a baixar se for superior.
No AndroidManifest.xml, fora de application:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

Dentro de application, para entrega agendada e reposição após reinício:

```xml
<receiver
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
    android:exported="false" />
<receiver
    android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
    android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
        <action android:name="android.intent.action.QUICKBOOT_POWERON" />
        <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
    </intent-filter>
</receiver>
```

Criar android/app/src/main/res/drawable/ic_stat_warranty.xml:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#FFFFFFFF"
        android:pathData="M12,2L3,6v6c0,5 5,8 9,10c4,-2 9,-5 9,-10V6L12,2z" />
</vector>
```

Preservar o recurso nas builds release via res/raw/keep.xml quando usar shrinkResources:

```xml
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_stat_warranty" />
```

Não adicionar SCHEDULE_EXACT_ALARM/USE_EXACT_ALARM: este serviço usa alarmes inexatos.

## iOS

Não existe uma chave de permissão de notificações locais para copiar para Info.plist.
A autorização de alertas/som é pedida em runtime pelo plugin. Não acrescentar
UIBackgroundModes ou permissões de calendário para este fluxo.
Manter as entradas de câmara/galeria já usadas pelo OCR, dentro do dict existente:

```xml
<key>NSCameraUsageDescription</key>
<string>A WarrantyBox usa a câmara para fotografar os seus talões.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>A WarrantyBox permite selecionar fotografias de faturas para leitura local.</string>
```

No AppDelegate.swift, importar UserNotifications e integrar em
application(_:didFinishLaunchingWithOptions:), preservando o ciclo de vida Flutter:

```swift
UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
```

O serviço não usa ações em background: não exige um callback Dart em isolate
separado. A autorização é pedida via plugin. Notificações estritamente locais
não exigem APNs/Push Notifications. Manter o deployment target 15.5 da stack OCR.

## Validação

```sh
dart format lib test
flutter analyze
flutter test
```

Há testes de planeamento para 30/7 dias, mudança de hora em Lisboa, datas passadas,
antecedências repetidas, valores inválidos e IDs. Há testes de geração de bytes PDF,
imagem ausente e proteção de caminhos. Os testes de interface verificam os botões
PDF e a gravação com sucesso, recusa de permissão, falha nativa de alertas e falha
SQLite (não tentar notificações quando a fatura não foi guardada).
Flutter SDK indisponível neste ambiente:
testes Dart, renderização visual dos PDFs, diálogos de impressão/partilha e entrega
real de notificações não foram executados. Verificar num Android e iPhone reais,
incluindo permissões recusadas, reinício, mudança de fuso e builds release.

Referências:
- https://pub.dev/packages/printing
- https://pub.dev/packages/pdf
- https://pub.dev/packages/flutter_local_notifications
- https://pub.dev/documentation/flutter_timezone/latest/flutter_timezone/FlutterTimezone/getLocalTimezone.html
