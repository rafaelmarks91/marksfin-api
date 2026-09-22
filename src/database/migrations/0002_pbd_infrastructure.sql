-- MarksFin — infraestrutura de PBD (stored procedures de regra de negócio).
-- Schema único (este banco `marksfin`) — projeto não comercializado, sem separação por domínio.

CREATE TABLE IF NOT EXISTS sys_pbd_ctrl (
  pbd_id VARCHAR(80) NOT NULL PRIMARY KEY,
  pbd_versao VARCHAR(10) NOT NULL DEFAULT 'v1',
  procedure_alvo VARCHAR(128) NOT NULL,
  ativo BOOLEAN NOT NULL DEFAULT TRUE,
  descricao VARCHAR(255) NULL,
  criado_em DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_sys_execucao_pbd$$

-- Executor universal: recebe o payload JSON (precisa de `pbd_id`), consulta sys_pbd_ctrl
-- para achar a procedure real e despacha via SQL dinâmico. Toda procedure de negócio deve
-- seguir a assinatura `(IN p_payload JSON, OUT p_object_output JSON)`.
CREATE PROCEDURE sp_sys_execucao_pbd(
  IN p_payload JSON,
  OUT p_object_output JSON
)
BEGIN
  DECLARE v_pbd_id VARCHAR(80);
  DECLARE v_procedure VARCHAR(128);
  DECLARE v_ativo BOOLEAN;
  DECLARE v_sql TEXT;
  DECLARE v_error_message TEXT DEFAULT NULL;

  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
    SET p_object_output = JSON_OBJECT(
      'success', FALSE,
      'code', 'PBD_EXECUTION_ERROR',
      'message', COALESCE(v_error_message, 'Erro ao executar PBD.'),
      'data', JSON_OBJECT(),
      'errors', JSON_ARRAY(),
      'meta', JSON_OBJECT()
    );
  END;

  SET v_pbd_id = JSON_UNQUOTE(JSON_EXTRACT(p_payload, '$.pbd_id'));

  IF v_pbd_id IS NULL OR v_pbd_id = '' THEN
    SET p_object_output = JSON_OBJECT(
      'success', FALSE,
      'code', 'PBD_ID_OBRIGATORIO',
      'message', 'Informe pbd_id no payload.',
      'data', JSON_OBJECT(),
      'errors', JSON_ARRAY(),
      'meta', JSON_OBJECT()
    );
  ELSE
    SELECT procedure_alvo, ativo
      INTO v_procedure, v_ativo
      FROM sys_pbd_ctrl
     WHERE pbd_id = v_pbd_id
     LIMIT 1;

    IF v_procedure IS NULL THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE,
        'code', 'PBD_NAO_ENCONTRADO',
        'message', CONCAT('pbd_id nao cadastrado em sys_pbd_ctrl: ', v_pbd_id),
        'data', JSON_OBJECT(),
        'errors', JSON_ARRAY(),
        'meta', JSON_OBJECT()
      );
    ELSEIF v_ativo = FALSE THEN
      SET p_object_output = JSON_OBJECT(
        'success', FALSE,
        'code', 'PBD_INATIVO',
        'message', CONCAT('pbd_id inativo: ', v_pbd_id),
        'data', JSON_OBJECT(),
        'errors', JSON_ARRAY(),
        'meta', JSON_OBJECT()
      );
    ELSE
      SET @mf_pbd_payload = p_payload;
      SET v_sql = CONCAT('CALL ', v_procedure, '(@mf_pbd_payload, @mf_pbd_object_output)');
      PREPARE mf_pbd_stmt FROM v_sql;
      EXECUTE mf_pbd_stmt;
      DEALLOCATE PREPARE mf_pbd_stmt;
      SET p_object_output = @mf_pbd_object_output;
      SET @mf_pbd_payload = NULL;
      SET @mf_pbd_object_output = NULL;
    END IF;
  END IF;
END$$

DELIMITER ;
