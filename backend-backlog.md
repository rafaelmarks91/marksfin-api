# Backend Backlog — PBD pendentes

Lista de `pbd_id` previstos para o MVP, na ordem do [BACKLOG-MVP.md](../marksfin-app/BACKLOG-MVP.md),
cada um mapeado para o endpoint do [CONTRATO-API.md](../marksfin-app/CONTRATO-API.md) que vai
chamá-lo via `sp_sys_execucao_pbd`. Os marcados com `[x]` já têm procedure escrita e validada
contra o banco (`ativo=1` em `sys_pbd_ctrl`); o resto fica `missing-functional-procedure` até ser
escrito — ver [ADR-004](./architecture-decisions.md#adr-004-falha-explícita-para-pbd-ausente).

Schema único `marksfin` (sem separação por domínio — projeto não comercializado, ver ADR-001).
Cada `pbd_id` vira uma procedure própria seguindo o padrão de nome `sp_pbd_<pbd_id>`, registrada
em `sys_pbd_ctrl` para o executor encontrar.

## P0 — Autenticação ✅ escrito em `0003_pbd_auth.sql`

- [x] `auth_cadastrar` — `POST /auth/register`. Cria usuário (senha com Argon2id, hash feito no
  backend antes de chamar o PBD) e o espaço financeiro inicial na mesma transação.
- [x] `auth_login` — `POST /auth/login`. Localiza usuário ativo por e-mail normalizado; devolve
  hash de senha para verificação Argon2id no backend (mesmo padrão do TeraOdonto) e a lista de
  espaços. Única procedure que devolve `password_hash` — o backend descarta logo após verificar.
- [x] `sessao_criar` (infra, não estava no backlog original) — cria a sessão depois que o backend
  confirma a senha com Argon2id. Chamada separada de `auth_login` de propósito: login só
  autentica, quem decide se cria sessão é o backend.
- [x] `sessao_validar` (infra, não estava no backlog original) — middleware de autenticação
  genérico, usado por toda rota protegida (não só `/auth/me`). Recebe `token_hash`, nunca o
  cookie.
- [x] `auth_logout` — `POST /auth/logout`. Revoga a sessão pelo hash do token. Sempre retorna
  sucesso (idempotente — não revela se o token era válido).
- [x] `auth_me` — `GET /auth/me`. Usuário atual (sem `password_hash`) e espaços disponíveis.
- [x] `auth_esqueci_senha` — `POST /auth/forgot-password`. Gera token de recuperação (hash
  salvo) e invalida tokens anteriores não usados do mesmo usuário. Resposta é idêntica exista ou
  não o e-mail — `data.deve_enviar_email`/`data.user_id`/`data.nome` são só para a fila de
  e-mail do backend, nunca aparecem na resposta HTTP (`204` sempre).
- [x] `auth_redefinir_senha` — `POST /auth/reset-password`. Valida token (expiração + uso único),
  atualiza senha e revoga todas as sessões ativas do usuário, tudo numa transação.

**Contratos que o backend precisa respeitar ao chamar essas procedures** (achados testando
contra o servidor de verdade, não só lidos na documentação):

- **Datas**: passe `expires_at` como `Date.toISOString()` (ISO 8601, ex.:
  `2026-09-29T11:48:43.362Z`) — a procedure remove o `T`/`Z` antes de converter. Não formate a
  mão nem mande no formato `YYYY-MM-DD HH:MM:SS` do MariaDB.
- **`ip_hash`**: nunca mande o IP cru nem um hash simples (`SHA-256(ip)` sozinho é reversível por
  força bruta — o espaço de IPv4 é pequeno). Calcule `HMAC-SHA256(SESSION_SECRET, ip)` no
  backend antes de chamar `sessao_criar`.
- **`token_hash`**: sempre `SHA-256` do token bruto gerado com `crypto.randomBytes` (mínimo 32
  bytes). O token bruto nunca é persistido — só existe em memória no backend (pro cookie) ou no
  corpo do e-mail (pro link de recuperação).
- **`password_hash`**: sempre Argon2id, calculado no backend antes de qualquer chamada de PBD.
  MariaDB não tem Argon2 nativo, então isso nunca pode acontecer dentro de uma procedure.

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
