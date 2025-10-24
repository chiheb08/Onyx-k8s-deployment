#!/bin/bash

# Onyx Cost Calculator for Beginners
# This script helps estimate the cost of running Onyx for different user counts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

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
    echo "Usage: $0 <user-count> [provider]"
    echo ""
    echo "Arguments:"
    echo "  user-count    Number of users (100, 300, 500)"
    echo "  provider      Cloud provider (aws, gcp, azure) - optional"
    echo ""
    echo "Examples:"
    echo "  $0 100"
    echo "  $0 300 aws"
    echo "  $0 500 gcp"
    echo ""
    echo "Supported user counts: 100, 300, 500"
    echo "Supported providers: aws, gcp, azure"
}

# Function to calculate costs for 100 users
calculate_100_users() {
    local provider="$1"
    
    print_header "100 USERS - COST ESTIMATE"
    
    case "$provider" in
        "aws")
            print_info "AWS Pricing (Recommended for beginners)"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Component                 │ Monthly Cost │ Notes                                      │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ API Server                │ \$80          │ Core functionality                         │"
            echo "│ Web Server                │ \$60          │ User interface                             │"
            echo "│ Database                  │ \$100         │ Data storage                               │"
            echo "│ Search Engine             │ \$160         │ Fast searches                              │"
            echo "│ AI/ML Models              │ \$320         │ Smart features                            │"
            echo "│ Background Workers        │ \$480         │ Keeps system running                       │"
            echo "│ Storage                   │ \$100         │ File storage                               │"
            echo "│ Network                   │ \$50          │ User access                                │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ TOTAL                     │ \$1,350        │ Complete system                            │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
        "gcp")
            print_info "Google Cloud Pricing"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Component                 │ Monthly Cost │ Notes                                      │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ API Server                │ \$96          │ Core functionality                         │"
            echo "│ Web Server                │ \$96          │ User interface                             │"
            echo "│ Database                  │ \$60          │ Data storage                               │"
            echo "│ Search Engine             │ \$202         │ Fast searches                              │"
            echo "│ AI/ML Models              │ \$403         │ Smart features                            │"
            echo "│ Background Workers        │ \$605         │ Keeps system running                       │"
            echo "│ Storage                   │ \$100         │ File storage                               │"
            echo "│ Network                   │ \$50          │ User access                                │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ TOTAL                     │ \$1,612        │ Complete system                            │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
        "azure")
            print_info "Microsoft Azure Pricing"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Component                 │ Monthly Cost │ Notes                                      │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ API Server                │ \$60          │ Core functionality                         │"
            echo "│ Web Server                │ \$60          │ User interface                             │"
            echo "│ Database                  │ \$180         │ Data storage                               │"
            echo "│ Search Engine             │ \$276         │ Fast searches                              │"
            echo "│ AI/ML Models              │ \$553         │ Smart features                            │"
            echo "│ Background Workers        │ \$830         │ Keeps system running                       │"
            echo "│ Storage                   │ \$100         │ File storage                               │"
            echo "│ Network                   │ \$50          │ User access                                │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ TOTAL                     │ \$2,109        │ Complete system                            │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
        *)
            print_info "Cost Comparison for 100 Users"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Provider                 │ Monthly Cost │ Best For                                   │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ AWS                      │ \$1,350        │ Beginners, cost-conscious                  │"
            echo "│ Google Cloud             │ \$1,612        │ Performance, scaling                       │"
            echo "│ Microsoft Azure          │ \$2,109        │ Enterprise, Microsoft integration          │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
    esac
    
    echo ""
    print_success "Recommendation: Start with AWS for 100 users"
    print_info "You can always switch providers later as you grow"
}

# Function to calculate costs for 300 users
calculate_300_users() {
    local provider="$1"
    
    print_header "300 USERS - COST ESTIMATE"
    
    case "$provider" in
        "aws")
            print_info "AWS Pricing"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Component                 │ Monthly Cost │ Notes                                      │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ API Servers (2x)         │ \$160         │ Handle more users                          │"
            echo "│ Web Servers (2x)         │ \$120         │ Serve more users                           │"
            echo "│ Database                 │ \$200         │ Store more data                            │"
            echo "│ Search Engine (2x)       │ \$320         │ Handle more searches                       │"
            echo "│ AI/ML Models (4x)        │ \$640         │ Process more documents                     │"
            echo "│ Background Workers (12x) │ \$960         │ Handle more tasks                          │"
            echo "│ Storage                  │ \$200         │ Store more files                           │"
            echo "│ Network                  │ \$100         │ Better performance                          │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ TOTAL                     │ \$2,700        │ Complete system                            │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
        "gcp")
            print_info "Google Cloud Pricing (Recommended)"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Component                 │ Monthly Cost │ Notes                                      │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ API Servers (2x)         │ \$192         │ Handle more users                          │"
            echo "│ Web Servers (2x)         │ \$192         │ Serve more users                           │"
            echo "│ Database                 │ \$120         │ Store more data                            │"
            echo "│ Search Engine (2x)       │ \$320         │ Handle more searches                       │"
            echo "│ AI/ML Models (4x)        │ \$640         │ Process more documents                     │"
            echo "│ Background Workers (12x) │ \$960         │ Handle more tasks                          │"
            echo "│ Storage                  │ \$200         │ Store more files                           │"
            echo "│ Network                  │ \$100         │ Better performance                          │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ TOTAL                     │ \$2,732        │ Complete system                            │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
        "azure")
            print_info "Microsoft Azure Pricing"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Component                 │ Monthly Cost │ Notes                                      │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ API Servers (2x)         │ \$120         │ Handle more users                          │"
            echo "│ Web Servers (2x)         │ \$120         │ Serve more users                           │"
            echo "│ Database                 │ \$360         │ Store more data                            │"
            echo "│ Search Engine (2x)       │ \$552         │ Handle more searches                       │"
            echo "│ AI/ML Models (4x)        │ \$1,104       │ Process more documents                     │"
            echo "│ Background Workers (12x) │ \$1,660       │ Handle more tasks                          │"
            echo "│ Storage                  │ \$200         │ Store more files                           │"
            echo "│ Network                  │ \$100         │ Better performance                          │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ TOTAL                     │ \$4,216        │ Complete system                            │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
        *)
            print_info "Cost Comparison for 300 Users"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Provider                 │ Monthly Cost │ Best For                                   │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ AWS                      │ \$2,700        │ Cost-conscious                             │"
            echo "│ Google Cloud             │ \$2,732        │ Performance, scaling (RECOMMENDED)         │"
            echo "│ Microsoft Azure          │ \$4,216        │ Enterprise, Microsoft integration          │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
    esac
    
    echo ""
    print_success "Recommendation: Use Google Cloud for 300 users"
    print_info "Best balance of cost and performance for medium companies"
}

# Function to calculate costs for 500 users
calculate_500_users() {
    local provider="$1"
    
    print_header "500 USERS - COST ESTIMATE"
    
    case "$provider" in
        "aws")
            print_info "AWS Pricing"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Component                 │ Monthly Cost │ Notes                                      │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ API Servers (3x)          │ \$240         │ Handle many users                          │"
            echo "│ Web Servers (3x)          │ \$180         │ Serve many users                           │"
            echo "│ Database (2x)             │ \$400         │ Store lots of data                        │"
            echo "│ Search Engine (3x)        │ \$480         │ Handle many searches                       │"
            echo "│ AI/ML Models (6x)         │ \$960         │ Process many documents                     │"
            echo "│ Background Workers (18x)   │ \$1,440       │ Handle many tasks                          │"
            echo "│ Storage                  │ \$300         │ Store many files                           │"
            echo "│ Network                  │ \$150         │ Best performance                            │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ TOTAL                     │ \$4,150        │ Complete system                            │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
        "gcp")
            print_info "Google Cloud Pricing (Recommended)"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Component                 │ Monthly Cost │ Notes                                      │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ API Servers (3x)          │ \$288         │ Handle many users                          │"
            echo "│ Web Servers (3x)          │ \$288         │ Serve many users                           │"
            echo "│ Database (2x)             │ \$240         │ Store lots of data                        │"
            echo "│ Search Engine (3x)        │ \$480         │ Handle many searches                       │"
            echo "│ AI/ML Models (6x)         │ \$960         │ Process many documents                     │"
            echo "│ Background Workers (18x)  │ \$1,440       │ Handle many tasks                          │"
            echo "│ Storage                  │ \$300         │ Store many files                           │"
            echo "│ Network                  │ \$150         │ Best performance                            │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ TOTAL                     │ \$4,146        │ Complete system                            │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
        "azure")
            print_info "Microsoft Azure Pricing"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Component                 │ Monthly Cost │ Notes                                      │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ API Servers (3x)          │ \$180         │ Handle many users                          │"
            echo "│ Web Servers (3x)          │ \$180         │ Serve many users                           │"
            echo "│ Database (2x)             │ \$720         │ Store lots of data                        │"
            echo "│ Search Engine (3x)        │ \$828         │ Handle many searches                       │"
            echo "│ AI/ML Models (6x)         │ \$1,656       │ Process many documents                     │"
            echo "│ Background Workers (18x)   │ \$2,490       │ Handle many tasks                          │"
            echo "│ Storage                  │ \$300         │ Store many files                           │"
            echo "│ Network                  │ \$150         │ Best performance                            │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ TOTAL                     │ \$6,414        │ Complete system                            │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
        *)
            print_info "Cost Comparison for 500 Users"
            echo ""
            echo "┌─────────────────────────────────────────────────────────────────────────────────────────┐"
            echo "│ Provider                 │ Monthly Cost │ Best For                                   │"
            echo "├─────────────────────────────────────────────────────────────────────────────────────────┤"
            echo "│ AWS                      │ \$4,150        │ Cost-conscious                             │"
            echo "│ Google Cloud             │ \$4,146        │ Performance, scaling (RECOMMENDED)         │"
            echo "│ Microsoft Azure          │ \$6,414        │ Enterprise, Microsoft integration          │"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────┘"
            ;;
    esac
    
    echo ""
    print_success "Recommendation: Use Google Cloud for 500 users"
    print_info "Best performance and scaling for large companies"
}

# Function to show cost optimization tips
show_optimization_tips() {
    print_header "COST OPTIMIZATION TIPS"
    
    echo "💡 Ways to reduce costs:"
    echo ""
    echo "1. Reserved Instances (1-year commitment):"
    echo "   - AWS: 30-35% savings"
    echo "   - GCP: 30-35% savings"
    echo "   - Azure: 30-35% savings"
    echo ""
    echo "2. Spot Instances (for non-critical workloads):"
    echo "   - AWS: 50-70% savings"
    echo "   - GCP: 50-70% savings"
    echo "   - Azure: 50-70% savings"
    echo ""
    echo "3. Auto-scaling:"
    echo "   - Scale down at night: 40-60% savings"
    echo "   - Scale up during business hours: Better performance"
    echo "   - Weekend scaling: 50-80% savings"
    echo ""
    echo "4. Start small and scale up:"
    echo "   - Begin with minimum requirements"
    echo "   - Monitor usage and performance"
    echo "   - Scale up only when needed"
    echo ""
    print_warning "Note: These optimizations require more technical knowledge"
    print_info "Start with standard pricing and optimize after 3-6 months"
}

# Function to show performance expectations
show_performance_expectations() {
    print_header "PERFORMANCE EXPECTATIONS"
    
    echo "📊 What you can expect:"
    echo ""
    echo "100 Users:"
    echo "  - Search results: < 2 seconds"
    echo "  - File uploads: 5MB in 3-5 seconds"
    echo "  - Concurrent users: 10-20 at once"
    echo "  - Documents per day: 500-1000"
    echo "  - Uptime: 99.5% (3.6 hours downtime per month)"
    echo ""
    echo "300 Users:"
    echo "  - Search results: < 3 seconds"
    echo "  - File uploads: 10MB in 5-8 seconds"
    echo "  - Concurrent users: 30-60 at once"
    echo "  - Documents per day: 1500-3000"
    echo "  - Uptime: 99.7% (2.2 hours downtime per month)"
    echo ""
    echo "500 Users:"
    echo "  - Search results: < 5 seconds"
    echo "  - File uploads: 10MB in 8-15 seconds"
    echo "  - Concurrent users: 50-100 at once"
    echo "  - Documents per day: 2500-5000"
    echo "  - Uptime: 99.9% (43 minutes downtime per month)"
}

# Main execution
main() {
    local user_count="$1"
    local provider="$2"
    
    # Check if help is requested
    if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]; then
        show_usage
        exit 0
    fi
    
    # Check if user count is provided
    if [[ -z "$user_count" ]]; then
        print_error "User count is required"
        show_usage
        exit 1
    fi
    
    # Validate user count
    case "$user_count" in
        100|300|500)
            ;;
        *)
            print_error "Invalid user count: $user_count"
            print_info "Supported user counts: 100, 300, 500"
            exit 1
            ;;
    esac
    
    # Validate provider if provided
    if [[ -n "$provider" ]]; then
        case "$provider" in
            aws|gcp|azure)
                ;;
            *)
                print_error "Invalid provider: $provider"
                print_info "Supported providers: aws, gcp, azure"
                exit 1
                ;;
        esac
    fi
    
    # Calculate costs based on user count
    case "$user_count" in
        100)
            calculate_100_users "$provider"
            ;;
        300)
            calculate_300_users "$provider"
            ;;
        500)
            calculate_500_users "$provider"
            ;;
    esac
    
    echo ""
    show_optimization_tips
    echo ""
    show_performance_expectations
    echo ""
    print_success "Cost calculation completed!"
    print_info "Remember: Start small and scale up as you grow"
}

# Run main function with all arguments
main "$@"
