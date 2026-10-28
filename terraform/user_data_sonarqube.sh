#!/bin/bash
# SonarQube Community in Docker on Amazon Linux 2023
set -euxo pipefail

dnf update -y
dnf install -y docker
systemctl enable --now docker

# Elasticsearch inside SonarQube requires these kernel settings
sysctl -w vm.max_map_count=262144
sysctl -w fs.file-max=65536
echo "vm.max_map_count=262144" >> /etc/sysctl.d/99-sonarqube.conf
echo "fs.file-max=65536"       >> /etc/sysctl.d/99-sonarqube.conf

docker volume create sonar_data
docker volume create sonar_extensions
docker volume create sonar_logs

docker run -d --name sonarqube --restart unless-stopped \
  -p 9000:9000 \
  -v sonar_data:/opt/sonarqube/data \
  -v sonar_extensions:/opt/sonarqube/extensions \
  -v sonar_logs:/opt/sonarqube/logs \
  sonarqube:community

# First login: admin / admin (you will be asked to change it)
