# Câmara e OCR local

## Ficheiros

- lib/features/invoices/data/receipt_image_service.dart: câmara/galeria,
  recuperação Android e cópia da fotografia confirmada para documentos privados.
- lib/features/invoices/data/receipt_ocr_service.dart: ML Kit latino, processImage
  sobre ficheiro local, reutilização do motor durante a vida do ecrã e libertação
  na saída, depois de qualquer leitura pendente terminar.
- lib/features/invoices/data/receipt_parser.dart: sugestões de loja, total em
  cêntimos e data; sem rede. Regex compiladas uma vez e seleção por contexto.
- lib/features/invoices/domain/receipt_reading.dart: resultado independente de UI.
- lib/features/warranties/screens/add_warranty_screen.dart: fotografia,
  progresso, revisão manual, texto selecionável e confirmação.
- lib/features/invoices/presentation/invoice_editor_screen.dart: wrapper de
  compatibilidade com imports antigos; não duplica o formulário.
- main.dart: recupera capturas perdidas no arranque; Dashboard abre o editor
  e recebe a garantia confirmada através de Navigator.

## Android

Gerar primeiro o projeto nativo com o comando indicado no README. Em
android/app/build.gradle.kts, manter a configuração criada pelo Flutter e ajustar:

```kotlin
android {
    compileSdk = 36 // ou o nível superior exigido pelos plugins resolvidos
    defaultConfig {
        minSdk = 24
    }
}
```

image_picker usa a aplicação de câmara do sistema e o seletor de fotografias.
Não adicionar permissões gerais de armazenamento nem requestLegacyExternalStorage.
Não adicionar CAMERA apenas para este fluxo de captura por Intent: o plugin trata
o fluxo. Se a aplicação passar a declarar CAMERA por outro módulo, é necessário
gerir também essa permissão. Não usar launchMode="singleInstance".

ReceiptImageService.recover é chamado uma vez em main e usa retrieveLostData.
Se o Android matar a Activity durante a captura, o editor é reaberto com a imagem
recuperada e executa OCR. Isto recupera a fotografia, não um formulário em edição.

O plugin de OCR usa o modelo latino incluído (com.google.mlkit:text-recognition),
permitindo a leitura sem primeiro descarregar um modelo em tempo de execução.
Manter esta dependência bundled; uma variante Play Services pode exigir download.

## iOS

Configurar deployment target >=15.5 no Runner e nas dependências, conforme o
README da versão do plugin. Usar macOS/Xcode para compilar e testar.
Adicionar estas entradas DENTRO do dict existente em ios/Runner/Info.plist:

```xml
<key>NSCameraUsageDescription</key>
<string>A WarrantyBox usa a câmara para fotografar os teus talões e ler o texto no dispositivo.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>A WarrantyBox permite selecionar fotografias de talões para leitura local.</string>
```

Não é necessário acesso ao microfone para fotografias. requestFullMetadata é
false: a app não pede acesso a metadados completos. Isto não é uma operação de
remoção de EXIF; a cópia mantém o conteúdo original do ficheiro.
Em projetos CocoaPods, definir platform :ios, '15.5' e alinhar o deployment target
dos pods conforme as instruções do ML Kit, preservando flutter_additional_ios_build_settings.
Se o projeto usar Swift Package Manager, configurar o target no Xcode e verificar
o suporte de cada plugin; não criar um Podfile isolado sem a integração Flutter.

## Comportamento e limites

1. Tirar fotografia ou selecionar na galeria. Cancelar não altera o formulário.
2. Mostrar imagem e o indicador «A analisar o talão com IA...», pintado antes da
   chamada nativa. Texto bruto fica disponível para revisão/cópia. Não há progresso
   percentual artificial: o ML Kit não o fornece neste fluxo.
3. Sugerir loja (primeiro cabeçalho plausível), total marcado explicitamente como
   total e uma data não ambígua. Dar prioridade a «total a pagar», «valor a pagar»,
   «total geral» e «montante total»; excluir subtotal, imposto e troco. Valores
   diferentes com a mesma prioridade ficam por preencher. Datas de compra/emissão
   têm prioridade; datas identificadas como validade/vencimento são ignoradas.
   Não tentar adivinhar o nome do produto.
4. Corrigir título, loja, preço, data, duração, categoria e notas.
5. Confirmar: copiar o ficheiro original para documents/invoices/<uuid>.<ext>,
   guardar o registo e o caminho relativo em SQLite e atualizar o Dashboard.
   Só fechar o editor depois de a gravação terminar. Se falhar, remover a cópia
   nova quando possível e manter o formulário para nova tentativa.

O OCR é uma leitura de imagem única, não um scanner de vídeo nem um detetor de
bordas. Boa luz, foco e o talão inteiro melhoram os resultados. Não há garantia de
extração correta. O parser inicial assume euros, duas casas decimais e datas
dd/mm/aaaa, dd.mm.aaaa, dd-mm-aaaa ou aaaa-mm-dd; outras convenções exigem revisão.
Não usar o maior número do talão como total. Um texto sem total explícito não
preenche esse campo. Vários totais contraditórios exigem preenchimento manual.

O ecrã mede o tempo de reconhecimento e parsing com Stopwatch, sem incluir o
tempo gasto na câmara/galeria ou a gravação. O resultado aparece após a leitura.
O objetivo de menos de 5 segundos tem de ser medido em builds profile/release em
Android e iOS reais, incluindo primeira leitura e repetições. Não há garantia de
latência: resolução, foco, comprimento do talão e dispositivo influenciam a leitura.
O original é mantido, evitando reduzir texto pequeno antes de medir a precisão.
Referência: https://developers.google.com/ml-kit/vision/text-recognition/v2/android

Todos os campos ficam editáveis após a análise. Cancelar a câmara preserva o
formulário. Repetir a leitura da mesma imagem conserva os campos que o OCR não
conseguiu reconhecer; escolher uma imagem diferente limpa loja, preço e data
para evitar misturar talões. Título, categoria, duração e notas são manuais.

Erros de permissões, cancelamentos, ficheiros indisponíveis e falhas do OCR têm
tratamento na UI. Uma falha no OCR permite repetir ou preencher manualmente.
Não há upload de imagens, texto ou campos neste módulo. Copiar texto para a área
de transferência é uma ação explícita do utilizador, exterior ao armazenamento
privado da app. A pasta privada e a cópia local não equivalem a cifra própria e
podem ser abrangidas pelo backup automático do SO até este ser configurado.

O catálogo persiste agora em SQLite e as imagens são reencontradas após reinício.
SQLite e ficheiros não partilham uma transação: falhas abruptas entre cópia e
gravação podem deixar ficheiros órfãos. Imagens canceladas não são copiadas pela
app para documentos; a câmara/galeria é responsável pelos seus temporários.

## Verificação

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <id-do-dispositivo>
```

Testes automáticos incluídos para datas inválidas/ambíguas, dinheiro, milhares,
subtotais, devoluções, campos ausentes e atualização do Dashboard.
O Flutter SDK não está disponível no ambiente de autoria: testes e compilação
nativa ainda não foram executados. Verificar num Android e num iPhone reais:

- Primeira permissão, recusa, permissão restrita e cancelamento.
- Fotografar em modo avião desde o primeiro arranque após instalação.
- Galeria JPEG/PNG e HEIC em iPhone real; o simulador tem limitações HEIC.
- Talão vazio/desfocado, fotografia rodada, total e data em falta.
- Repetir leitura, corrigir manualmente, confirmar e abrir a imagem nos detalhes.
- Cancelar a captura e verificar que os dados anteriores se mantêm.
- Recriação da Activity Android durante a captura e recuperação no arranque.

Referências:
- https://pub.dev/packages/image_picker
- https://pub.dev/packages/google_mlkit_text_recognition
- https://developers.google.com/ml-kit/vision/text-recognition/v2/android
