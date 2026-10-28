output "region" {
  value = var.region
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "jenkins_url" {
  value = "http://${aws_eip.jenkins.public_ip}:8080"
}

output "sonarqube_url" {
  value = "http://${aws_instance.sonarqube.public_ip}:9000"
}

output "sonarqube_private_url" {
  description = "Use this URL in Jenkins (Manage Jenkins -> System -> SonarQube servers)"
  value       = "http://${aws_instance.sonarqube.private_ip}:9000"
}

output "db_secret_name" {
  value = aws_secretsmanager_secret.db.name
}

output "read_db_secret" {
  description = "Command to read the generated DB credentials"
  value       = "aws secretsmanager get-secret-value --region ${var.region} --secret-id ${aws_secretsmanager_secret.db.name} --query SecretString --output text"
}
