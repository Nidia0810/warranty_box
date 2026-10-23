# Persistência local SQLite

## Dependências

sqflite 2.4.5, path 1.9.1 e, apenas para testes, sqflite_common_ffi 2.4.4.
Hive CE foi removido, pois não havia dados ou integração Hive implementados.
Não há migração de dados antigos: o Dashboard anterior mantinha só dados em memória.
Imagens do protótipo sem registo associado não são importadas nem apagadas.

## Organização

- core/storage/app_database.dart: warranty_box.db em getDatabasesPath(),
  abertura lazy partilhada, esquema versão 1 e índices por expiração/categoria.
- features/warranties/data/warranty_row_mapper.dart: conversão entidade/linha.
- features/warranties/data/sqlite_warranty_repository.dart: CRUD assíncrono.
- features/warranties/domain/repositories/warranty_repository.dart: contrato Dart.
- DashboardController: carregamento, pesquisa, filtros e estado de erro.
- InvoiceEditorScreen: gravação após confirmação dos campos de OCR/manual.

## Dados

Tabela warranties: id (chave primária), title, store, price_cents, currency,
purchased_on, duration_months, expires_on, photo_path, category, notes.
Preço é um inteiro em cêntimos. Datas civis são YYYY-MM-DD, sem conversão de fuso.
Expiração é calculada pelo modelo e persistida para indexação; o mapper verifica
consistência ao ler. Valores negativos e campos essenciais vazios são rejeitados.

As fotografias não são BLOBs: ficam em documents/invoices/<uuid>.<ext> e a tabela
guarda o caminho relativo. Não guardar caminhos temporários ou absolutos.
Ao mudar de dispositivo via backup, reconstruir o caminho a partir da pasta local.
O texto OCR bruto é revisto na UI; os campos confirmados são guardados, o texto
bruto não é persistido nesta versão.

## Utilização do repositório

```dart
final database = AppDatabase();
final repository = SqliteWarrantyRepository(database);

await repository.save(warranty); // Cria ou atualiza pelo ID
final all = await repository.findAll();
final one = await repository.findById(warranty.id);
await repository.delete(warranty.id);
```

save faz update e, se necessário, insert dentro da mesma transação. As consultas
por ID usam whereArgs, preservando acentos, apóstrofos e caracteres especiais.
findAll devolve ordem cronológica de expiração. A apresentação ordena por estado.
O contrato usa leitura explícita em vez de stream: o Dashboard recarrega depois
das alterações e quando a app regressa ao primeiro plano.

Atualizar mantém o ID e reconstrói Warranty com os dados revistos. A API suporta
atualização, mas a UI de edição de registos existentes ainda não está implementada.
delete remove só a linha na camada de dados. O fluxo de eliminação do Dashboard
pede confirmação e tenta apagar a fotografia depois do commit da eliminação.
Se o ficheiro já não existir, a eliminação é considerada concluída.

## Falhas e consistência

Guardar segue: copiar fotografia, inserir registo, fechar editor, recarregar lista.
Se a base falhar após a cópia, tenta remover apenas a nova fotografia criada pela
operação e mantém os campos para tentar novamente. Não apaga registos antigos.
Há validação de caminho ao remover imagens para impedir sair de invoices/.
Uma falha durante leitura mantém a lista anterior e mostra erro com nova tentativa.

SQLite e o sistema de ficheiros não têm transação conjunta. Uma interrupção abrupta
entre as operações pode deixar uma imagem órfã. Uma falha ao apagar o ficheiro após
eliminar a linha é comunicada e não recria o registo. Não há limpeza automática de
ficheiros órfãos: implementar com verificação de referências e backups no futuro.
O DB fica aberto durante a vida da aplicação; SQLite recupera transações incompletas
após terminar o processo. close está disponível para testes e encerramento controlado.

## Migrações

Não alterar o SQL da versão 1 como forma de atualizar instalações existentes.
Na próxima alteração, aumentar version para 2 e implementar onUpgrade, por exemplo:

```dart
if (oldVersion < 2) {
  await db.execute('ALTER TABLE warranties ADD COLUMN created_at TEXT');
}
```

Os callbacks de migração do sqflite são executados em transação. Adicionar teste
de uma base antiga antes de publicar. Esta versão não inclui migrações futuras
inventadas: onUpgrade rejeita versões sem implementação. Não existe fallback que
apague/recrie o catálogo em caso de erro.

## Privacidade

Não há servidores, autenticação, upload ou rede nesta persistência. Funciona offline.
A base está na área privada da app; as fotografias estão em documentos privados.
sqflite não cifra o ficheiro: existe apenas a proteção do SO/sandbox nesta fase.
Backups automáticos iOS/Android podem incluir estes dados dependendo da configuração
do projeto. Configurar exclusões e consentimento antes de prometer backup apenas
manual. Apagar a aplicação pode eliminar os dados locais; backup é outro módulo.

## Validação

```sh
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d <id-do-telemovel>
```

Os testes SQLite usam um ficheiro temporário real por teste via FFI: inserir,
fechar/reabrir, atualizar sem duplicar, eliminar, parâmetros SQL e restrições.
Testam também datas inválidas/expiração inconsistente e erros de leitura no
controller. A fixture de demonstração é usada apenas nos testes.

O Flutter SDK não está instalado no ambiente de autoria, pelo que os testes Dart,
a resolução de dependências e builds móveis ainda não foram executados.
O SQL do esquema foi extraído do ficheiro Dart e validado separadamente com SQLite
num ficheiro de teste: criação dos índices, inserção, reabertura, atualização,
restrições, parâmetros e eliminação passaram. Isto não substitui os testes do plugin.
No telefone: guardar em modo avião, terminar a app, reabrir, confirmar os campos
e a fotografia; eliminar, reiniciar e confirmar a ausência do registo.

Referências: https://pub.dev/packages/sqflite e https://pub.dev/packages/sqflite_common_ffi
