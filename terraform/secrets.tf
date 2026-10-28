# Generated database credentials, stored in AWS Secrets Manager.
# Use the same values for the Jenkins credentials "db-credentials" and "db-root-password".

resource "random_password" "db_root" {
  length  = 24
  special = false
}

resource "random_password" "db_app" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/mysql"
  description             = "MySQL credentials for the ${var.project} application"
  recovery_window_in_days = 0   # allows immediate re-create after destroy (demo-friendly); use 7-30 in production
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    MYSQL_ROOT_PASSWORD = random_password.db_root.result
    DB_USER             = "appuser"
    DB_PASSWORD         = random_password.db_app.result
    DB_NAME             = "taskdb"
  })
}
