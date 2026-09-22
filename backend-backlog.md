# Backend Backlog — PBD pendentes

Nenhuma stored procedure existe ainda. Esta é a lista de `pbd_id` previstos para o MVP, na ordem
do [BACKLOG-MVP.md](../marksfin-app/BACKLOG-MVP.md), cada um mapeado para o endpoint do
[CONTRATO-API.md](../marksfin-app/CONTRATO-API.md) que vai chamá-lo via `sp_sys_execucao_pbd`.
Todos ficam com status `missing-functional-procedure` até serem escritos no banco — ver
[ADR-004](./architecture-decisions.md#adr-004-falha-explícita-para-pbd-ausente).

Schema único `marksfin` (sem separação por domínio — projeto não comercializado, ver ADR-001).
Cada `pbd_id` vira uma procedure própria seguindo o padrão de nome `sp_pbd_<pbd_id>`, registrada
em `sys_pbd_ctrl` para o executor encontrar.

## P0 — Autenticação

- `auth_cadastrar` — `POST /auth/register`. Cria usuário (senha com Argon2id, hash feito no
  backend antes de chamar o PBD) e o espaço financeiro inicial na mesma transação.
- `auth_login` — `POST /auth/login`. Localiza usuário por e-mail normalizado; devolve hash de
  senha para verificação Argon2 no backend (mesmo padrão do TeraOdonto) e a lista de espaços.
- `auth_logout` — `POST /auth/logout`. Revoga a sessão pelo hash do token.
- `auth_me` — `GET /auth/me`. Usuário atual (sem `password_hash`) e espaços disponíveis.
- `auth_esqueci_senha` — `POST /auth/forgot-password`. Gera token de recuperação (hash salvo,
  TTL de `PASSWORD_RESET_TTL_MINUTES`). Resposta HTTP é sempre `204`, mesmo se o e-mail não
  existir — a procedure decide silenciosamente se envia e-mail ou não.
- `auth_redefinir_senha` — `POST /auth/reset-password`. Valida token, atualiza senha e revoga
  todas as sessões ativas do usuário.

## P0 — Espaços e autorização

- `espacos_listar` — `GET /spaces`. Espaços do usuário autenticado.
- `espaco_obter` — `GET /spaces/:spaceId`. Falha se o usuário não for membro ativo.
- `espaco_atualizar` — `PATCH /spaces/:spaceId`. Só `OWNER`.
- `espaco_membros_listar` — `GET /spaces/:spaceId/members`.
- `espaco_membro_remover` — `DELETE /spaces/:spaceId/members/:userId`. `OWNER` ou o próprio
  membro saindo; nunca remove o último `OWNER`.

## P0 — Compartilhamento

- `convite_criar` — `POST /spaces/:spaceId/invitations`. Só `OWNER`; token aleatório, só o hash
  é persistido.
- `convites_listar` — `GET /spaces/:spaceId/invitations`.
- `convite_revogar` — `DELETE /spaces/:spaceId/invitations/:id`.
- `convite_obter_por_token` — `GET /invitations/:token`. Público; valida expiração/uso.
- `convite_aceitar` — `POST /invitations/:token/accept`. Confirma que o e-mail autenticado
  corresponde ao destinatário antes de criar o `space_member`.

## P0 — Financeiro

- `contas_listar` / `conta_criar` / `conta_obter` / `conta_atualizar` / `conta_arquivar` —
  `/spaces/:spaceId/accounts` (arquivar é a "exclusão", nunca remoção física).
- `categorias_listar` / `categoria_criar` / `categoria_obter` / `categoria_atualizar` /
  `categoria_arquivar` — `/spaces/:spaceId/categories`. Nome único por espaço+tipo entre ativas.
- `lancamentos_listar` — `GET /spaces/:spaceId/transactions`. Filtros `from`, `to`, `accountId`,
  `categoryId`, `type`, `search`, paginação por cursor (`transaction_date DESC, id DESC`).
- `lancamento_criar` — `POST /spaces/:spaceId/transactions`. Para `type=TRANSFER`, a procedure
  cria as duas linhas (`TRANSFER_OUT`/`TRANSFER_IN`) com o mesmo `transfer_group_id` numa única
  transação SQL.
- `lancamento_obter` / `lancamento_atualizar` / `lancamento_excluir` — idem; atualizar ou excluir
  uma transferência afeta os dois lados atomicamente.
- `dashboard_obter` — `GET /spaces/:spaceId/dashboard?month=`. Saldo, receitas, despesas,
  resultado, comparação com mês anterior, despesas por categoria e série diária — tudo agregado
  pela procedure; o front só formata.
- `relatorio_categorias` — `GET /spaces/:spaceId/reports/categories?from=&to=`.
- `lancamentos_exportar_csv` — `GET /spaces/:spaceId/export.csv?from=&to=`. Só `OWNER`; a
  procedure devolve os dados, o backend monta o CSV.

## P1 / P2 (depois do MVP central)

- `lancamento_duplicar` — duplicar lançamento (P1).
- Importação CSV/OFX (P1) — ainda sem PBD definido; entra quando o parsing for desenhado.
- Papel `EDITOR` (P2) — precisa de PBDs de escrita para convidado, hoje só `VIEWER` existe.
