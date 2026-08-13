// Apaga o arquivo do banco SQLite (e os sidecars do WAL) antes de um reset.
//
// Roda como `predb:reset`, automaticamente antes de `npm run db:reset`.
//
// Por que precisa existir: o servidor coloca o banco em `journal_mode = WAL`
// (ver src/prisma/prisma.service.ts), e esse modo fica gravado no CABEÇALHO do
// arquivo — sobrevive ao servidor fechar, mesmo sem os arquivos `-wal`/`-shm`
// por perto. O `prisma migrate reset` não lida com um banco em WAL: ele trunca
// o arquivo e depois falha ao criar a tabela de migrations, com
// "database disk image is malformed". Rodar o comando duas vezes "resolvia",
// porque na segunda o arquivo já estava vazio.
//
// Apagar o arquivo antes torna o reset determinístico. É seguro: `db:reset` é
// destrutivo por definição — ele existe justamente para recomeçar do zero.
const fs = require('node:fs');
const path = require('node:path');

const url = process.env.DATABASE_URL ?? 'file:./prisma/dev.db';
if (!url.startsWith('file:')) {
  // Postgres e afins: quem apaga é o próprio prisma.
  process.exit(0);
}

const file = path.resolve(url.slice('file:'.length));
for (const suffix of ['', '-wal', '-shm', '-journal']) {
  fs.rmSync(`${file}${suffix}`, { force: true });
}
