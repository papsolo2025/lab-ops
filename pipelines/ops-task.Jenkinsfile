// Generic runner for every scheduled automation job.
// Each job (created by jobs/automation.groovy) passes TASK = the script name in scripts/.
// Exit codes from scripts: 0 = OK (green), 1 = WARN (yellow/UNSTABLE), 2+ = FAIL (red).
//
// Jenkins credentials used (create them once - see the lab guide, Day 6):
//   lab-ssh-key    SSH username with private key (user: ubuntu) - Ansible jobs
//   slack-webhook  Secret text (use the value "none" if you have no Slack)
//   nexus-admin    Username with password - Nexus health job
//   lab-tfvars     Secret file (your terraform.tfvars) - drift check

pipeline {
  agent any
  options {
    timestamps()
    timeout(time: 90, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '30'))
    disableConcurrentBuilds()
  }
  environment {
    REPORT_DIR = "${WORKSPACE}/reports"
  }
  stages {
    stage('Run task') {
      steps {
        script {
          currentBuild.description = params.TASK
          def rc = 0
          withCredentials([
            sshUserPrivateKey(credentialsId: 'lab-ssh-key', keyFileVariable: 'SSH_KEY_FILE'),
            string(credentialsId: 'slack-webhook', variable: 'SLACK_WEBHOOK_URL'),
            usernamePassword(credentialsId: 'nexus-admin', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS'),
            file(credentialsId: 'lab-tfvars', variable: 'TFVARS_FILE'),
          ]) {
            rc = sh(script: 'rm -rf "$REPORT_DIR" && mkdir -p "$REPORT_DIR" && bash "scripts/${TASK}.sh"', returnStatus: true)
          }
          if (rc == 1) {
            unstable("${params.TASK} finished with warnings")
          } else if (rc != 0) {
            error("${params.TASK} failed (exit ${rc})")
          }
        }
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true
    }
  }
}
