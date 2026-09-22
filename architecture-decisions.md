# Architecture Decisions

## ADR-001: Backend chama apenas stored procedures (PBD)

Toda regra de negócio do MarksFin vive em stored procedures no MariaDB — mesmo padrão adotado
no TeraOdonto. O backend não executa `INSERT`/`UPDATE`/`DELETE` direto nas tabelas de negócio, e
evita `SELECT` direto sempre que a consulta envolve regra (saldo, permissão, agregação). A única
chamada operacional para regra de negócio é:

```sql
CALL sp_sys_execucao_pbd(?, @object_output);
SELECT @object_output AS object_output;
```

Diferente do TeraOdonto (que separa por vários schemas), o MarksFin não é um produto
comercializado — todas as tabelas e procedures ficam num schema único, o próprio banco
`marksfin` já usado pela aplicação. Isso evita overhead de versionamento/GRANTs entre múltiplos
schemas sem necessidade real para o tamanho do projeto.

O primeiro parâmetro é um JSON com pelo menos `sys_id`, `pbd_id` (identifica qual operação
executar), `pbd_versao` e os parâmetros específicos da operação. A procedure escreve o resultado
como JSON em `@object_output`, no formato:

```json
{
  "success": true,
  "code": "SUCCESS",
  "message": "Operação realizada.",
  "data": {},
  "errors": [],
  "meta": {}
}
```

**Por quê:** manter a regra de negócio no banco, não no backend — centralizada, auditável e
protegida mesmo se outro cliente (script, outro serviço) acessar o banco diretamente. O
backend fica fino: valida forma de entrada (Zod), chama o PBD certo, mapeia o envelope de volta
para o formato HTTP do [CONTRATO-API.md](../marksfin-app/CONTRATO-API.md), sem decidir regra.

## ADR-002: Espaço ativo sempre validado pela procedure

O front-end informa `spaceId` na URL, mas o backend nunca confia só nesse valor. Todo PBD que
opera sobre um espaço financeiro recebe `usuario_id` (do usuário autenticado) e `space_id`, e a
própria procedure valida se existe associação ativa em `space_members` antes de ler ou escrever
qualquer coisa. Um `space_id` de outro usuário deve resultar em erro de contrato (ex.:
`SPACE_ACCESS_DENIED`), nunca em dado vazado.

## ADR-003: Sessão validada no banco, não só no cookie

A sessão usa cookie opaco (`HttpOnly`, `Secure`, `SameSite=Lax`) — o backend nunca decodifica um
JWT para saber "quem é o usuário". Cada requisição autenticada chama um PBD de validação de
sessão (hash do token → usuário + espaços), que também checa expiração e revogação direto na
tabela `sessions`. Revogar acesso (troca de senha, remoção de participante) é revogar a sessão no
banco — o efeito é imediato na próxima requisição, sem esperar o cookie expirar.

## ADR-004: Falha explícita para PBD ausente

Enquanto uma procedure funcional não existir para um `pbd_id`, o repository continua chamando o
PBD esperado — nunca simula sucesso no backend. O service retorna erro de contrato
(`PROCEDURE_NOT_IMPLEMENTED` ou equivalente) e a pendência fica registrada em
[backend-backlog.md](./backend-backlog.md). Isso evita que uma tela pareça funcionar com dado
fake enquanto a regra real ainda não foi escrita no banco.

## ADR-005: API atrás do Apache, nunca exposta direto

A API escuta apenas `127.0.0.1` (`HOST=127.0.0.1` em produção) e usa `fastify.register(cors)`
restrito ao domínio da aplicação. A exposição pública é feita por um vhost Apache local, que faz
`ProxyPass /api/v1` para o processo Node gerenciado pelo PM2. Ver
[README.md](./README.md#production-pm2--apache) para o exemplo de vhost e a alocação de porta no
servidor compartilhado com o TeraOdonto.

## ADR-006: Cadastro fechado + painel admin em SPA separada

MarksFin deixa de ter cadastro público. Só um usuário com `users.is_admin = TRUE` cria contas
novas, via convite (`signup_invitations` — tabela e regras diferentes de `invitations`, que dá
acesso somente-leitura a um espaço já existente; aqui o convite cria conta e espaço do zero).
`sp_pbd_auth_cadastrar` exige um `convite_token_hash` válido, cujo e-mail bate exatamente com o
e-mail cadastrado.

A administração roda numa **SPA separada** (`master.marksfin.com.br`, repositório
`marksfin-master`), não numa rota dentro do app principal (`app.marksfin.com.br`). As duas SPAs
chamam a mesma API (`marksfin-api`) — não é um backend novo, só rotas novas sob `/admin`,
protegidas checando `is_admin` (a própria procedure valida isso, nunca só o backend — mesmo
espírito do ADR-002). Ver `0004_admin.sql` e o módulo "Administração" em
[backend-backlog.md](./backend-backlog.md).

**Por quê:** o projeto é pensado desde já pra eventualmente ser compartilhado com amigos, cada
um com conta própria e independente — não como acesso somente-leitura à conta de quem convidou
(isso já existe via `invitations`). Fechar o cadastro e ter um painel de administração evita que
qualquer pessoa com o link do app crie uma conta sozinha.

O primeiro admin não passa pelo fluxo de convite (não existe admin nenhum pra convidar o
primeiro) — nasce por `npm run db:seed-admin`, que lê `ADMIN_NAME`/`ADMIN_EMAIL`/
`ADMIN_PASSWORD` do ambiente e nunca fica versionado.
