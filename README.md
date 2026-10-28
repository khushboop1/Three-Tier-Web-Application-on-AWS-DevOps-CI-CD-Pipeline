# Three-tier Java app on AWS EKS (Terraform + Jenkins + SonarQube + DockerHub)

```
Browser -> [LoadBalancer] -> frontend (nginx) -> backend (Spring Boot) -> MySQL (StatefulSet + EBS gp3)
```

## Layout

| Path | What it is |
|------|-----------|
| `backend/` | Spring Boot 3 / Java 17 REST API (`/api/tasks`), JPA + MySQL, JUnit tests, JaCoCo, Sonar plugin, multi-stage `Dockerfile` |
| `frontend/` | Static page + nginx (proxies `/api/` to the `backend` Service), `Dockerfile` |
| `docker-compose.yml` | Run all three tiers locally |
| `k8s/` | Namespace, StorageClass, Secret, ConfigMap, MySQL StatefulSet, backend/frontend Deployments, Services, HPA |
| `Jenkinsfile` | Build, Test, SonarQube, Quality Gate, Docker build, DockerHub push, EKS deploy, rollout verify, rollback on failure |
| `terraform/` | VPC, EKS (managed nodes + EBS CSI), Jenkins EC2, SonarQube EC2, Secrets Manager |

## 1. Try it locally

```bash
docker compose up --build
# open http://localhost:8081
```

## 2. Provision AWS

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set allowed_cidr to your public IP/32
terraform init
terraform plan
terraform apply                                # EKS takes ~15 minutes
```

Useful outputs afterwards: `jenkins_url`, `sonarqube_url`, `sonarqube_private_url`, `configure_kubectl`, `read_db_secret`.

Cost note: EKS control plane, a NAT gateway, 2 worker nodes and 2 EC2 hosts bill hourly. Run `terraform destroy` when finished
(delete the `frontend` Service first with `kubectl -n taskapp delete svc frontend` so the AWS load balancer is removed cleanly).

## 3. Configure Jenkins and SonarQube (one-time)

1. **SonarQube** (`sonarqube_url`): log in as `admin`/`admin`, change the password, then *My Account -> Security -> Generate token*.
   Add a webhook: *Administration -> Configuration -> Webhooks* -> `http://<jenkins-private-or-public-ip>:8080/sonarqube-webhook/`.
2. **Jenkins** (`jenkins_url`): get the unlock password with
   `sudo cat /var/lib/jenkins/secrets/initialAdminPassword` (SSH or SSM Session Manager), install suggested plugins, then add
   plugins *SonarQube Scanner*, *Docker Pipeline*.
3. *Manage Jenkins -> System -> SonarQube servers*: name `sonar-server`, URL = `sonarqube_private_url`, token = the token from step 1.
4. *Manage Jenkins -> Credentials*, add:
   - `dockerhub-creds`: Username with password (DockerHub username + access token)
   - `db-credentials`: Username with password (`appuser` + `DB_PASSWORD` from Secrets Manager)
   - `db-root-password`: Secret text (`MYSQL_ROOT_PASSWORD` from Secrets Manager)
5. Create a *Pipeline* job from SCM pointing at your Git repo (script path `Jenkinsfile`).
6. Edit the `environment {}` block of the `Jenkinsfile`: `DOCKERHUB_USER`, and `AWS_REGION`/`EKS_CLUSTER` if you changed them.

## 4. Run the pipeline

Push to Git and click **Build Now**. The last stage prints the pods and Services. Get the public address with:

```bash
aws eks update-kubeconfig --region ap-south-1 --name taskapp-eks
kubectl -n taskapp get svc frontend      # EXTERNAL-IP is the load balancer DNS name
```

## Deploying manually (without Jenkins)

```bash
kubectl apply -f k8s/00-namespace.yaml -f k8s/01-storageclass.yaml
kubectl -n taskapp create secret generic db-credentials \
  --from-literal=MYSQL_ROOT_PASSWORD='...' --from-literal=DB_USER=appuser --from-literal=DB_PASSWORD='...'
# edit DOCKERHUB_USER in k8s/05-backend.yaml and k8s/06-frontend.yaml first
kubectl apply -f k8s/03-configmap.yaml -f k8s/04-mysql.yaml -f k8s/05-backend.yaml -f k8s/06-frontend.yaml
```

## Things to harden before production

- Run Jenkins and SonarQube behind HTTPS (ALB + ACM) and restrict access; the demo uses plain HTTP limited to `allowed_cidr`.
- Use one NAT gateway per AZ, multi-replica or managed MySQL (RDS) instead of a single StatefulSet pod, and set a real Secrets Manager recovery window.
- Add an Ingress with TLS instead of a bare LoadBalancer Service, plus NetworkPolicies.
- Pin image digests, and scan images with Trivy in the pipeline.
