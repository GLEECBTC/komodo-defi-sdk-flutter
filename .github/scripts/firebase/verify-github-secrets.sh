#!/bin/bash

# Verify Firebase GitHub Secrets Script (Updated)
# This script checks the current status of Firebase service accounts and GitHub secrets
# Updated to check for the actual service accounts in use

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_REPO="GLEECBTC/komodo-defi-sdk-flutter"
SDK_PROJECT_ID="komodo-defi-sdk"
PLAYGROUND_PROJECT_ID="komodo-playground"
# Updated to use the actual service account names
SDK_SERVICE_ACCOUNT_NAME="github-action-839744467"
PLAYGROUND_SERVICE_ACCOUNT_NAME="github-action-839744467"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Function to check if a command exists
check_command() {
    if command -v $1 &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# Function to check gcloud authentication
check_gcloud_auth() {
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        local account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
        print_success "Authenticated with gcloud as: ${account}"
        return 0
    else
        print_error "Not authenticated with gcloud"
        return 1
    fi
}

# Function to check GitHub CLI authentication
check_gh_auth() {
    if gh auth status &> /dev/null; then
        print_success "Authenticated with GitHub CLI"
        return 0
    else
        print_error "Not authenticated with GitHub CLI"
        return 1
    fi
}

# Function to check if service account exists
check_service_account() {
    local project_id=$1
    local service_account_name=$2
    local service_account_email="${service_account_name}@${project_id}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${service_account_email}" --project="${project_id}" &> /dev/null; then
        print_success "Service account exists: ${service_account_email}"
        return 0
    else
        print_error "Service account does not exist: ${service_account_email}"
        return 1
    fi
}

# Function to check service account permissions
check_permissions() {
    local project_id=$1
    local service_account_email=$2
    
    print_status "Checking permissions for ${service_account_email}..."
    
    # Get the IAM policy for the project
    local policy=$(gcloud projects get-iam-policy "${project_id}" --format=json 2>/dev/null)
    
    # Updated required roles - only checking for the essential ones
    local required_roles=(
        "roles/firebasehosting.admin"
    )
    
    # Optional but recommended roles
    local optional_roles=(
        "roles/firebase.rules.admin"
        "roles/iam.serviceAccountTokenCreator"
        "roles/firebaseauth.admin"
    )
    
    local missing_required=()
    local missing_optional=()
    
    # Check required roles
    for role in "${required_roles[@]}"; do
        if echo "${policy}" | jq -e ".bindings[] | select(.role == \"${role}\") | .members[] | select(. == \"serviceAccount:${service_account_email}\")" &> /dev/null; then
            print_success "  Has required permission: ${role}"
        else
            print_error "  Missing required permission: ${role}"
            missing_required+=("${role}")
        fi
    done
    
    # Check optional roles
    for role in "${optional_roles[@]}"; do
        if echo "${policy}" | jq -e ".bindings[] | select(.role == \"${role}\") | .members[] | select(. == \"serviceAccount:${service_account_email}\")" &> /dev/null; then
            print_success "  Has optional permission: ${role}"
        else
            print_warning "  Missing optional permission: ${role}"
            missing_optional+=("${role}")
        fi
    done
    
    if [ ${#missing_required[@]} -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to check GitHub secret
check_github_secret() {
    local secret_name=$1
    
    # Check if running in GitHub Actions or local
    local repo="${GITHUB_REPOSITORY:-${GITHUB_REPO}}"
    
    if gh secret list --repo "${repo}" 2>/dev/null | grep -q "^${secret_name}"; then
        local updated=$(gh secret list --repo "${repo}" | grep "^${secret_name}" | awk '{print $2}')
        print_success "GitHub secret exists: ${secret_name} (Updated: ${updated})"
        return 0
    else
        print_error "GitHub secret does not exist: ${secret_name}"
        return 1
    fi
}

# Function to check Firebase project
check_firebase_project() {
    local project_id=$1
    
    if gcloud projects describe "${project_id}" &> /dev/null; then
        print_success "Firebase project exists: ${project_id}"
        return 0
    else
        print_error "Firebase project does not exist or you don't have access: ${project_id}"
        return 1
    fi
}

# Main verification
main() {
    local all_checks_passed=true
    
    echo "================================================"
    echo "Firebase GitHub Secrets Verification (Updated)"
    echo "================================================"
    echo
    
    # Check prerequisites
    print_status "Checking prerequisites..."
    echo
    
    check_command "gcloud" || all_checks_passed=false
    check_command "gh" || all_checks_passed=false
    check_command "jq" || all_checks_passed=false
    echo
    
    # Check authentication
    print_status "Checking authentication..."
    echo
    
    check_gcloud_auth || all_checks_passed=false
    check_gh_auth || all_checks_passed=false
    echo
    
    # Check Firebase projects
    print_status "Checking Firebase projects..."
    echo
    
    check_firebase_project "${SDK_PROJECT_ID}" || all_checks_passed=false
    check_firebase_project "${PLAYGROUND_PROJECT_ID}" || all_checks_passed=false
    echo
    
    # Check komodo-defi-sdk setup
    print_status "Checking komodo-defi-sdk setup..."
    echo
    
    if check_service_account "${SDK_PROJECT_ID}" "${SDK_SERVICE_ACCOUNT_NAME}"; then
        check_permissions "${SDK_PROJECT_ID}" "${SDK_SERVICE_ACCOUNT_NAME}@${SDK_PROJECT_ID}.iam.gserviceaccount.com" || all_checks_passed=false
    else
        all_checks_passed=false
    fi
    echo
    
    # Check komodo-playground setup
    print_status "Checking komodo-playground setup..."
    echo
    
    if check_service_account "${PLAYGROUND_PROJECT_ID}" "${PLAYGROUND_SERVICE_ACCOUNT_NAME}"; then
        check_permissions "${PLAYGROUND_PROJECT_ID}" "${PLAYGROUND_SERVICE_ACCOUNT_NAME}@${PLAYGROUND_PROJECT_ID}.iam.gserviceaccount.com" || all_checks_passed=false
    else
        all_checks_passed=false
    fi
    echo
    
    # Check GitHub secrets
    print_status "Checking GitHub secrets..."
    echo
    
    check_github_secret "FIREBASE_SERVICE_ACCOUNT_KOMODO_DEFI_SDK" || all_checks_passed=false
    check_github_secret "FIREBASE_SERVICE_ACCOUNT_KOMODO_PLAYGROUND" || all_checks_passed=false
    echo
    
    # Summary
    echo "================================================"
    echo "Summary:"
    echo
    print_status "Service Accounts in use:"
    echo "  - SDK: github-action-839744467@komodo-defi-sdk.iam.gserviceaccount.com"
    echo "  - Playground: github-action-839744467@komodo-playground.iam.gserviceaccount.com"
    echo
    
    if [ "${all_checks_passed}" = true ]; then
        print_success "All required checks passed! Firebase secrets are properly configured."
        print_warning "Note: Some optional permissions may be missing but the setup should work fine."
    else
        print_error "Some required checks failed. Please review the errors above."
    fi
    echo "================================================"
}

# Run main function
main
