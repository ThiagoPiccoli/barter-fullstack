#!/usr/bin/env node
/**
 * A FOLHA DE ACESSOS do ambiente de teste, em PDF.
 *
 *   node scripts/credentials-pdf.mjs credenciais.json --out=acessos.pdf \
 *        --api=https://barter-api.vercel.app
 *
 * Entra o JSON que o `npm run provision` escreveu; sai um PDF de uma página com
 * uma linha por conta e, ao lado de cada papel, O QUE ELE FAZ na esteira da
 * permuta. Isso não é enfeite: quem vai testar precisa saber que a permuta
 * registrada pelo consultor só anda quando o GERENTE dá o parecer, e que quem
 * aprova é o COMITÊ — sem isso o teste trava no segundo passo e parece defeito.
 *
 * O PDF sai pelo Chrome em modo headless (`--print-to-pdf`), e não por LaTeX:
 * não há distribuição TeX nesta máquina, e acrescentar uma (uns 500MB, com
 * instalador que pede senha) para compor uma página de tabela seria pagar caro
 * por um caminho que o Chrome já anda. O HTML fica no meio do caminho, então
 * quem quiser reimprimir ou ajustar o layout tem um arquivo legível para mexer.
 *
 * O ARQUIVO DE SAÍDA É SEGREDO: ele carrega as senhas em texto puro, e é a
 * única cópia delas. Não versione, e prefira mandá-lo por um canal que não
 * fique guardado para sempre.
 */

import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

/** O que cada papel FAZ — a mesma divisão de postos de barter-workflow.ts. */
const ROLE_NOTES = {
  admin: 'Administra o sistema: usuários, unidades, produtos, safras e a tabela de preços. Não decide permuta.',
  consultant: 'Registra a permuta junto ao produtor e a envia ao gerente dele.',
  manager: 'Escreve o parecer técnico das permutas do próprio time. Não aprova.',
  committee: 'Aprova ou nega. É a única instância que decide — o acesso é do órgão, não de uma pessoa.',
  biller: 'Fatura o que o comitê aprovou. É o fim da linha.',
};

/** A ordem em que os papéis aparecem: a mesma em que a permuta passa por eles. */
const ROLE_ORDER = ['consultant', 'manager', 'committee', 'biller', 'admin'];

function parseArgs(argv) {
  const input = argv.find((arg) => !arg.startsWith('--'));
  const flag = (name) => argv.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
  return { input, out: flag('out'), api: flag('api'), html: flag('html') };
}

function escapeHtml(value) {
  return String(value).replace(
    /[&<>"']/g,
    (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char],
  );
}

function render(credentials, apiUrl) {
  const today = new Date().toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: 'long',
    year: 'numeric',
  });

  const sorted = [...credentials].sort(
    (a, b) => ROLE_ORDER.indexOf(a.role) - ROLE_ORDER.indexOf(b.role),
  );

  const groups = ROLE_ORDER.flatMap((role) => {
    const people = sorted.filter((item) => item.role === role);
    if (people.length === 0) return [];
    return [{ role, label: people[0].roleLabel, people }];
  });

  const rows = groups
    .map(
      ({ role, label, people }) => `
      <section class="grupo">
        <div class="cabeca">
          <h2>${escapeHtml(label)}${people.length > 1 ? ` <span class="cont">${people.length} contas</span>` : ''}</h2>
          <p>${escapeHtml(ROLE_NOTES[role] ?? '')}</p>
        </div>
        <table>
          <thead>
            <tr><th>Nome</th><th>E-mail</th><th>Senha</th><th>Unidade</th></tr>
          </thead>
          <tbody>
            ${people
              .map(
                (p) => `<tr>
                  <td>${escapeHtml(p.fullName)}</td>
                  <td class="mono">${escapeHtml(p.email)}</td>
                  <td class="mono senha">${escapeHtml(p.password)}</td>
                  <td class="filial">${escapeHtml(p.branch ?? '—')}</td>
                </tr>`,
              )
              .join('\n')}
          </tbody>
        </table>
      </section>`,
    )
    .join('\n');

  return `<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<title>agroBarter — acessos do ambiente de teste</title>
<style>
  @page { size: A4; margin: 14mm 13mm; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
    color: #16241c;
    font-size: 10pt;
    line-height: 1.45;
  }
  header { border-bottom: 2.5pt solid #2f6b46; padding-bottom: 7pt; margin-bottom: 13pt; }
  h1 { margin: 0; font-size: 17pt; color: #2f6b46; letter-spacing: -0.2pt; }
  .sub { margin: 3pt 0 0; color: #5c6b62; font-size: 9pt; }
  .ambiente {
    margin: 11pt 0 14pt;
    padding: 8pt 10pt;
    background: #f2f7f3;
    border-left: 3pt solid #2f6b46;
    font-size: 9pt;
  }
  .ambiente strong { color: #2f6b46; }
  .grupo { margin-bottom: 12pt; break-inside: avoid; }
  .cabeca h2 {
    margin: 0;
    font-size: 11pt;
    color: #2f6b46;
    display: flex;
    align-items: baseline;
    gap: 6pt;
  }
  .cont { font-size: 8pt; font-weight: 500; color: #7a8a80; }
  .cabeca p { margin: 1pt 0 5pt; font-size: 8.5pt; color: #5c6b62; }
  table { width: 100%; border-collapse: collapse; }
  th {
    text-align: left;
    font-size: 7.5pt;
    text-transform: uppercase;
    letter-spacing: 0.4pt;
    color: #7a8a80;
    border-bottom: 0.75pt solid #d4ded8;
    padding: 3pt 5pt;
    font-weight: 600;
  }
  td { padding: 4pt 5pt; border-bottom: 0.5pt solid #eaf0ec; vertical-align: middle; }
  .mono { font-family: "SF Mono", Menlo, Consolas, monospace; font-size: 9pt; }
  .senha { font-weight: 700; letter-spacing: 0.3pt; color: #1c4a30; white-space: nowrap; }
  .filial { color: #5c6b62; font-size: 8.5pt; }
  .fluxo {
    margin-top: 4pt;
    padding: 9pt 10pt;
    border: 0.75pt solid #d4ded8;
    border-radius: 3pt;
    font-size: 8.5pt;
    color: #3d4b43;
    break-inside: avoid;
  }
  .fluxo h3 { margin: 0 0 4pt; font-size: 9pt; color: #2f6b46; }
  .fluxo code {
    font-family: "SF Mono", Menlo, Consolas, monospace;
    background: #f2f7f3;
    padding: 1pt 3pt;
    border-radius: 2pt;
  }
  footer {
    margin-top: 12pt;
    padding-top: 7pt;
    border-top: 0.75pt solid #d4ded8;
    font-size: 7.5pt;
    color: #7a8a80;
  }
  footer strong { color: #a33; }
</style>
</head>
<body>
  <header>
    <h1>agroBarter — acessos do ambiente de teste</h1>
    <p class="sub">Gerado em ${escapeHtml(today)} · uma conta por papel do sistema</p>
  </header>

  <div class="ambiente">
    <strong>Servidor:</strong> <span class="mono">${escapeHtml(apiUrl ?? 'defina com --api=')}</span><br>
    <strong>Senha:</strong> sorteada por conta, distinta para cada uma. Não há recuperação por
    e-mail — quem redefine senha de outro é o administrador, dentro do app.
  </div>

  ${rows}

  <div class="fluxo">
    <h3>Para testar uma permuta de ponta a ponta, nesta ordem</h3>
    <strong>1.</strong> O <em>consultor</em> registra a permuta e envia →
    <strong>2.</strong> o <em>gerente daquele consultor</em> escreve o parecer →
    <strong>3.</strong> o <em>comitê</em> aprova ou nega →
    <strong>4.</strong> o <em>faturista</em> fatura.<br>
    Cada permuta vai para o gerente do consultor que a registrou, e não para qualquer gerente:
    João, Ana → <code>gerente@</code>; Roberto, Maria, Lucas → <code>gerente.sul@</code>. Entrar
    com o gerente errado é ver uma fila vazia, e isso é a regra funcionando.<br>
    O ambiente começa <strong>sem produtores e sem permutas</strong>: o catálogo (unidades,
    classes, produtos e a tabela de preços da safra vigente) já está pronto, e o primeiro passo
    é o consultor cadastrar um produtor.
  </div>

  <footer>
    <strong>Este arquivo é segredo.</strong> Ele carrega as senhas em texto puro e é a única
    cópia delas — depois do provisionamento elas só existem como hash, e nem o administrador
    consegue lê-las de volta. Reprovisionar o ambiente sorteia senhas novas e invalida esta folha.
  </footer>
</body>
</html>`;
}

const { input, out, api, html: htmlOut } = parseArgs(process.argv.slice(2));

if (!input || !out) {
  console.error(
    'uso: node scripts/credentials-pdf.mjs <credenciais.json> --out=<acessos.pdf> [--api=<url>] [--html=<acessos.html>]',
  );
  process.exit(1);
}

const credentials = JSON.parse(readFileSync(input, 'utf8'));
const html = render(credentials, api);

// O Chrome só imprime o que consegue abrir por URL, então o HTML passa por um
// arquivo — em diretório temporário, porque ele carrega as senhas.
const workdir = mkdtempSync(join(tmpdir(), 'agrobarter-acessos-'));
const htmlPath = join(workdir, 'acessos.html');
writeFileSync(htmlPath, html, { mode: 0o600 });

const outPath = resolve(out);
execFileSync(
  CHROME,
  [
    '--headless=new',
    '--disable-gpu',
    '--no-pdf-header-footer',
    `--print-to-pdf=${outPath}`,
    `file://${htmlPath}`,
  ],
  { stdio: 'pipe' },
);

// O PDF nasce com a permissão padrão do Chrome (legível por todo mundo na
// máquina). Ele carrega senha em texto puro, então fecha para o dono — a mesma
// regra que o `provision` aplica ao JSON.
chmodSync(outPath, 0o600);

if (htmlOut) {
  const htmlOutPath = resolve(htmlOut);
  writeFileSync(htmlOutPath, html, { mode: 0o600 });
  console.log(`HTML guardado: ${htmlOutPath}`);
}

console.log(`PDF gerado: ${outPath}`);
console.log(`${credentials.length} contas. Não versione este arquivo.`);
