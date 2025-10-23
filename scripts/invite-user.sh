#!/bin/bash

# Onyx User Invitation Script
# This script helps administrators invite users to Onyx

set -e

# Configuration
ONYX_API_URL="${ONYX_API_URL:-http://localhost:8080}"
API_KEY="${ONYX_API_KEY:-}"
USER_EMAIL="${1:-}"
USER_ROLE="${2:-basic}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 <user-email> [role]"
    echo ""
    echo "Arguments:"
    echo "  user-email    Email address of the user to invite"
    echo "  role          User role (basic, admin, curator, global_curator, limited)"
    echo ""
    echo "Environment Variables:"
    echo "  ONYX_API_URL  Onyx API URL (default: http://localhost:8080)"
    echo "  API_KEY       Onyx API key for authentication"
    echo ""
    echo "Examples:"
    echo "  $0 john.doe@company.com"
    echo "  $0 jane.smith@company.com admin"
    echo "  ONYX_API_URL=https://onyx.company.com API_KEY=your-key $0 user@company.com"
    echo ""
    echo "Valid roles:"
    echo "  basic           - Standard user access (default)"
    echo "  admin           - Full system access"
    echo "  curator         - Can manage content for their groups"
    echo "  global_curator  - Can manage content for all groups"
    echo "  limited         - Restricted access to basic features"
}

# Function to validate email
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        print_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

# Function to validate role
validate_role() {
    local role="$1"
    case "$role" in
        basic|admin|curator|global_curator|limited)
            return 0
            ;;
        *)
            print_error "Invalid role: $role"
            print_info "Valid roles: basic, admin, curator, global_curator, limited"
            return 1
            ;;
    esac
}

# Function to check if API key is set
check_api_key() {
    if [[ -z "$API_KEY" ]]; then
        print_error "API_KEY environment variable is not set"
        print_info "Please set your Onyx API key:"
        print_info "  export API_KEY=your-api-key-here"
        print_info "  or run: API_KEY=your-key $0 $@"
        exit 1
    fi
}

# Function to check if Onyx API is accessible
check_api_health() {
    print_info "Checking Onyx API connectivity..."
    
    if ! curl -s -f "${ONYX_API_URL}/health" > /dev/null 2>&1; then
        print_error "Cannot connect to Onyx API at ${ONYX_API_URL}"
        print_info "Please check:"
        print_info "  1. Onyx is running and accessible"
        print_info "  2. ONYX_API_URL is correct"
        print_info "  3. Network connectivity"
        exit 1
    fi
    
    print_success "Onyx API is accessible"
}

# Function to invite user
invite_user() {
    local email="$1"
    local role="$2"
    
    print_info "Inviting user: $email with role: $role"
    
    # Prepare the request
    local request_data=$(cat <<EOF
{
    "email": "$email",
    "role": "$role"
}
EOF
)
    
    # Make the API call
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST "${ONYX_API_URL}/api/user/invite" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$request_data")
    
    # Extract HTTP status code
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    # Check response
    case "$http_code" in
        200|201)
            print_success "User invitation sent successfully!"
            print_info "User $email will receive an invitation email"
            ;;
        400)
            print_error "Bad request - check email format and role"
            print_info "Response: $response_body"
            exit 1
            ;;
        401)
            print_error "Unauthorized - check your API key"
            exit 1
            ;;
        403)
            print_error "Forbidden - insufficient permissions"
            print_info "Make sure your API key has admin privileges"
            exit 1
            ;;
        409)
            print_warning "User already exists or has been invited"
            print_info "Response: $response_body"
            ;;
        500)
            print_error "Internal server error"
            print_info "Response: $response_body"
            exit 1
            ;;
        *)
            print_error "Unexpected response (HTTP $http_code)"
            print_info "Response: $response_body"
            exit 1
            ;;
    esac
}

# Function to list existing users (optional)
list_users() {
    print_info "Fetching current user list..."
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X GET "${ONYX_API_URL}/api/user/list" \
        -H "Authorization: Bearer ${API_KEY}")
    
    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        print_success "Current users:"
        echo "$response_body" | jq -r '.[] | "  \(.email) (\(.role))"' 2>/dev/null || echo "$response_body"
    else
        print_warning "Could not fetch user list (HTTP $http_code)"
    fi
}

# Main execution
main() {
    # Check if help is requested
    if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
        show_usage
        exit 0
    fi
    
    # Check if email is provided
    if [[ -z "$USER_EMAIL" ]]; then
        print_error "User email is required"
        show_usage
        exit 1
    fi
    
    # Validate inputs
    validate_email "$USER_EMAIL" || exit 1
    validate_role "$USER_ROLE" || exit 1
    
    # Check prerequisites
    check_api_key
    check_api_health
    
    # Show current users (optional)
    if [[ "$3" == "--list" ]]; then
        list_users
        echo ""
    fi
    
    # Invite the user
    invite_user "$USER_EMAIL" "$USER_ROLE"
    
    print_success "Invitation process completed!"
    print_info "The user should receive an email invitation shortly"
}

# Run main function with all arguments
main "$@"
