// Declarative pipeline: Build -> Test -> SonarQube -> Docker -> DockerHub -> EKS
//
// Jenkins prerequisites (see README.md):
//   Plugins : Pipeline, Git, Docker Pipeline, SonarQube Scanner, JUnit, Credentials Binding
//   Tools   : "maven-3" (Maven) configured in Manage Jenkins -> Tools, or Maven on the agent PATH
//   Server  : "sonar-server" in Manage Jenkins -> System -> SonarQube servers (with token)
//   Creds   : dockerhub-creds   (Username with password)
//             db-credentials    (Username with password -> app DB user / password)
//             db-root-password  (Secret text)
//   AWS     : Jenkins EC2 uses an instance profile with EKS access (created by ../terraform),
//             so no AWS keys are stored in Jenkins.

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '15'))
        timeout(time: 45, unit: 'MINUTES')
    }

    environment {
        DOCKERHUB_USER = 'your-dockerhub-username'   // <-- change
        BACKEND_IMAGE  = "${DOCKERHUB_USER}/taskapp-backend"
        FRONTEND_IMAGE = "${DOCKERHUB_USER}/taskapp-frontend"
        IMAGE_TAG      = "${env.BUILD_NUMBER}"
        AWS_REGION     = 'ap-south-1'                // <-- match terraform
        EKS_CLUSTER    = 'taskapp-eks'               // <-- match terraform
        K8S_NAMESPACE  = 'taskapp'
        SONAR_PROJECT  = 'taskapp'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                dir('backend') {
                    sh 'mvn -B -DskipTests clean package'
                }
            }
        }

        stage('Test') {
            steps {
                dir('backend') {
                    sh 'mvn -B test'
                }
            }
            post {
                always {
                    junit allowEmptyResults: true, testResults: 'backend/target/surefire-reports/*.xml'
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                dir('backend') {
                    withSonarQubeEnv('sonar-server') {
                        sh """
                          mvn -B sonar:sonar \
                            -Dsonar.projectKey=${SONAR_PROJECT} \
                            -Dsonar.projectName=${SONAR_PROJECT}
                        """
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    // Needs a webhook in SonarQube: http://<jenkins>:8080/sonarqube-webhook/
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh """
                  docker build -t ${BACKEND_IMAGE}:${IMAGE_TAG}  -t ${BACKEND_IMAGE}:latest  backend
                  docker build -t ${FRONTEND_IMAGE}:${IMAGE_TAG} -t ${FRONTEND_IMAGE}:latest frontend
                """
            }
        }

        stage('Push to DockerHub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                                                  usernameVariable: 'DH_USER',
                                                  passwordVariable: 'DH_PASS')]) {
                    sh '''
                      echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
                      docker push ${BACKEND_IMAGE}:${IMAGE_TAG}
                      docker push ${BACKEND_IMAGE}:latest
                      docker push ${FRONTEND_IMAGE}:${IMAGE_TAG}
                      docker push ${FRONTEND_IMAGE}:latest
                      docker logout
                    '''
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'db-credentials',
                                     usernameVariable: 'DB_USER_VAL',
                                     passwordVariable: 'DB_PASS_VAL'),
                    string(credentialsId: 'db-root-password', variable: 'DB_ROOT_VAL')
                ]) {
                    sh '''
                      set -e
                      aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_CLUSTER"

                      # Render manifests with the new image tags into a scratch folder
                      rm -rf .rendered && mkdir .rendered
                      cp k8s/*.yaml .rendered/
                      rm .rendered/02-secret.yaml      # real secret is created below from Jenkins credentials
                      sed -i "s|DOCKERHUB_USER/taskapp-backend:latest|${BACKEND_IMAGE}:${IMAGE_TAG}|"   .rendered/05-backend.yaml
                      sed -i "s|DOCKERHUB_USER/taskapp-frontend:latest|${FRONTEND_IMAGE}:${IMAGE_TAG}|" .rendered/06-frontend.yaml

                      kubectl apply -f .rendered/00-namespace.yaml
                      kubectl apply -f .rendered/01-storageclass.yaml

                      kubectl -n "$K8S_NAMESPACE" create secret generic db-credentials \
                        --from-literal=MYSQL_ROOT_PASSWORD="$DB_ROOT_VAL" \
                        --from-literal=DB_USER="$DB_USER_VAL" \
                        --from-literal=DB_PASSWORD="$DB_PASS_VAL" \
                        --dry-run=client -o yaml | kubectl apply -f -

                      kubectl apply -f .rendered/03-configmap.yaml
                      kubectl apply -f .rendered/04-mysql.yaml
                      kubectl -n "$K8S_NAMESPACE" rollout status statefulset/mysql --timeout=300s

                      kubectl apply -f .rendered/05-backend.yaml
                      kubectl apply -f .rendered/06-frontend.yaml
                    '''
                }
            }
        }

        stage('Verify Rollout') {
            steps {
                sh '''
                  kubectl -n "$K8S_NAMESPACE" rollout status deployment/backend  --timeout=240s
                  kubectl -n "$K8S_NAMESPACE" rollout status deployment/frontend --timeout=240s
                  kubectl -n "$K8S_NAMESPACE" get pods,svc
                '''
            }
        }
    }

    post {
        failure {
            // Roll back the app tiers if a deploy went bad
            sh '''
              kubectl -n "$K8S_NAMESPACE" rollout undo deployment/backend  || true
              kubectl -n "$K8S_NAMESPACE" rollout undo deployment/frontend || true
            '''
            echo 'Pipeline failed - attempted rollback of backend and frontend.'
        }
        always {
            sh 'docker image prune -f || true'
            cleanWs()
        }
    }
}
