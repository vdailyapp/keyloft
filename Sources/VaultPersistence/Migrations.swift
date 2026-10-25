import Foundation
import GRDB

extension VaultDatabase {
    /// Toàn bộ migration của vault. v1 = schema giai đoạn 1 (SPEC-003 §3).
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(
                sql: """
                    CREATE TABLE secret (
                      id TEXT PRIMARY KEY NOT NULL,
                      kind TEXT NOT NULL,
                      label TEXT NOT NULL,
                      keychain_account TEXT NOT NULL UNIQUE,
                      requires_user_presence INTEGER NOT NULL,
                      created_at DOUBLE NOT NULL,
                      rotated_at DOUBLE
                    );
                    """)
            try db.execute(
                sql: """
                    CREATE TABLE oauth_client (
                      id TEXT PRIMARY KEY NOT NULL,
                      provider_id TEXT NOT NULL,
                      client_id TEXT NOT NULL,
                      client_secret_ref TEXT REFERENCES secret(id) ON DELETE SET NULL,
                      redirect_uri TEXT NOT NULL,
                      secret_expires_at DOUBLE,
                      label TEXT NOT NULL,
                      created_at DOUBLE NOT NULL
                    );
                    """)
            try db.execute(
                sql: """
                    CREATE TABLE account (
                      id TEXT PRIMARY KEY NOT NULL,
                      provider_id TEXT NOT NULL,
                      oauth_client_id TEXT NOT NULL REFERENCES oauth_client(id) ON DELETE RESTRICT,
                      external_id TEXT NOT NULL,
                      email TEXT,
                      display_name TEXT,
                      status TEXT NOT NULL,
                      status_changed_at DOUBLE NOT NULL,
                      created_at DOUBLE NOT NULL,
                      UNIQUE (provider_id, oauth_client_id, external_id)
                    );
                    """)
            try db.execute(
                sql: """
                    CREATE TABLE credential (
                      id TEXT PRIMARY KEY NOT NULL,
                      account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
                      refresh_token_ref TEXT NOT NULL REFERENCES secret(id) ON DELETE RESTRICT,
                      requested_scopes TEXT NOT NULL,
                      granted_scopes TEXT NOT NULL,
                      issued_at DOUBLE NOT NULL,
                      superseded_by TEXT REFERENCES credential(id) ON DELETE SET NULL,
                      status TEXT NOT NULL
                    );
                    CREATE INDEX credential_account ON credential(account_id, status, issued_at);
                    """)
            try db.execute(
                sql: """
                    CREATE TABLE health_check_result (
                      id TEXT PRIMARY KEY NOT NULL,
                      account_id TEXT NOT NULL REFERENCES account(id) ON DELETE CASCADE,
                      checked_at DOUBLE NOT NULL,
                      status TEXT NOT NULL,
                      checks TEXT NOT NULL
                    );
                    CREATE INDEX health_account_time ON health_check_result(account_id, checked_at DESC);
                    """)
            try db.execute(
                sql: """
                    CREATE TABLE audit_event (
                      id TEXT PRIMARY KEY NOT NULL,
                      actor TEXT NOT NULL,
                      action TEXT NOT NULL,
                      target TEXT NOT NULL,
                      scopes TEXT,
                      result TEXT NOT NULL,
                      timestamp DOUBLE NOT NULL
                    );
                    CREATE INDEX audit_time ON audit_event(timestamp DESC);
                    CREATE INDEX audit_target ON audit_event(target, timestamp DESC);
                    """)
            // Audit log chỉ được ghi thêm (SPEC-003 §3).
            try db.execute(
                sql: """
                    CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_event
                    BEGIN
                      SELECT RAISE(ABORT, 'audit_event is append-only');
                    END;
                    """)
            try db.execute(
                sql: """
                    CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_event
                    BEGIN
                      SELECT RAISE(ABORT, 'audit_event is append-only');
                    END;
                    """)
        }
        return migrator
    }
}
