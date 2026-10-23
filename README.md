# WarrantyBox — fase 1

Base para iOS e Android: arquitetura por funcionalidades, entidade de domínio,
contrato de repositório, navegação inicial e temas Material 3 claro/escuro.
O Dashboard lê os registos locais em SQLite e o editor integra câmara, galeria,
OCR local e revisão manual. As faturas confirmadas persistem entre reinícios.
O Paywall integra RevenueCat para compra vitalícia/restauro e um teste local de
7 dias. As compras exigem configurar produtos e chaves de SDK nas lojas/RevenueCat.
PDF e notificações estão ligados à UI: exportação nos detalhes, alertas automáticos
após gravar e autorização/nova tentativa em Definições. Backup está pendente.
Consultar docs/CAMERA_OCR.md para configurar e testar a captura nos dispositivos.
Consultar docs/LOCAL_STORAGE.md para esquema, CRUD, migrações e testes SQLite.
Consultar docs/IN_APP_PURCHASE.md para produtos, preço, trial e configuração IAP.
Consultar docs/PDF_NOTIFICATIONS.md para utilização dos serviços e configuração nativa.

## Dashboard

Interface inspirada na referência visual: cartões arredondados, fundo neutro e
resumo verde-lima, com adaptação ao modo escuro e largura máxima em tablets.
Inclui pesquisa por produto/loja sem distinção de acentos,
filtros combináveis por estado e categoria, estados vazios, dias restantes,
barra do período restante e detalhes num painel inferior. As contagens globais
mantêm-se independentes dos filtros. A expirar significa até 30 dias inclusive;
as garantias ativas no resumo excluem esse grupo para não duplicar contagens.
Uma instalação nova começa vazia. As seis faturas fictícias são apenas fixtures
dos testes. O estado vive em DashboardController, separado dos widgets e com
relógio injetável. A lista é recarregada ao regressar ao primeiro plano e após
gravar/eliminar. Há indicadores de carregamento, erro e opção de tentar novamente.
Nova fatura abre o editor com OCR, grava em SQLite e só depois regressa ao Dashboard.
A fotografia fica em documentos privados e pode ser vista nos detalhes.
Eliminar pede confirmação e remove o registo e a fotografia associada.
Definições mostra o estado do acesso e permite restaurar compras. Criar novas
faturas exige teste ativo ou acesso vitalício; consulta e eliminação mantêm-se livres.

## Estrutura

```text
warranty_box/
├── android/                         # gerado pelo flutter create
├── ios/                             # gerado pelo flutter create
├── assets/images/
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart                 # composição e rotas
│   │   └── theme/app_theme.dart
│   ├── core/
│   │   ├── storage/app_database.dart # SQLite, esquema e migrações
│   │   ├── files/                   # ficheiros privados do dispositivo
│   │   └── notifications/           # adaptador de alertas locais
│   └── features/
│       ├── warranties/
│       │   ├── domain/
│       │   │   ├── entities/warranty.dart
│       │   │   └── repositories/warranty_repository.dart
│       │   ├── data/                # mapper e repositório SQLite
│       │   ├── application/         # estado, pesquisa e filtros
│       │   ├── presentation/dashboard_screen.dart
│       │   └── screens/
│       │       ├── add_warranty_screen.dart
│       │       └── paywall_screen.dart
│       ├── invoices/
│       │   ├── domain/
│       │   ├── data/                # image_picker e ML Kit
│       │   ├── application/
│       │   └── presentation/invoice_editor_screen.dart
│       ├── paywall/
│       │   ├── domain/              # estado do teste e acesso vitalício
│       │   ├── data/                # RevenueCat e armazenamento do teste
│       │   ├── application/
│       │   └── presentation/paywall_screen.dart
│       ├── backup/
│       │   ├── domain/
│       │   ├── data/                # arquivo, PDF e seletor nativo
│       │   └── application/
│       └── settings/
│           ├── application/
│           └── presentation/settings_screen.dart
├── test/features/warranties/domain/warranty_test.dart
├── analysis_options.yaml
└── pubspec.yaml
```

O domínio usa apenas Dart. A camada data implementa os contratos e converte
entidades para armazenamento; application coordena casos de uso/providers;
presentation apresenta estado e recolhe ações. Riverpod faz a composição.
Não criar camadas sem responsabilidade só para preencher a árvore.

## Iniciar a partir desta pasta

Instalar Flutter stable e Android Studio/SDK e adicionar Flutter ao PATH.
Base declarada: Flutter >=3.44.0 e Dart >=3.12.0. Usar o stable atual.

```powershell
cd C:\Users\User\OneDrive\Documentos\Apps\warranty_box
flutter doctor -v
flutter doctor --android-licenses
flutter create --platforms=android,ios --project-name=warranty_box --org=com.example --no-pub .
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter devices
flutter run -d <ID_DO_DISPOSITIVO_ANDROID>
```

Substituir com.example pelo domínio inverso da organização antes de publicar.
Não usar --overwrite: preservar os ficheiros desta base. Se o Flutter gerar
test/widget_test.dart com o teste de contador padrão, removê-lo ou substituí-lo
por um teste da WarrantyBox antes de executar flutter test.
Para começar numa pasta nova, executar primeiro:

```sh
flutter create --platforms=android,ios --project-name=warranty_box --org=com.example warranty_box
```

Depois copiar lib/, test/, analysis_options.yaml e pubspec.yaml desta base.
No macOS, instalar Xcode e as ferramentas exigidas por flutter doctor,
configurar assinatura e executar flutter run num simulador/dispositivo iOS.
Compilar iOS exige macOS/Xcode; Windows permite desenvolver e testar Android.

## Configuração nativa antes de usar os plugins

- Android: minSdk 24; compileSdk pelo menos 36 (ou superior se exigido pelos
  plugins resolvidos). Ajustar targetSdk aos requisitos da loja na publicação.
  Configurar Java/Gradle/desugaring e receivers segundo o README da versão
  flutter_local_notifications. Pedir permissão de notificações quando aplicável.
  Evitar alarmes exatos para simples avisos de garantia.
- iOS: deployment target >=15.5, incluindo projeto e dependências nativas.
  Adicionar NSCameraUsageDescription e NSPhotoLibraryUsageDescription em
  Info.plist. Configurar notificações e capacidades de In-App Purchase.
- image_picker cobre captura simples e galeria. Copiar a imagem devolvida para
  documentos privados antes de guardar; não persistir o caminho da cache.
- ML Kit: usar reconhecimento latino com modelo incluído para OCR offline.
  O texto reconhecido exige parsing para loja/valor/data e confirmação humana.
- flutter_local_notifications cria alertas do sistema; não cria eventos no
  calendário. Para eventos reais será necessário um adaptador EventKit/Calendar
  Provider e permissões próprias. Agendar numa janela móvel, respeitando os
  limites de notificações pendentes do iOS.

## Modelo e persistência

Warranty é imutável. preco guarda cêntimos (499 = 4,99 EUR); moeda é EUR por
defeito. dataExpiracao é calculada a partir de dataCompra e duracaoMeses,
limitando o dia ao fim do mês de destino. É válida até ao fim desse dia.
fotoPath deve ser relativo à pasta privada, para permitir restaurar noutro
dispositivo. categoria guarda um ID estável; o rótulo pertence à UI.

SqliteWarrantyRepository implementa o contrato com findAll, findById, save e delete.
WarrantyRowMapper converte datas civis para YYYY-MM-DD, valores para cêntimos
inteiros e caminhos de imagem para referências relativas. AppDatabase gere a
abertura partilhada e a versão do esquema. Não é necessário build_runner.
Instantes técnicos como criação/alteração podem ser adicionados em UTC.
Notificações devem ser reagendadas ao editar, apagar, restaurar ou mudar de fuso.

## Privacidade, backup e compras

- Dados e fotografias permanecem locais por defeito. sqflite não cifra a base nem
  as fotografias; esta versão usa a proteção da sandbox e do sistema operativo.
  Cifra adicional exige uma solução própria para base e ficheiros, com gestão
  de chaves e recuperação. flutter_secure_storage isoladamente não cifra SQLite.
- Backup inicial: arquivo versionado com manifest e cópias das imagens, exportado
  e importado pelo seletor do sistema (file_picker), incluindo provedores iCloud
  Drive/Google Drive quando disponíveis. Isto é backup manual, não sincronização.
  Sincronização automática requer adaptadores próprios, autenticação/capacidades,
  gestão de conflitos e funcionamento offline. ZIP, por si só, não dá confidencialidade.
  Backups cifrados precisam de uma estratégia de recuperação de chaves portátil.
  Controlar também o backup automático do SO para respeitar o consentimento.
- PDF/printing geram relatórios locais. Incluir fontes locais ao implementar PDF;
  evitar downloads de fontes em tempo de execução para suportar modo offline.
- Criar produto vitalício não consumível e entitlement lifetime no RevenueCat.
  Configurar 4,99 EUR nas lojas e mostrar na UI o preço localizado devolvido pela
  loja; não fixar esse preço para todos os países. Incluir restauro de compras.
- O teste de 7 dias é uma concessão local da aplicação, iniciada explicitamente
  e sem cobrança automática. Persistir início UTC em armazenamento seguro.
  Sem servidor não há garantia contra alterações do relógio ou reinstalação.
  Não representar este teste como trial de uma subscrição da loja.
- Consultar/criar/restaurar compras e sincronizar backups exige Internet.
  A experiência principal permanece local; manter acesso comprado em cache segundo
  a política do SDK. RevenueCat transmite dados de compra/identificadores: não
  enviar faturas, imagens ou texto OCR e declarar esse tratamento na privacidade.
  Não bloquear consulta/exportação dos dados pessoais após terminar o teste.

## Versões e validação

Versões diretas fixadas a partir das páginas pub.dev consultadas em 22/10/2026.
Isto ainda não é uma resolução de dependências nem uma compilação validada.
Flutter/Dart não estão instalados no ambiente onde esta base foi preparada.
Executar flutter pub get, guardar pubspec.lock no Git e validar builds em Android
e iOS antes de considerar a combinação confirmada.

Referências: https://pub.dev/packages/sqflite,
https://pub.dev/packages/google_mlkit_text_recognition,
https://pub.dev/packages/flutter_local_notifications,
https://pub.dev/packages/purchases_flutter,
https://www.revenuecat.com/docs/platform-resources/non-subscriptions
