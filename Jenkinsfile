pipeline {
  agent { label 'docker' }

  options {
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '20'))
  }

  environment {
    IMAGE_REPO      = 'eliranb1978/eliran-apps-images'
    APP_REPO        = 'https://github.com/eliranbt-commits/sample-nodejs.git'
    GITOPS_REPO     = 'https://github.com/eliranbt-commits/gitops-sample-nodejs.git'
    GITOPS_DIR      = "${WORKSPACE}@tmp/gitops"

    DOCKERHUB_CREDS = 'dockerhub'
    GITHUB_CREDS    = 'github-bot'

    NODE_IMAGE      = 'node:22-alpine'
    SEMGREP_IMAGE   = 'semgrep/semgrep:latest'
    HADOLINT_IMAGE  = 'hadolint/hadolint:latest-debian'
    HELM_IMAGE      = 'alpine/helm:latest'
    TRIVY_IMAGE     = 'aquasec/trivy:latest'
  }

  stages {
    stage('Prepare') {
      steps {
        script {
          def msg = sh(returnStdout: true, script: 'git log -1 --pretty=%B').trim()
          env.SKIP_CI = (msg.contains('[skip ci]') || msg.contains('[ci skip]')) ? 'true' : 'false'

          def manual = !currentBuild.getBuildCauses('hudson.model.Cause$UserIdCause').isEmpty()
          env.IS_RELEASE = (env.BRANCH_NAME == 'main' && !env.CHANGE_ID && !manual) ? 'true' : 'false'

          if (env.SKIP_CI == 'true') {
            currentBuild.result = 'NOT_BUILT'
            currentBuild.description = 'Skipped: commit message contains [skip ci]'
          }
          echo "branch=${env.BRANCH_NAME} pr=${env.CHANGE_ID ?: '-'} release=${env.IS_RELEASE} skip=${env.SKIP_CI}"
        }
      }
    }

    stage('Checks') {
      when { expression { env.SKIP_CI != 'true' } }
      parallel {
        stage('SAST and lint') {
          stages {
            stage('npm audit') {
              steps {
                script {
                  withTool(env.NODE_IMAGE) {
                    dir('web-app') {
                      sh 'npm ci'
                      sh 'npm audit --audit-level=critical'
                    }
                  }
                }
              }
            }

            stage('Semgrep') {
              steps {
                script {
                  withTool(env.SEMGREP_IMAGE) {
                    sh '''
                      semgrep scan \
                        --config p/javascript \
                        --config p/nodejs \
                        --config p/owasp-top-ten \
                        --severity ERROR \
                        --error \
                        --metrics off
                    '''
                  }
                }
              }
            }

            stage('Hadolint') {
              steps {
                script {
                  withTool(env.HADOLINT_IMAGE) {
                    sh 'hadolint --failure-threshold error Dockerfile'
                  }
                }
              }
            }

            stage('Helm lint') {
              steps {
                script {
                  withTool(env.HELM_IMAGE) {
                    sh 'helm lint ./helm/sample-nodejs -f ./helm/sample-nodejs/values.yaml -f ./helm/sample-nodejs/values-gitops.yaml'
                  }
                }
              }
            }

            stage('Trivy filesystem scan') {
              steps {
                script {
                  withTool(env.TRIVY_IMAGE) {
                    sh 'trivy fs --scanners vuln,secret --severity CRITICAL --exit-code 1 --ignore-unfixed .'
                  }
                }
              }
            }
          }
        }

        stage('Resolve version') {
          steps {
            withCredentials([usernamePassword(credentialsId: env.GITHUB_CREDS, usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
              sh '''#!/bin/bash
                set -euo pipefail
                rm -rf "$GITOPS_DIR"
                git -c credential.helper= \
                    -c credential.helper='!f() { echo "username=$GIT_USER"; echo "password=$GIT_TOKEN"; }; f' \
                    clone --depth 1 "$GITOPS_REPO" "$GITOPS_DIR"
              '''
            }
            script {
              def current = sh(returnStdout: true, script: '''sed -n 's/^appVersion: "\\(.*\\)"/\\1/p' "$GITOPS_DIR/helm/sample-nodejs/Chart.yaml"''').trim()

              if (env.IS_RELEASE == 'true') {
                def msg = sh(returnStdout: true, script: 'git log -1 --pretty=%B').trim()
                def bump = 'patch'
                if (msg.contains('bump:minor')) { bump = 'minor' }
                if (msg.contains('bump:major')) { bump = 'major' }
                withEnv(["CURRENT=${current}", "BUMP=${bump}"]) {
                  env.VERSION = sh(returnStdout: true, script: 'bash scripts/next-version.sh "$CURRENT" "$BUMP"').trim()
                }
              } else {
                env.VERSION = "pr-${env.GIT_COMMIT.substring(0, 7)}"
              }
              echo "Resolved version: ${env.VERSION} (current appVersion: ${current})"
            }
          }
        }
      }
    }

    stage('Build and scan image') {
      when { expression { env.SKIP_CI != 'true' } }
      steps {
        sh 'docker build --pull -t "local-scan:$VERSION" .'
        sh 'docker save "local-scan:$VERSION" -o image.tar'
        script {
          withTool(env.TRIVY_IMAGE) {
            sh 'trivy image --input image.tar --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed --format table'
          }
        }
      }
    }

    stage('Push image') {
      when { expression { env.SKIP_CI != 'true' && env.IS_RELEASE == 'true' } }
      environment {
        DOCKER_CONFIG = "${WORKSPACE}@tmp/docker"
      }
      steps {
        withCredentials([usernamePassword(credentialsId: env.DOCKERHUB_CREDS, usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
          sh '''#!/bin/bash
            set -euo pipefail
            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
            docker tag "local-scan:$VERSION" "$IMAGE_REPO:$VERSION"
            docker tag "local-scan:$VERSION" "$IMAGE_REPO:sha-$GIT_COMMIT"
            docker push "$IMAGE_REPO:$VERSION"
            docker push "$IMAGE_REPO:sha-$GIT_COMMIT"
          '''
        }
      }
      post {
        always {
          sh 'docker logout || true'
        }
      }
    }

    stage('Pin image tag for ArgoCD') {
      when { expression { env.SKIP_CI != 'true' && env.IS_RELEASE == 'true' } }
      steps {
        withCredentials([usernamePassword(credentialsId: env.GITHUB_CREDS, usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
          sh '''#!/bin/bash
            set -euo pipefail
            git_auth() {
              git -c credential.helper= \
                  -c credential.helper='!f() { echo "username=$GIT_USER"; echo "password=$GIT_TOKEN"; }; f' \
                  "$@"
            }

            rm -rf "$GITOPS_DIR"
            git_auth clone "$GITOPS_REPO" "$GITOPS_DIR"
            cd "$GITOPS_DIR"
            git config user.name "jenkins-bot"
            git config user.email "jenkins-bot@users.noreply.github.com"
            mkdir -p helm/sample-nodejs
            cp -a "$WORKSPACE/helm/sample-nodejs/." helm/sample-nodejs/
            bash "$WORKSPACE/scripts/apply-version.sh" "$VERSION" "docker.io/$IMAGE_REPO" "$GITOPS_DIR"
            git add helm/sample-nodejs
            git diff --cached
            git commit -m "chore(release): $VERSION"
            git tag -f "v$VERSION"
            git_auth push origin HEAD:main
            git_auth push origin "v$VERSION" --force

            cd "$WORKSPACE"
            git config user.name "jenkins-bot"
            git config user.email "jenkins-bot@users.noreply.github.com"
            bash scripts/apply-version.sh "$VERSION" "docker.io/$IMAGE_REPO" "$WORKSPACE"
            git add helm/sample-nodejs/Chart.yaml helm/sample-nodejs/values-gitops.yaml web-app/package.json
            git diff --cached
            git commit -m "chore(release): $VERSION [skip ci]"
            git tag -f "v$VERSION"
            git_auth push "$APP_REPO" HEAD:main
            git_auth push "$APP_REPO" "v$VERSION" --force
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'rm -f image.tar'
      sh 'if [ -n "${VERSION:-}" ]; then docker image rm -f "local-scan:$VERSION" >/dev/null 2>&1 || true; fi'
    }
  }
}

// Tool containers run as the Jenkins agent user, whose HOME does not exist inside them;
// npm, semgrep, helm and trivy need a writable HOME for their caches.
def withTool(String image, Closure body) {
  withEnv(["HOME=${env.WORKSPACE}@tmp/home"]) {
    sh 'mkdir -p "$HOME"'
    docker.image(image).inside('--entrypoint=') {
      body()
    }
  }
}
