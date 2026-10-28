#!/bin/bash
# Bootstraps Jenkins, Docker, Maven, Git, kubectl on Amazon Linux 2023
set -euxo pipefail

dnf update -y
dnf install -y java-17-amazon-corretto-headless docker git maven wget unzip

# kubectl (matches EKS 1.31 closely enough; kubectl supports +/-1 minor skew)
curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

# Jenkins LTS
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins

# Let Jenkins run Docker
systemctl enable --now docker
usermod -aG docker jenkins

systemctl enable --now jenkins
# Initial admin password: sudo cat /var/lib/jenkins/secrets/initialAdminPassword
