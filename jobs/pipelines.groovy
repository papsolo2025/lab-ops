// Job DSL: the application CI/CD pipeline (multibranch: every branch builds, main deploys to prod).
// Jenkins is only reachable from your IP, so GitHub webhooks can't reach it - Jenkins polls instead.
multibranchPipelineJob('orders-api') {
  description('orders-api CI/CD: tests, SonarQube, Trivy, ECR, Helm, deploy dev/staging/prod')
  branchSources {
    branchSource {
      source {
        git {
          id('orders-api')
          remote(LAB_APP_REPO)
        }
      }
    }
  }
  triggers {
    periodicFolderTrigger {
      interval('5m')
    }
  }
  orphanedItemStrategy {
    discardOldItems {
      numToKeep(5)
    }
  }
}

// Lambda functions: test, scan, package, versioned deploy with alias switch and rollback
multibranchPipelineJob('lab-serverless') {
  description('Lambda CI/CD: tests, SonarQube, Trivy, package, publish version, smoke test, move live alias')
  branchSources {
    branchSource {
      source {
        git {
          id('lab-serverless')
          remote(LAB_SERVERLESS_REPO)
        }
      }
    }
  }
  triggers {
    periodicFolderTrigger {
      interval('5m')
    }
  }
  orphanedItemStrategy {
    discardOldItems {
      numToKeep(5)
    }
  }
}
