#!/bin/bash

# Setup Firebase GitHub Secrets Script
# This script automates the creation and configuration of Firebase service accounts
# and GitHub secrets for the Komodo DeFi SDK Flutter project

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
SDK_SERVICE_ACCOUNT_NAME="github-actions-deploy"
PLAYGROUND_SERVICE_ACCOUNT_NAME="github-actions-deploy"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if a command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed. Please install it first."
        return 1
    fi
    return 0
}

# Function to check if user is authenticated with gcloud
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "Not authenticated with gcloud. Please run: gcloud auth login"
        return 1
    fi
    return 0
}

# Function to check if user is authenticated with gh
check_gh_auth() {
    if ! gh auth status &> /dev/null; then
        print_error "Not authenticated with GitHub CLI. Please run: gh auth login"
        return 1
    fi
    return 0
}

# Function to create service account if it doesn't exist
create_service_account_if_needed() {
    local project_id=$1
    local service_account_name=$2
    local service_account_email="${service_account_name}@${project_id}.iam.gserviceaccount.com"
    
    print_status "Checking if service account ${service_account_email} exists..."
    
    if gcloud iam service-accounts describe "${service_account_email}" --project="${project_id}" &> /dev/null; then
        print_status "Service account already exists"
    else
        print_status "Creating service account..."
        gcloud iam service-accounts create "${service_account_name}" \
            --display-name="GitHub Actions Deploy" \
            --description="Service account for GitHub Actions Firebase deployments" \
            --project="${project_id}"
        print_success "Service account created"
    fi
}

# Function to grant necessary permissions to service account
grant_permissions() {
    local project_id=$1
    local service_account_email=$2
    
    print_status "Granting permissions to ${service_account_email}..."
    
    # Array of roles to grant
    local roles=(
        "roles/firebase.hosting.admin"
        "roles/firebase.rules.admin"
        "roles/iam.serviceAccountTokenCreator"
    )
    
    for role in "${roles[@]}"; do
        print_status "Granting ${role}..."
        gcloud projects add-iam-policy-binding "${project_id}" \
            --member="serviceAccount:${service_account_email}" \
            --role="${role}" \
            --quiet &> /dev/null || true
    done
    
    print_success "Permissions granted"
}

# Function to generate service account key
generate_service_account_key() {
    local project_id=$1
    local service_account_name=$2
    local key_file=$3
    local service_account_email="${service_account_name}@${project_id}.iam.gserviceaccount.com"
    
    print_status "Generating service account key for ${service_account_email}..."
    
    gcloud iam service-accounts keys create "${key_file}" \
        --iam-account="${service_account_email}" \
        --project="${project_id}"
    
    print_success "Service account key generated: ${key_file}"
}

# Function to create or update GitHub secret
create_github_secret() {
    local secret_name=$1
    local key_file=$2
    
    print_status "Creating/updating GitHub secret: ${secret_name}..."
    
    # Check if running in GitHub Actions or local
    if [ -n "$GITHUB_REPOSITORY" ]; then
        # Running in GitHub Actions
        gh secret set "${secret_name}" < "${key_file}" --repo "${GITHUB_REPOSITORY}"
    else
        # Running locally
        gh secret set "${secret_name}" < "${key_file}" --repo "${GITHUB_REPO}"
    fi
    
    print_success "GitHub secret ${secret_name} created/updated"
}

# Main execution
main() {
    print_status "Starting Firebase GitHub secrets setup..."
    
    # Step 1: Check prerequisites
    print_status "Checking prerequisites..."
    
    if ! check_command "gcloud"; then
        print_error "Please install Google Cloud SDK: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    if ! check_command "gh"; then
        print_error "Please install GitHub CLI: https://cli.github.com/manual/installation"
        exit 1
    fi
    
    if ! check_gcloud_auth; then
        exit 1
    fi
    
    if ! check_gh_auth; then
        exit 1
    fi
    
    print_success "All prerequisites met"
    
    # Step 2: Set up komodo-defi-sdk project
    print_status "Setting up komodo-defi-sdk project..."
    
    # Set the project
    gcloud config set project "${SDK_PROJECT_ID}" --quiet
    
    # Create service account if needed
    create_service_account_if_needed "${SDK_PROJECT_ID}" "${SDK_SERVICE_ACCOUNT_NAME}"
    
    # Grant permissions
    grant_permissions "${SDK_PROJECT_ID}" "${SDK_SERVICE_ACCOUNT_NAME}@${SDK_PROJECT_ID}.iam.gserviceaccount.com"
    
    # Generate key
    SDK_KEY_FILE="komodo-defi-sdk-key.json"
    generate_service_account_key "${SDK_PROJECT_ID}" "${SDK_SERVICE_ACCOUNT_NAME}" "${SDK_KEY_FILE}"
    
    # Create GitHub secret
    create_github_secret "FIREBASE_SERVICE_ACCOUNT_KOMODO_DEFI_SDK" "${SDK_KEY_FILE}"
    
    # Step 3: Set up komodo-playground project
    print_status "Setting up komodo-playground project..."
    
    # Set the project
    gcloud config set project "${PLAYGROUND_PROJECT_ID}" --quiet
    
    # Create service account if needed
    create_service_account_if_needed "${PLAYGROUND_PROJECT_ID}" "${PLAYGROUND_SERVICE_ACCOUNT_NAME}"
    
    # Grant permissions
    grant_permissions "${PLAYGROUND_PROJECT_ID}" "${PLAYGROUND_SERVICE_ACCOUNT_NAME}@${PLAYGROUND_PROJECT_ID}.iam.gserviceaccount.com"
    
    # Generate key
    PLAYGROUND_KEY_FILE="komodo-playground-key.json"
    generate_service_account_key "${PLAYGROUND_PROJECT_ID}" "${PLAYGROUND_SERVICE_ACCOUNT_NAME}" "${PLAYGROUND_KEY_FILE}"
    
    # Create GitHub secret
    create_github_secret "FIREBASE_SERVICE_ACCOUNT_KOMODO_PLAYGROUND" "${PLAYGROUND_KEY_FILE}"
    
    # Step 4: Clean up sensitive files
    print_status "Cleaning up sensitive files..."
    
    if [ -f "${SDK_KEY_FILE}" ]; then
        rm -f "${SDK_KEY_FILE}"
        print_success "Removed ${SDK_KEY_FILE}"
    fi
    
    if [ -f "${PLAYGROUND_KEY_FILE}" ]; then
        rm -f "${PLAYGROUND_KEY_FILE}"
        print_success "Removed ${PLAYGROUND_KEY_FILE}"
    fi
    
    # Step 5: Verify setup
    print_status "Verifying setup..."
    
    # Check if secrets exist
    if gh secret list --repo "${GITHUB_REPO}" | grep -q "FIREBASE_SERVICE_ACCOUNT_KOMODO_DEFI_SDK"; then
        print_success "FIREBASE_SERVICE_ACCOUNT_KOMODO_DEFI_SDK secret exists"
    else
        print_error "FIREBASE_SERVICE_ACCOUNT_KOMODO_DEFI_SDK secret not found"
    fi
    
    if gh secret list --repo "${GITHUB_REPO}" | grep -q "FIREBASE_SERVICE_ACCOUNT_KOMODO_PLAYGROUND"; then
        print_success "FIREBASE_SERVICE_ACCOUNT_KOMODO_PLAYGROUND secret exists"
    else
        print_error "FIREBASE_SERVICE_ACCOUNT_KOMODO_PLAYGROUND secret not found"
    fi
    
    print_success "Firebase GitHub secrets setup completed!"
    print_status "You can now test the deployment by creating a pull request or pushing to the dev branch."
}

# Display banner
echo "================================================"
echo "Firebase GitHub Secrets Setup Script"
echo "================================================"
echo

# Confirm before proceeding
read -p "This script will set up Firebase service accounts and GitHub secrets. Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Setup cancelled"
    exit 0
fi

# Run main function
main
