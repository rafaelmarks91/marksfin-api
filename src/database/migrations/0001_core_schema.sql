-- MarksFin — schema principal (Marco 0)
-- Traduzido de ../../../marksfin-app/MODELO-DE-DADOS.md. snake_case, IDs em CHAR(36) (UUID),
-- dinheiro em DECIMAL(15,2), instantes técnicos em DATETIME(3) UTC, datas financeiras em DATE.

CREATE TABLE IF NOT EXISTS users (
  id CHAR(36) NOT NULL PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  email VARCHAR(190) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  status ENUM('ACTIVE', 'DISABLED') NOT NULL DEFAULT 'ACTIVE',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  UNIQUE KEY users_email_unique (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS financial_spaces (
  id CHAR(36) NOT NULL PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'BRL',
  timezone VARCHAR(60) NOT NULL DEFAULT 'America/Sao_Paulo',
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS space_members (
  id CHAR(36) NOT NULL PRIMARY KEY,
  space_id CHAR(36) NOT NULL,
  user_id CHAR(36) NOT NULL,
  role ENUM('OWNER', 'VIEWER') NOT NULL,
  joined_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  revoked_at DATETIME(3) NULL,
  UNIQUE KEY space_members_space_user_unique (space_id, user_id),
  KEY space_members_user_idx (user_id),
  KEY space_members_space_idx (space_id),
  CONSTRAINT fk_space_members_space FOREIGN KEY (space_id) REFERENCES financial_spaces (id) ON DELETE CASCADE,
  CONSTRAINT fk_space_members_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS invitations (
  id CHAR(36) NOT NULL PRIMARY KEY,
  space_id CHAR(36) NOT NULL,
  invited_by CHAR(36) NOT NULL,
  email VARCHAR(190) NOT NULL,
  role ENUM('OWNER', 'VIEWER') NOT NULL DEFAULT 'VIEWER',
  token_hash CHAR(64) NOT NULL,
  expires_at DATETIME(3) NOT NULL,
  accepted_at DATETIME(3) NULL,
  revoked_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY invitations_token_hash_unique (token_hash),
  KEY invitations_space_email_revoked_idx (space_id, email, revoked_at),
  CONSTRAINT fk_invitations_space FOREIGN KEY (space_id) REFERENCES financial_spaces (id) ON DELETE CASCADE,
  CONSTRAINT fk_invitations_inviter FOREIGN KEY (invited_by) REFERENCES users (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS accounts (
  id CHAR(36) NOT NULL PRIMARY KEY,
  space_id CHAR(36) NOT NULL,
  name VARCHAR(100) NOT NULL,
  type ENUM('CHECKING', 'SAVINGS', 'CASH', 'INVESTMENT', 'OTHER') NOT NULL,
  initial_balance DECIMAL(15, 2) NOT NULL,
  initial_balance_date DATE NOT NULL,
  color CHAR(7) NULL,
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  KEY accounts_space_archived_idx (space_id, is_archived),
  CONSTRAINT fk_accounts_space FOREIGN KEY (space_id) REFERENCES financial_spaces (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS categories (
  id CHAR(36) NOT NULL PRIMARY KEY,
  space_id CHAR(36) NOT NULL,
  name VARCHAR(80) NOT NULL,
  type ENUM('INCOME', 'EXPENSE') NOT NULL,
  icon VARCHAR(40) NULL,
  color CHAR(7) NULL,
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  KEY categories_space_type_archived_idx (space_id, type, is_archived),
  CONSTRAINT fk_categories_space FOREIGN KEY (space_id) REFERENCES financial_spaces (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS transactions (
  id CHAR(36) NOT NULL PRIMARY KEY,
  space_id CHAR(36) NOT NULL,
  account_id CHAR(36) NOT NULL,
  category_id CHAR(36) NULL,
  type ENUM('INCOME', 'EXPENSE', 'TRANSFER_IN', 'TRANSFER_OUT') NOT NULL,
  amount DECIMAL(15, 2) NOT NULL,
  description VARCHAR(160) NOT NULL,
  transaction_date DATE NOT NULL,
  notes TEXT NULL,
  transfer_group_id CHAR(36) NULL,
  created_by CHAR(36) NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  deleted_at DATETIME(3) NULL,
  KEY transactions_space_date_id_idx (space_id, transaction_date, id),
  KEY transactions_account_date_idx (account_id, transaction_date),
  KEY transactions_category_date_idx (category_id, transaction_date),
  KEY transactions_transfer_group_idx (transfer_group_id),
  CONSTRAINT fk_transactions_space FOREIGN KEY (space_id) REFERENCES financial_spaces (id) ON DELETE CASCADE,
  CONSTRAINT fk_transactions_account FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE,
  CONSTRAINT fk_transactions_category FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE CASCADE,
  CONSTRAINT fk_transactions_creator FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sessions (
  id CHAR(36) NOT NULL PRIMARY KEY,
  user_id CHAR(36) NOT NULL,
  token_hash CHAR(64) NOT NULL,
  expires_at DATETIME(3) NOT NULL,
  last_seen_at DATETIME(3) NOT NULL,
  ip_hash VARCHAR(64) NULL,
  user_agent VARCHAR(255) NULL,
  revoked_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY sessions_token_hash_unique (token_hash),
  KEY sessions_user_revoked_expires_idx (user_id, revoked_at, expires_at),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS password_resets (
  id CHAR(36) NOT NULL PRIMARY KEY,
  user_id CHAR(36) NOT NULL,
  token_hash CHAR(64) NOT NULL,
  expires_at DATETIME(3) NOT NULL,
  used_at DATETIME(3) NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UNIQUE KEY password_resets_token_hash_unique (token_hash),
  CONSTRAINT fk_password_resets_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  space_id CHAR(36) NOT NULL,
  actor_user_id CHAR(36) NOT NULL,
  action VARCHAR(80) NOT NULL,
  entity_type VARCHAR(50) NOT NULL,
  entity_id CHAR(36) NOT NULL,
  metadata JSON NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  KEY audit_logs_space_created_idx (space_id, created_at),
  CONSTRAINT fk_audit_logs_space FOREIGN KEY (space_id) REFERENCES financial_spaces (id) ON DELETE CASCADE,
  CONSTRAINT fk_audit_logs_actor FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
