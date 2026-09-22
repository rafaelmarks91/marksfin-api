-- MarksFin — PBDs do módulo de autenticação (ver backend-backlog.md).
--
-- Convenção de sigilo: nada reversível chega ao banco por aqui. Senha vem já com hash
-- Argon2id (calculado no backend, MariaDB não tem Argon2 nativo); tokens de sessão e de
-- recuperação de senha chegam só como hash SHA-256 (o valor bruto nunca é persistido,
-- só existe em memória no backend/e-mail); IP também chega só como hash (HMAC-SHA256 com
-- SESSION_SECRET como chave — nunca hash simples, o espaço de IPv4 é pequeno demais pra
-- resistir a força bruta sem chave). `sp_pbd_auth_login` é a única procedure que devolve
-- `password_hash`, e só para o backend verificar com Argon2id — descartado em seguida,
-- nunca sai da API.

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_pbd_auth_cadastrar$$

-- pbd_id: auth_cadastrar — cria usuário + espaço financeiro inicial + membership OWNER.
CREATE PROCEDURE sp_pbd_auth_cadastrar(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_name VARCHAR(120);
  DECLARE v_email VARCHAR(190);
  DECLARE v_password_hash VARCHAR(255);
  DECLARE v_user_id CHAR(36);
  DECLARE v_space_id CHAR(36);
  DECLARE v_member_id CHAR(36);
  DECLARE v_space_name VARCHAR(100);
  DECLARE v_existing_id CHAR(36);
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    ROLLBACK;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO',
      'message', COALESCE(v_error_message, 'Erro ao cadastrar usuario.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_name = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.name'));
  SET v_email = LOWER(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.email'))));
  SET v_password_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.password_hash'));

  IF v_name IS NULL OR v_name = '' OR v_email IS NULL OR v_email = '' OR v_password_hash IS NULL OR v_password_hash = '' THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'DADOS_OBRIGATORIOS', 'message', 'Informe nome, e-mail e senha.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT id INTO v_existing_id FROM users WHERE email = v_email LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE, 'code', 'EMAIL_JA_CADASTRADO', 'message', 'Este e-mail já está cadastrado.',
        'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    ELSE
      SET v_user_id = UUID();
      SET v_space_id = UUID();
      SET v_member_id = UUID();
      SET v_space_name = CONCAT('Finanças de ', v_name);

      START TRANSACTION;

      INSERT INTO users (id, name, email, password_hash, status)
        VALUES (v_user_id, v_name, v_email, v_password_hash, 'ACTIVE');

      INSERT INTO financial_spaces (id, name, currency, timezone)
        VALUES (v_space_id, v_space_name, 'BRL', 'America/Sao_Paulo');

      INSERT INTO space_members (id, space_id, user_id, role)
        VALUES (v_member_id, v_space_id, v_user_id, 'OWNER');

      COMMIT;

      SET p_object_output = JSON_OBJECT(
        'success', TRUE, 'code', 'SUCCESS', 'message', 'Usuario cadastrado.',
        'data', JSON_OBJECT(
          'user', JSON_OBJECT('id', v_user_id, 'name', v_name, 'email', v_email, 'status', 'ACTIVE'),
          'space', JSON_OBJECT('id', v_space_id, 'name', v_space_name, 'currency', 'BRL', 'timezone', 'America/Sao_Paulo', 'role', 'OWNER')
        ),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_auth_login$$

-- pbd_id: auth_login — localiza usuário ativo por e-mail. Única procedure que devolve
-- password_hash (para o backend verificar com Argon2id).
CREATE PROCEDURE sp_pbd_auth_login(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_email VARCHAR(190);
  DECLARE v_user_id CHAR(36);
  DECLARE v_name VARCHAR(120);
  DECLARE v_password_hash VARCHAR(255);
  DECLARE v_status VARCHAR(20);
  DECLARE v_spaces JSON;
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao autenticar.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_email = LOWER(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.email'))));

  IF v_email IS NULL OR v_email = '' THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'DADOS_OBRIGATORIOS', 'message', 'Informe e-mail e senha.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT id, name, password_hash, status
      INTO v_user_id, v_name, v_password_hash, v_status
      FROM users
     WHERE email = v_email AND status = 'ACTIVE'
     LIMIT 1;

    IF v_user_id IS NULL THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE, 'code', 'CREDENCIAIS_INVALIDAS', 'message', 'E-mail ou senha incorretos.',
        'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    ELSE
      SELECT COALESCE(JSON_ARRAYAGG(JSON_OBJECT(
               'id', fs.id, 'name', fs.name, 'currency', fs.currency, 'timezone', fs.timezone, 'role', sm.role
             )), JSON_ARRAY())
        INTO v_spaces
        FROM space_members sm
        JOIN financial_spaces fs ON fs.id = sm.space_id
       WHERE sm.user_id = v_user_id AND sm.revoked_at IS NULL;

      SET p_object_output = JSON_OBJECT(
        'success', TRUE, 'code', 'SUCCESS', 'message', 'Usuario localizado.',
        'data', JSON_OBJECT(
          'user', JSON_OBJECT('id', v_user_id, 'name', v_name, 'email', v_email, 'password_hash', v_password_hash, 'status', v_status),
          'spaces', v_spaces
        ),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_sessao_criar$$

-- pbd_id: sessao_criar — cria a sessão após o backend validar a senha com Argon2id.
-- token_hash e ip_hash já chegam hasheados; o valor bruto nunca passa pelo banco.
CREATE PROCEDURE sp_pbd_sessao_criar(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_user_id CHAR(36);
  DECLARE v_token_hash CHAR(64);
  DECLARE v_expires_at DATETIME(3);
  DECLARE v_ip_hash VARCHAR(64);
  DECLARE v_user_agent VARCHAR(255);
  DECLARE v_session_id CHAR(36);
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao criar sessao.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_user_id = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.user_id'));
  SET v_token_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.token_hash'));
  -- Aceita ISO 8601 (formato que Date.toISOString() do Node sempre produz); a conversao
  -- implicita do MariaDB nao entende o separador 'T' nem o sufixo 'Z' de UTC.
  SET v_expires_at = REPLACE(REPLACE(JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.expires_at')), 'T', ' '), 'Z', '');
  SET v_ip_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.ip_hash'));
  SET v_user_agent = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.user_agent'));

  IF v_user_id IS NULL OR v_token_hash IS NULL OR v_expires_at IS NULL THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'DADOS_OBRIGATORIOS', 'message', 'Dados de sessao incompletos.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SET v_session_id = UUID();

    INSERT INTO sessions (id, user_id, token_hash, expires_at, last_seen_at, ip_hash, user_agent)
      VALUES (v_session_id, v_user_id, v_token_hash, v_expires_at, CURRENT_TIMESTAMP(3), v_ip_hash, v_user_agent);

    SET p_object_output = JSON_OBJECT(
      'success', TRUE, 'code', 'SUCCESS', 'message', 'Sessao criada.',
      'data', JSON_OBJECT('session_id', v_session_id, 'expires_at', v_expires_at),
      'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_sessao_validar$$

-- pbd_id: sessao_validar — middleware de autenticação genérico (qualquer rota protegida).
-- Recebe só o hash do token; nunca o cookie em si.
CREATE PROCEDURE sp_pbd_sessao_validar(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_token_hash CHAR(64);
  DECLARE v_session_id CHAR(36);
  DECLARE v_user_id CHAR(36);
  DECLARE v_expires_at DATETIME(3);
  DECLARE v_revoked_at DATETIME(3);
  DECLARE v_name VARCHAR(120);
  DECLARE v_email VARCHAR(190);
  DECLARE v_status VARCHAR(20);
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao validar sessao.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_token_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.token_hash'));

  IF v_token_hash IS NULL OR v_token_hash = '' THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'SESSAO_INVALIDA', 'message', 'Sessao ausente.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT s.id, s.user_id, s.expires_at, s.revoked_at, u.name, u.email, u.status
      INTO v_session_id, v_user_id, v_expires_at, v_revoked_at, v_name, v_email, v_status
      FROM sessions s
      JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = v_token_hash
     LIMIT 1;

    IF v_session_id IS NULL OR v_revoked_at IS NOT NULL OR v_expires_at <= CURRENT_TIMESTAMP(3) OR v_status <> 'ACTIVE' THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE, 'code', 'SESSAO_INVALIDA', 'message', 'Sessao invalida ou expirada.',
        'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    ELSE
      UPDATE sessions SET last_seen_at = CURRENT_TIMESTAMP(3) WHERE id = v_session_id;

      SET p_object_output = JSON_OBJECT(
        'success', TRUE, 'code', 'SUCCESS', 'message', 'Sessao valida.',
        'data', JSON_OBJECT('user', JSON_OBJECT('id', v_user_id, 'name', v_name, 'email', v_email, 'status', v_status)),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_auth_logout$$

-- pbd_id: auth_logout — revoga a sessão pelo hash do token. Sempre success (idempotente:
-- não revela se o token era válido).
CREATE PROCEDURE sp_pbd_auth_logout(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_token_hash CHAR(64);
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao encerrar sessao.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_token_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.token_hash'));

  IF v_token_hash IS NOT NULL AND v_token_hash <> '' THEN
    UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP(3) WHERE token_hash = v_token_hash AND revoked_at IS NULL;
  END IF;

  SET p_object_output = JSON_OBJECT(
    'success', TRUE, 'code', 'SUCCESS', 'message', 'Sessao encerrada.',
    'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
  );
END$$

DROP PROCEDURE IF EXISTS sp_pbd_auth_me$$

-- pbd_id: auth_me — usuário autenticado + espaços disponíveis (GET /auth/me).
CREATE PROCEDURE sp_pbd_auth_me(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_token_hash CHAR(64);
  DECLARE v_session_id CHAR(36);
  DECLARE v_user_id CHAR(36);
  DECLARE v_expires_at DATETIME(3);
  DECLARE v_revoked_at DATETIME(3);
  DECLARE v_name VARCHAR(120);
  DECLARE v_email VARCHAR(190);
  DECLARE v_status VARCHAR(20);
  DECLARE v_spaces JSON;
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao carregar usuario.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_token_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.token_hash'));

  IF v_token_hash IS NULL OR v_token_hash = '' THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'SESSAO_INVALIDA', 'message', 'Sessao ausente.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT s.id, s.user_id, s.expires_at, s.revoked_at, u.name, u.email, u.status
      INTO v_session_id, v_user_id, v_expires_at, v_revoked_at, v_name, v_email, v_status
      FROM sessions s
      JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = v_token_hash
     LIMIT 1;

    IF v_session_id IS NULL OR v_revoked_at IS NOT NULL OR v_expires_at <= CURRENT_TIMESTAMP(3) OR v_status <> 'ACTIVE' THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE, 'code', 'SESSAO_INVALIDA', 'message', 'Sessao invalida ou expirada.',
        'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    ELSE
      UPDATE sessions SET last_seen_at = CURRENT_TIMESTAMP(3) WHERE id = v_session_id;

      SELECT COALESCE(JSON_ARRAYAGG(JSON_OBJECT(
               'id', fs.id, 'name', fs.name, 'currency', fs.currency, 'timezone', fs.timezone, 'role', sm.role
             )), JSON_ARRAY())
        INTO v_spaces
        FROM space_members sm
        JOIN financial_spaces fs ON fs.id = sm.space_id
       WHERE sm.user_id = v_user_id AND sm.revoked_at IS NULL;

      SET p_object_output = JSON_OBJECT(
        'success', TRUE, 'code', 'SUCCESS', 'message', 'Usuario autenticado.',
        'data', JSON_OBJECT(
          'user', JSON_OBJECT('id', v_user_id, 'name', v_name, 'email', v_email, 'status', v_status),
          'spaces', v_spaces
        ),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_auth_esqueci_senha$$

-- pbd_id: auth_esqueci_senha — gera token de recuperação se o e-mail existir. Resposta
-- idêntica exista ou não o e-mail (backend sempre responde 204); `deve_enviar_email` e o
-- nome só servem pra fila de e-mail do backend, nunca saem pro cliente HTTP. Invalida
-- tokens de recuperação anteriores ainda não usados, para não deixar vários links válidos.
CREATE PROCEDURE sp_pbd_auth_esqueci_senha(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_email VARCHAR(190);
  DECLARE v_token_hash CHAR(64);
  DECLARE v_expires_at DATETIME(3);
  DECLARE v_user_id CHAR(36);
  DECLARE v_name VARCHAR(120);
  DECLARE v_reset_id CHAR(36);
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    ROLLBACK;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao processar recuperacao.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_email = LOWER(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.email'))));
  SET v_token_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.token_hash'));
  -- Aceita ISO 8601 (formato que Date.toISOString() do Node sempre produz); a conversao
  -- implicita do MariaDB nao entende o separador 'T' nem o sufixo 'Z' de UTC.
  SET v_expires_at = REPLACE(REPLACE(JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.expires_at')), 'T', ' '), 'Z', '');

  IF v_email IS NULL OR v_email = '' OR v_token_hash IS NULL OR v_expires_at IS NULL THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'DADOS_OBRIGATORIOS', 'message', 'Dados incompletos.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT id, name INTO v_user_id, v_name FROM users WHERE email = v_email AND status = 'ACTIVE' LIMIT 1;

    IF v_user_id IS NOT NULL THEN
      SET v_reset_id = UUID();

      START TRANSACTION;

      UPDATE password_resets SET used_at = CURRENT_TIMESTAMP(3)
       WHERE user_id = v_user_id AND used_at IS NULL;

      INSERT INTO password_resets (id, user_id, token_hash, expires_at)
        VALUES (v_reset_id, v_user_id, v_token_hash, v_expires_at);

      COMMIT;
    END IF;

    SET p_object_output = JSON_OBJECT(
      'success', TRUE, 'code', 'SUCCESS', 'message', 'Solicitacao processada.',
      'data', JSON_OBJECT('deve_enviar_email', v_user_id IS NOT NULL, 'user_id', v_user_id, 'nome', v_name),
      'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_auth_redefinir_senha$$

-- pbd_id: auth_redefinir_senha — valida token de recuperação, troca a senha (já com hash
-- Argon2id calculado no backend) e revoga todas as sessões ativas do usuário.
CREATE PROCEDURE sp_pbd_auth_redefinir_senha(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_token_hash CHAR(64);
  DECLARE v_password_hash VARCHAR(255);
  DECLARE v_reset_id CHAR(36);
  DECLARE v_user_id CHAR(36);
  DECLARE v_expires_at DATETIME(3);
  DECLARE v_used_at DATETIME(3);
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    ROLLBACK;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao redefinir senha.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_token_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.token_hash'));
  SET v_password_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.password_hash'));

  IF v_token_hash IS NULL OR v_password_hash IS NULL THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'DADOS_OBRIGATORIOS', 'message', 'Dados incompletos.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT id, user_id, expires_at, used_at
      INTO v_reset_id, v_user_id, v_expires_at, v_used_at
      FROM password_resets
     WHERE token_hash = v_token_hash
     LIMIT 1;

    IF v_reset_id IS NULL OR v_used_at IS NOT NULL OR v_expires_at <= CURRENT_TIMESTAMP(3) THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE, 'code', 'TOKEN_INVALIDO', 'message', 'Token de recuperacao invalido ou expirado.',
        'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    ELSE
      START TRANSACTION;

      UPDATE users SET password_hash = v_password_hash WHERE id = v_user_id;
      UPDATE password_resets SET used_at = CURRENT_TIMESTAMP(3) WHERE id = v_reset_id;
      UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP(3) WHERE user_id = v_user_id AND revoked_at IS NULL;

      COMMIT;

      SET p_object_output = JSON_OBJECT(
        'success', TRUE, 'code', 'SUCCESS', 'message', 'Senha redefinida.',
        'data', JSON_OBJECT('user_id', v_user_id),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DELIMITER ;

INSERT INTO sys_pbd_ctrl (pbd_id, procedure_alvo, descricao) VALUES
  ('auth_cadastrar', 'sp_pbd_auth_cadastrar', 'Cria usuario e espaco financeiro inicial.'),
  ('auth_login', 'sp_pbd_auth_login', 'Localiza usuario por e-mail para verificacao de senha no backend.'),
  ('sessao_criar', 'sp_pbd_sessao_criar', 'Cria sessao apos login validado no backend.'),
  ('sessao_validar', 'sp_pbd_sessao_validar', 'Valida sessao por hash do token (middleware de autenticacao).'),
  ('auth_logout', 'sp_pbd_auth_logout', 'Revoga a sessao pelo hash do token.'),
  ('auth_me', 'sp_pbd_auth_me', 'Usuario autenticado e espacos disponiveis.'),
  ('auth_esqueci_senha', 'sp_pbd_auth_esqueci_senha', 'Gera token de recuperacao de senha se o e-mail existir.'),
  ('auth_redefinir_senha', 'sp_pbd_auth_redefinir_senha', 'Valida token e redefine senha, revogando sessoes ativas.')
ON DUPLICATE KEY UPDATE procedure_alvo = VALUES(procedure_alvo), descricao = VALUES(descricao);
