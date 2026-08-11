pipeline {
    agent any
    
    parameters {
        booleanParam(name: 'DESTROY_AND_REBUILD', defaultValue: false, description: 'Destroy Terraform resources first, then run a full fresh rebuild')
        booleanParam(name: 'REBUILD_IMAGE', defaultValue: false, description: 'Rebuild the Packer image first, else reuse the existing one')
    }

    environment {
        // Vault password fetched from Jenkins credentials (never hardcoded in Git)
        VAULT_PASS = credentials('ansible-vault-password')
        TF_IN_AUTOMATION = 'true'
    }

    stages {
        stage('Teardown Infrastructure') {
            when {
                expression { params.DESTROY_AND_REBUILD }
            }
            steps {
                dir('terraform') {
                    // Wiped workspace means a destroy button with nothing to destroy!
                    // In a production environment, state lives in a persistent remote backend 
                    // (e.g., S3, pg, Consul) so we can run a destroy even on a fresh Jenkins workspace.
                    sh 'terraform init'
                    sh 'terraform destroy -auto-approve'
                }
            }
        }

        stage('Build Golden Image') {
            when {
                expression { params.REBUILD_IMAGE || params.DESTROY_AND_REBUILD }
            }
            steps {
                dir('packer') {
                    sh '/usr/bin/packer init build.pkr.hcl'
                    sh '/usr/bin/packer build build.pkr.hcl'
                }
            }
        }

        stage('Provision Infrastructure') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                    sh 'terraform apply -auto-approve'
                }
            }
        }

        stage('Harden with Ansible') {
            steps {
                dir('ansible') {
                    // Install the pinned CIS role from requirements.yml
                    sh 'ansible-galaxy install -r requirements.yml -p roles/'
                    
                    // Create a dummy vault password file from the Jenkins credential for this run
                    sh 'echo $VAULT_PASS > vault_password.txt'

                    // Run the playbook, dynamically passing an extra-var to demonstrate 
                    // variable precedence (Level 3 - highest precedence, overriding play and group vars)
                    sh "ansible-playbook -i inventory/hosts.ini playbook.yml --vault-password-file vault_password.txt -e \"rhel9cis_warning_banner='JENKINS EXTRA-VARS BANNER'\""
                }
            }
        }

        stage('Audit & Compliance (Goss)') {
            steps {
                dir('ansible') {
                    // Goss runs as part of the lockdown role if setup_audit / run_audit are triggered.
                    // The report is generated natively by the role.
                    sh 'echo "Goss audit report ready for archival"' 
                }
            }
        }
    }

    post {
        always {
            // Archive the Goss report artifact back to Jenkins
            archiveArtifacts artifacts: '**/goss-report.json, **/goss-report.html, **/*-goss-report*', allowEmptyArchive: true
            
            // Clean up the workspace, ensuring no secrets or generated inventory are left behind
            cleanWs()
        }
        failure {
            echo 'Pipeline encountered an error. Failing loudly!'
        }
    }
}
