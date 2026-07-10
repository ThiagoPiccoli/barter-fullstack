# Revisão do frontend (app Flutter original)

Revisão de UI/UX, componentização e arquitetura do `barter-app` (mock), feita
antes da integração com o backend. Cada item marca se foi tratado neste
repositório ou se fica como recomendação.

## O que está bem resolvido (manter)

- **Domínio bem modelado e documentado** — `models.dart` explica a regra
  central (insumos → custo → sacas do grão) em comentários exemplares; os
  cálculos moram em getters do modelo (`inputCost`, `sacksToDeliver`,
  `balance`), não espalhados pelas telas.
- **Componentização real** — `common_widgets.dart` concentra o vocabulário
  visual (StatusBadge, TypeBadge, BarterBalanceBar, SummaryCard, InfoTile,
  MiniBarterCard, BarterLogItem, SearchField, DashboardHeader) e as telas o
  reutilizam de verdade. Sem copy-paste relevante entre telas.
- **Tema centralizado** — `AppColors`/`AppTheme` (Material 3) com semântica de
  cores consistente: verde institucional, âmbar = grão, verde-azulado = insumo,
  status com par cor/fundo. Nenhuma tela inventa cor própria.
- **Padrões de UX consistentes** — toda tela de nível principal tem
  LogoutButton com confirmação única (`confirmLogout`); telas empilhadas só
  voltam; ações destrutivas sempre confirmam; feedback por SnackBar.
- **Regra de privacidade por papel aplicada com disciplina** — o vendedor
  nunca vê R$ (flag `showValue` percorre telas e PDF); para ele a permuta é
  "insumos retirados → sacas do grão".
- **Fluxo da Nova Permuta** — etapa 1 (produtor) antes de tudo, porque a área
  dele define os mínimos; insumos obrigatórios pré-preenchidos e travados no
  mínimo; barras de progresso das categorias sem expor valores; resumo antes
  de enviar. UX bem pensada para o domínio.

## Problemas encontrados

| # | Problema | Severidade | Status |
|---|----------|-----------|--------|
| 1 | **Sem camada de dados**: telas liam/mutavam listas globais (`mockBarters` etc.) diretamente; trocar para API exigiria tocar toda tela | alta (arquitetura) | **corrigido aqui** — `AppData` (cache) + `repositories/` + `services/api/`; mutações passam pela API |
| 2 | **Login fake**: qualquer e-mail entrava (vazio → admin), senha ignorada | alta (segurança) | **corrigido** — auth real por token; sem signup público |
| 3 | **Usuário hardcoded**: `reviewedBy: 'Carlos Mendes'` e `changedBy: 'Carlos Mendes'` fixos no código | alta (correção) | **corrigido** — o servidor grava o usuário autenticado |
| 4 | **Regras de negócio só no cliente**: mínimos por ha/categoria e cálculo de sacas podiam ser burlados fora da UI | alta (integridade) | **corrigido** — servidor revalida tudo e ignora preços do cliente |
| 5 | **`_InputTile` recriava `TextEditingController` em cada build** (sem dispose, com `ValueKey` pela qty): teclado caía a cada dígito e havia vazamento | média (bug UX) | **corrigido** — StatefulWidget com controller próprio |
| 6 | **Listas de Cadastros compartilhavam offset de rolagem** (PageStorage sem chave): alternar Produtores↔Vendedores herdava a rolagem | média (bug UX, pego pelo teste E2E) | **corrigido** — `PageStorageKey` por lista |
| 7 | **`setState` após `await` sem `mounted`** no login | baixa | **corrigido** no fluxo novo |
| 8 | **Logo com iniciais "AP"** (resquício do Agropan) num app chamado Barter | baixa (branding) | **corrigido** — "BT" |
| 9 | **Pull-to-refresh fake** no dashboard admin (`Future.delayed(1s)`) | baixa | **corrigido** — recarrega da API (e o dashboard do vendedor ganhou um) |
| 10 | Nomes de arquivo enganosos: `sellers_screen.dart` é a tela de *Cadastros*; `seller_profile_admin_screen.dart` é o perfil do *produtor* | baixa (manutenção) | recomendação — renomear em um refactor futuro |
| 11 | `BartersScreen._filtered` roda 8× por rebuild (contadores das abas + listas) | baixa (desempenho, dataset pequeno) | recomendação |
| 12 | Acessibilidade: fontes de 10–11px em vários lugares, alvos de toque reduzidos (`shrinkWrap` nos TextButtons), sem `Semantics` | média (UX) | recomendação |
| 13 | Sem testes de unidade para a matemática da permuta no app | média (qualidade) | mitigado — a matemática autoritativa agora vive no servidor, com testes de unidade lá |
| 14 | `IndexedStack` cria as abas uma vez; dashboards podem exibir dados defasados até um refresh | baixa | mitigado — pull-to-refresh real em ambos os painéis |

## Arquitetura final do app (após integração)

```
lib/
├── models/          # modelos + fromJson (contratos da API)
├── services/
│   ├── api/         # ApiClient (base URL, token, erros → ApiException)
│   └── barter_pdf.dart
├── repositories/    # auth, producers, sellers, catalog, barters (HTTP → modelos)
├── data/
│   └── app_data.dart  # cache em memória (substitui mock_data com os mesmos contratos)
├── widgets/         # componentes compartilhados
├── screens/         # telas (leituras síncronas do cache; mutações via AppData→API)
└── theme/
```

Racional: com dataset pequeno (cooperativa), **carregar tudo no login** mantém
as telas síncronas e instantâneas, evitando espalhar `FutureBuilder` por todo
o app; toda escrita vai à API e o cache é atualizado com a resposta oficial do
servidor. Se o volume crescer, o próximo passo natural é paginar as permutas
(`GET /barters?page=`) e mover as listas para busca server-side — os
repositórios já isolam esse ponto de mudança.

## Nota sobre privacidade de preços

Hoje os preços trafegam para ambos os papéis e a **UI** esconde R$ do
vendedor (mesmo comportamento do mock; é o que permite a prévia instantânea de
sacas no construtor de permuta). Se a regra virar "vendedor não pode nem
receber os valores", o caminho é: omitir `currentPrice`/`unitValue` na
serialização para `role=seller` e criar `POST /barters/quote` para a prévia —
os transformers e o `BarterService` já estão estruturados para isso.
