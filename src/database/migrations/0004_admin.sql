-- MarksFin — módulo de administração da plataforma.
--
-- Decisão de produto: o MarksFin deixa de ter cadastro público. Só um administrador (você)
-- cria/convida contas novas — cada amigo convidado vira dono de um espaço financeiro próprio e
-- independente (não é a mesma coisa que o convite de "visualizar meu espaço" que já existe em
-- `invitations`: aquele dá acesso VIEWER a um espaço existente; este cria uma conta nova do
-- zero). `sp_pbd_auth_cadastrar` passa a exigir um convite de cadastro válido.

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE AFTER status;

CREATE TABLE IF NOT EXISTS signup_invitations (
  id CHAR(36) NOT NULL PRIMARY KEY,
  invited_by CHAR(36) NOT NULL,
  email VARCHAR(190) NOT NULL,
  token_hash CHAR(64) NOT NULL,
  expires_at DATETIME(3) NOT NULL,
  accepted_at DATETIME(3) NULL,
  revoked_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY signup_invitations_token_hash_unique (token_hash),
  KEY signup_invitations_email_idx (email, revoked_at, accepted_at),
  CONSTRAINT fk_signup_invitations_invited_by FOREIGN KEY (invited_by) REFERENCES users (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_pbd_auth_cadastrar$$

-- pbd_id: auth_cadastrar — redefinida: agora exige um convite de cadastro válido
-- (`convite_token_hash`), emitido por um admin via admin_convite_criar. O e-mail cadastrado
-- precisa ser exatamente o e-mail convidado — não dá pra usar o convite de outra pessoa.
CREATE PROCEDURE sp_pbd_auth_cadastrar(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_name VARCHAR(120);
  DECLARE v_email VARCHAR(190);
  DECLARE v_password_hash VARCHAR(255);
  DECLARE v_convite_token_hash CHAR(64);
  DECLARE v_invite_id CHAR(36);
  DECLARE v_invite_email VARCHAR(190);
  DECLARE v_invite_expires_at DATETIME(3);
  DECLARE v_invite_accepted_at DATETIME(3);
  DECLARE v_invite_revoked_at DATETIME(3);
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
  SET v_convite_token_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.convite_token_hash'));

  IF v_name IS NULL OR v_name = '' OR v_email IS NULL OR v_email = '' OR v_password_hash IS NULL OR v_password_hash = ''
     OR v_convite_token_hash IS NULL OR v_convite_token_hash = '' THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'DADOS_OBRIGATORIOS', 'message', 'Informe nome, e-mail, senha e o convite.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT id, email, expires_at, accepted_at, revoked_at
      INTO v_invite_id, v_invite_email, v_invite_expires_at, v_invite_accepted_at, v_invite_revoked_at
      FROM signup_invitations
     WHERE token_hash = v_convite_token_hash
     LIMIT 1;

    IF v_invite_id IS NULL OR v_invite_accepted_at IS NOT NULL OR v_invite_revoked_at IS NOT NULL OR v_invite_expires_at <= CURRENT_TIMESTAMP(3) THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE, 'code', 'CONVITE_INVALIDO', 'message', 'Convite invalido, expirado ou ja utilizado.',
        'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    ELSEIF v_invite_email <> v_email THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE, 'code', 'CONVITE_EMAIL_DIVERGENTE', 'message', 'Este convite foi emitido para outro e-mail.',
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

        INSERT INTO users (id, name, email, password_hash, status, is_admin)
          VALUES (v_user_id, v_name, v_email, v_password_hash, 'ACTIVE', FALSE);

        INSERT INTO financial_spaces (id, name, currency, timezone)
          VALUES (v_space_id, v_space_name, 'BRL', 'America/Sao_Paulo');

        INSERT INTO space_members (id, space_id, user_id, role)
          VALUES (v_member_id, v_space_id, v_user_id, 'OWNER');

        UPDATE signup_invitations SET accepted_at = CURRENT_TIMESTAMP(3) WHERE id = v_invite_id;

        COMMIT;

        SET p_object_output = JSON_OBJECT(
          'success', TRUE, 'code', 'SUCCESS', 'message', 'Usuario cadastrado.',
          'data', JSON_OBJECT(
            'user', JSON_OBJECT('id', v_user_id, 'name', v_name, 'email', v_email, 'status', 'ACTIVE', 'is_admin', FALSE),
            'space', JSON_OBJECT('id', v_space_id, 'name', v_space_name, 'currency', 'BRL', 'timezone', 'America/Sao_Paulo', 'role', 'OWNER')
          ),
          'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
        );
      END IF;
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_auth_login$$

-- pbd_id: auth_login — redefinida só para incluir `is_admin` no usuário devolvido (front
-- precisa saber se mostra a área administrativa). Resto do comportamento é idêntico.
CREATE PROCEDURE sp_pbd_auth_login(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_email VARCHAR(190);
  DECLARE v_user_id CHAR(36);
  DECLARE v_name VARCHAR(120);
  DECLARE v_password_hash VARCHAR(255);
  DECLARE v_status VARCHAR(20);
  DECLARE v_is_admin BOOLEAN;
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
    SELECT id, name, password_hash, status, is_admin
      INTO v_user_id, v_name, v_password_hash, v_status, v_is_admin
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
          'user', JSON_OBJECT('id', v_user_id, 'name', v_name, 'email', v_email, 'password_hash', v_password_hash, 'status', v_status, 'is_admin', v_is_admin),
          'spaces', v_spaces
        ),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_auth_me$$

-- pbd_id: auth_me — redefinida só para incluir `is_admin`.
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
  DECLARE v_is_admin BOOLEAN;
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
    SELECT s.id, s.user_id, s.expires_at, s.revoked_at, u.name, u.email, u.status, u.is_admin
      INTO v_session_id, v_user_id, v_expires_at, v_revoked_at, v_name, v_email, v_status, v_is_admin
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
          'user', JSON_OBJECT('id', v_user_id, 'name', v_name, 'email', v_email, 'status', v_status, 'is_admin', v_is_admin),
          'spaces', v_spaces
        ),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_sessao_validar$$

-- pbd_id: sessao_validar — redefinida só para incluir `is_admin` (o middleware de
-- autenticação passa a saber, em toda rota, se quem chama é admin).
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
  DECLARE v_is_admin BOOLEAN;
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
    SELECT s.id, s.user_id, s.expires_at, s.revoked_at, u.name, u.email, u.status, u.is_admin
      INTO v_session_id, v_user_id, v_expires_at, v_revoked_at, v_name, v_email, v_status, v_is_admin
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
        'data', JSON_OBJECT('user', JSON_OBJECT('id', v_user_id, 'name', v_name, 'email', v_email, 'status', v_status, 'is_admin', v_is_admin)),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_admin_usuarios_listar$$

-- pbd_id: admin_usuarios_listar — só admin. Lista todo mundo cadastrado na plataforma.
CREATE PROCEDURE sp_pbd_admin_usuarios_listar(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_admin_user_id CHAR(36);
  DECLARE v_is_admin BOOLEAN;
  DECLARE v_users JSON;
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao listar usuarios.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_admin_user_id = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.admin_user_id'));
  SELECT is_admin INTO v_is_admin FROM users WHERE id = v_admin_user_id AND status = 'ACTIVE' LIMIT 1;

  IF v_is_admin IS NULL OR v_is_admin = FALSE THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ACESSO_NEGADO', 'message', 'Apenas administradores podem listar usuarios.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT COALESCE(JSON_ARRAYAGG(JSON_OBJECT(
             'id', u.id, 'name', u.name, 'email', u.email, 'status', u.status, 'is_admin', u.is_admin,
             'created_at', DATE_FORMAT(u.created_at, '%Y-%m-%dT%H:%i:%s.000Z'),
             'spaces_count', (SELECT COUNT(*) FROM space_members sm WHERE sm.user_id = u.id AND sm.revoked_at IS NULL)
           )), JSON_ARRAY())
      INTO v_users
      FROM users u
     ORDER BY u.created_at DESC;

    SET p_object_output = JSON_OBJECT(
      'success', TRUE, 'code', 'SUCCESS', 'message', 'Usuarios listados.',
      'data', JSON_OBJECT('users', v_users), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_admin_usuario_status_atualizar$$

-- pbd_id: admin_usuario_status_atualizar — só admin. Ativa/desativa um usuário; ao
-- desativar, revoga imediatamente todas as sessões ativas dele. Um admin não pode alterar o
-- próprio status por aqui (evita se trancar fora sem querer).
CREATE PROCEDURE sp_pbd_admin_usuario_status_atualizar(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_admin_user_id CHAR(36);
  DECLARE v_target_user_id CHAR(36);
  DECLARE v_status VARCHAR(20);
  DECLARE v_is_admin BOOLEAN;
  DECLARE v_target_exists CHAR(36);
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    ROLLBACK;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao atualizar usuario.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_admin_user_id = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.admin_user_id'));
  SET v_target_user_id = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.target_user_id'));
  SET v_status = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.status'));

  SELECT is_admin INTO v_is_admin FROM users WHERE id = v_admin_user_id AND status = 'ACTIVE' LIMIT 1;

  IF v_is_admin IS NULL OR v_is_admin = FALSE THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ACESSO_NEGADO', 'message', 'Apenas administradores podem alterar usuarios.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSEIF v_target_user_id IS NULL OR v_status NOT IN ('ACTIVE', 'DISABLED') THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'DADOS_OBRIGATORIOS', 'message', 'Informe o usuario e o novo status.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSEIF v_target_user_id = v_admin_user_id THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'OPERACAO_INVALIDA', 'message', 'Voce nao pode alterar o proprio status.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT id INTO v_target_exists FROM users WHERE id = v_target_user_id LIMIT 1;

    IF v_target_exists IS NULL THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE, 'code', 'USUARIO_NAO_ENCONTRADO', 'message', 'Usuario nao encontrado.',
        'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    ELSE
      START TRANSACTION;

      UPDATE users SET status = v_status WHERE id = v_target_user_id;

      IF v_status = 'DISABLED' THEN
        UPDATE sessions SET revoked_at = CURRENT_TIMESTAMP(3) WHERE user_id = v_target_user_id AND revoked_at IS NULL;
      END IF;

      COMMIT;

      SET p_object_output = JSON_OBJECT(
        'success', TRUE, 'code', 'SUCCESS', 'message', 'Usuario atualizado.',
        'data', JSON_OBJECT('user_id', v_target_user_id, 'status', v_status),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_admin_convite_criar$$

-- pbd_id: admin_convite_criar — só admin. Convida um e-mail novo pra criar conta própria.
-- Invalida convites anteriores não aceitos do mesmo e-mail antes de criar um novo.
CREATE PROCEDURE sp_pbd_admin_convite_criar(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_admin_user_id CHAR(36);
  DECLARE v_email VARCHAR(190);
  DECLARE v_token_hash CHAR(64);
  DECLARE v_expires_at DATETIME(3);
  DECLARE v_is_admin BOOLEAN;
  DECLARE v_existing_user CHAR(36);
  DECLARE v_invite_id CHAR(36);
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    ROLLBACK;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao criar convite.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_admin_user_id = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.admin_user_id'));
  SET v_email = LOWER(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.email'))));
  SET v_token_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.token_hash'));
  SET v_expires_at = REPLACE(REPLACE(JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.expires_at')), 'T', ' '), 'Z', '');

  SELECT is_admin INTO v_is_admin FROM users WHERE id = v_admin_user_id AND status = 'ACTIVE' LIMIT 1;

  IF v_is_admin IS NULL OR v_is_admin = FALSE THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ACESSO_NEGADO', 'message', 'Apenas administradores podem convidar novos usuarios.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSEIF v_email IS NULL OR v_email = '' OR v_token_hash IS NULL OR v_expires_at IS NULL THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'DADOS_OBRIGATORIOS', 'message', 'Informe o e-mail do convidado.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT id INTO v_existing_user FROM users WHERE email = v_email LIMIT 1;

    IF v_existing_user IS NOT NULL THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE, 'code', 'EMAIL_JA_CADASTRADO', 'message', 'Este e-mail ja tem uma conta.',
        'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    ELSE
      SET v_invite_id = UUID();

      START TRANSACTION;

      UPDATE signup_invitations SET revoked_at = CURRENT_TIMESTAMP(3)
       WHERE email = v_email AND accepted_at IS NULL AND revoked_at IS NULL;

      INSERT INTO signup_invitations (id, invited_by, email, token_hash, expires_at)
        VALUES (v_invite_id, v_admin_user_id, v_email, v_token_hash, v_expires_at);

      COMMIT;

      SET p_object_output = JSON_OBJECT(
        'success', TRUE, 'code', 'SUCCESS', 'message', 'Convite criado.',
        'data', JSON_OBJECT('invitation_id', v_invite_id, 'email', v_email, 'expires_at', v_expires_at),
        'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
      );
    END IF;
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_admin_convites_listar$$

-- pbd_id: admin_convites_listar — só admin. Lista convites de cadastro (pendente, aceito,
-- revogado ou expirado).
CREATE PROCEDURE sp_pbd_admin_convites_listar(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_admin_user_id CHAR(36);
  DECLARE v_is_admin BOOLEAN;
  DECLARE v_invites JSON;
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao listar convites.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_admin_user_id = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.admin_user_id'));
  SELECT is_admin INTO v_is_admin FROM users WHERE id = v_admin_user_id AND status = 'ACTIVE' LIMIT 1;

  IF v_is_admin IS NULL OR v_is_admin = FALSE THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ACESSO_NEGADO', 'message', 'Apenas administradores podem listar convites.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SELECT COALESCE(JSON_ARRAYAGG(JSON_OBJECT(
             'id', si.id, 'email', si.email,
             'status', CASE
               WHEN si.accepted_at IS NOT NULL THEN 'ACCEPTED'
               WHEN si.revoked_at IS NOT NULL THEN 'REVOKED'
               WHEN si.expires_at <= CURRENT_TIMESTAMP(3) THEN 'EXPIRED'
               ELSE 'PENDING'
             END,
             'created_at', DATE_FORMAT(si.created_at, '%Y-%m-%dT%H:%i:%s.000Z'),
             'expires_at', DATE_FORMAT(si.expires_at, '%Y-%m-%dT%H:%i:%s.000Z')
           )), JSON_ARRAY())
      INTO v_invites
      FROM signup_invitations si
     ORDER BY si.created_at DESC;

    SET p_object_output = JSON_OBJECT(
      'success', TRUE, 'code', 'SUCCESS', 'message', 'Convites listados.',
      'data', JSON_OBJECT('invitations', v_invites), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_admin_convite_revogar$$

-- pbd_id: admin_convite_revogar — só admin.
CREATE PROCEDURE sp_pbd_admin_convite_revogar(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_admin_user_id CHAR(36);
  DECLARE v_invitation_id CHAR(36);
  DECLARE v_is_admin BOOLEAN;
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao revogar convite.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_admin_user_id = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.admin_user_id'));
  SET v_invitation_id = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.invitation_id'));

  SELECT is_admin INTO v_is_admin FROM users WHERE id = v_admin_user_id AND status = 'ACTIVE' LIMIT 1;

  IF v_is_admin IS NULL OR v_is_admin = FALSE THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ACESSO_NEGADO', 'message', 'Apenas administradores podem revogar convites.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    UPDATE signup_invitations SET revoked_at = CURRENT_TIMESTAMP(3)
     WHERE id = v_invitation_id AND accepted_at IS NULL AND revoked_at IS NULL;

    SET p_object_output = JSON_OBJECT(
      'success', TRUE, 'code', 'SUCCESS', 'message', 'Convite revogado.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END IF;
END$$

DROP PROCEDURE IF EXISTS sp_pbd_convite_cadastro_obter_por_token$$

-- pbd_id: convite_cadastro_obter_por_token — pública (tela de cadastro usa antes de
-- mostrar o formulário). Só confirma validade e devolve o e-mail convidado.
CREATE PROCEDURE sp_pbd_convite_cadastro_obter_por_token(IN p_payload JSON, OUT p_object_output JSON)
BEGIN
  DECLARE v_token_hash CHAR(64);
  DECLARE v_invite_id CHAR(36);
  DECLARE v_email VARCHAR(190);
  DECLARE v_expires_at DATETIME(3);
  DECLARE v_accepted_at DATETIME(3);
  DECLARE v_revoked_at DATETIME(3);
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'ERRO_INTERNO', 'message', COALESCE(v_error_message, 'Erro ao consultar convite.'),
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END;

  SET v_token_hash = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.token_hash'));

  SELECT id, email, expires_at, accepted_at, revoked_at
    INTO v_invite_id, v_email, v_expires_at, v_accepted_at, v_revoked_at
    FROM signup_invitations
   WHERE token_hash = v_token_hash
   LIMIT 1;

  IF v_invite_id IS NULL OR v_accepted_at IS NOT NULL OR v_revoked_at IS NOT NULL OR v_expires_at <= CURRENT_TIMESTAMP(3) THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE, 'code', 'CONVITE_INVALIDO', 'message', 'Convite invalido, expirado ou ja utilizado.',
      'data', JSON_OBJECT(), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  ELSE
    SET p_object_output = JSON_OBJECT(
      'success', TRUE, 'code', 'SUCCESS', 'message', 'Convite valido.',
      'data', JSON_OBJECT('email', v_email), 'errors', JSON_ARRAY(), 'meta', JSON_OBJECT()
    );
  END IF;
END$$

DELIMITER ;

INSERT INTO sys_pbd_ctrl (pbd_id, procedure_alvo, descricao) VALUES
  ('admin_usuarios_listar', 'sp_pbd_admin_usuarios_listar', 'Lista todos os usuarios da plataforma (so admin).'),
  ('admin_usuario_status_atualizar', 'sp_pbd_admin_usuario_status_atualizar', 'Ativa/desativa um usuario (so admin).'),
  ('admin_convite_criar', 'sp_pbd_admin_convite_criar', 'Convida um e-mail para criar conta propria (so admin).'),
  ('admin_convites_listar', 'sp_pbd_admin_convites_listar', 'Lista convites de cadastro (so admin).'),
  ('admin_convite_revogar', 'sp_pbd_admin_convite_revogar', 'Revoga um convite de cadastro pendente (so admin).'),
  ('convite_cadastro_obter_por_token', 'sp_pbd_convite_cadastro_obter_por_token', 'Valida um convite de cadastro (publico).')
ON DUPLICATE KEY UPDATE procedure_alvo = VALUES(procedure_alvo), descricao = VALUES(descricao);
