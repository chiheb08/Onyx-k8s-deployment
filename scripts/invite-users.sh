#!/bin/bash

# Onyx Bulk User Invitation Script
# This script helps administrators invite multiple users to Onyx from a file

set -e

# Configuration
ONYX_API_URL="${ONYX_API_URL:-http://localhost:8080}"
API_KEY="${ONYX_API_KEY:-}"
USERS_FILE="${1:-}"
DEFAULT_ROLE="${2:-basic}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_USERS=0
SUCCESS_COUNT=0
ERROR_COUNT=0
SKIP_COUNT=0

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
    echo "Usage: $0 <users-file> [default-role]"
    echo ""
    echo "Arguments:"
    echo "  users-file     File containing list of users to invite"
    echo "  default-role   Default role for all users (default: basic)"
    echo ""
    echo "Environment Variables:"
    echo "  ONYX_API_URL   Onyx API URL (default: http://localhost:8080)"
    echo "  API_KEY        Onyx API key for authentication"
    echo ""
    echo "Users File Format:"
    echo "  Each line should contain: email,role"
    echo "  Example:"
    echo "    john.doe@company.com,admin"
    echo "    jane.smith@company.com,basic"
    echo "    bob.wilson@company.com,curator"
    echo ""
    echo "  Or just email addresses (will use default role):"
    echo "    john.doe@company.com"
    echo "    jane.smith@company.com"
    echo ""
    echo "Examples:"
    echo "  $0 users.txt"
    echo "  $0 users.txt admin"
    echo "  ONYX_API_URL=https://onyx.company.com API_KEY=your-key $0 users.txt"
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

# Function to invite a single user
invite_single_user() {
    local email="$1"
    local role="$2"
    
    # Validate email
    if ! validate_email "$email"; then
        print_error "Invalid email format: $email"
        return 1
    fi
    
    # Validate role
    if ! validate_role "$role"; then
        print_error "Invalid role: $role"
        return 1
    fi
    
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
            print_success "✓ Invited $email ($role)"
            return 0
            ;;
        400)
            print_error "✗ Bad request for $email - check email format and role"
            return 1
            ;;
        401)
            print_error "✗ Unauthorized - check your API key"
            exit 1
            ;;
        403)
            print_error "✗ Forbidden - insufficient permissions"
            exit 1
            ;;
        409)
            print_warning "⚠ User $email already exists or has been invited"
            return 2
            ;;
        500)
            print_error "✗ Internal server error for $email"
            return 1
            ;;
        *)
            print_error "✗ Unexpected response (HTTP $http_code) for $email"
            return 1
            ;;
    esac
}

# Function to process users file
process_users_file() {
    local users_file="$1"
    
    if [[ ! -f "$users_file" ]]; then
        print_error "Users file not found: $users_file"
        exit 1
    fi
    
    print_info "Processing users from: $users_file"
    print_info "Default role: $DEFAULT_ROLE"
    echo ""
    
    # Count total lines
    TOTAL_USERS=$(wc -l < "$users_file")
    print_info "Found $TOTAL_USERS users to process"
    echo ""
    
    # Process each line
    local line_number=0
    while IFS= read -r line; do
        line_number=$((line_number + 1))
        
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Parse line (format: email,role or just email)
        local email=""
        local role="$DEFAULT_ROLE"
        
        if [[ "$line" == *","* ]]; then
            # Line contains both email and role
            email=$(echo "$line" | cut -d',' -f1 | xargs)
            role=$(echo "$line" | cut -d',' -f2 | xargs)
        else
            # Line contains only email
            email=$(echo "$line" | xargs)
        fi
        
        # Skip if email is empty
        if [[ -z "$email" ]]; then
            print_warning "⚠ Skipping empty line $line_number"
            SKIP_COUNT=$((SKIP_COUNT + 1))
            continue
        fi
        
        # Process the user
        print_info "[$line_number/$TOTAL_USERS] Processing: $email"
        
        local result
        invite_single_user "$email" "$role"
        result=$?
        
        case $result in
            0)
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                ;;
            1)
                ERROR_COUNT=$((ERROR_COUNT + 1))
                ;;
            2)
                SKIP_COUNT=$((SKIP_COUNT + 1))
                ;;
        esac
        
        echo ""
        
    done < "$users_file"
}

# Function to show summary
show_summary() {
    echo "=========================================="
    print_info "Bulk invitation summary:"
    echo "  Total users processed: $TOTAL_USERS"
    print_success "  Successfully invited: $SUCCESS_COUNT"
    print_warning "  Skipped (already exists): $SKIP_COUNT"
    print_error "  Errors: $ERROR_COUNT"
    echo "=========================================="
    
    if [[ $ERROR_COUNT -gt 0 ]]; then
        print_warning "Some users could not be invited. Check the errors above."
        exit 1
    else
        print_success "All users processed successfully!"
    fi
}

# Function to create sample users file
create_sample_file() {
    local sample_file="users-sample.txt"
    print_info "Creating sample users file: $sample_file"
    
    cat > "$sample_file" <<EOF
# Sample users file for Onyx bulk invitation
# Format: email,role
# Lines starting with # are comments and will be ignored

# Admin users
admin@company.com,admin
john.doe@company.com,admin

# Regular users
jane.smith@company.com,basic
bob.wilson@company.com,basic

# Curators
alice.johnson@company.com,curator
charlie.brown@company.com,global_curator

# Limited access users
guest@company.com,limited
EOF
    
    print_success "Sample file created: $sample_file"
    print_info "Edit this file with your users and run: $0 $sample_file"
}

# Main execution
main() {
    # Check if help is requested
    if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
        show_usage
        exit 0
    fi
    
    # Check if sample file creation is requested
    if [[ "$1" == "--create-sample" ]]; then
        create_sample_file
        exit 0
    fi
    
    # Check if users file is provided
    if [[ -z "$USERS_FILE" ]]; then
        print_error "Users file is required"
        show_usage
        exit 1
    fi
    
    # Check prerequisites
    check_api_key
    check_api_health
    
    # Process users
    process_users_file "$USERS_FILE"
    
    # Show summary
    show_summary
}

# Run main function with all arguments
main "$@"

