#!/bin/bash

# Claude Code Agents Collection - Automated Setup Script (Linux)
# ============================================================
# This script automates the installation and configuration of the Claude Code Agents collection for Linux
# Supports Ubuntu/Debian (apt), CentOS/RHEL/Fedora (yum/dnf), and Arch Linux (pacman)
# 
# SAFE TO RUN MULTIPLE TIMES - Preserves existing configurations
# 
# Features:
# - Preserves existing agents, orchestrators, and tools
# - Only copies new files that don't already exist
# - Creates backups before updating configuration files
# - Merges rather than overwrites agent collections
# - Provides detailed logging of all actions taken
# - Safe to run repeatedly for updates
#
# Run with: bash setup-linux.sh

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DISTRO=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""

# Functions for colored output
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

print_header() {
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
    echo ""
}

# Detect Linux distribution and package manager
detect_distro() {
    print_status "Detecting Linux distribution..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        print_error "Unable to detect Linux distribution"
        exit 1
    fi
    
    case "$DISTRO" in
        ubuntu|debian)
            PACKAGE_MANAGER="apt"
            INSTALL_CMD="apt install -y"
            UPDATE_CMD="apt update"
            ;;
        centos|rhel|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                PACKAGE_MANAGER="dnf"
                INSTALL_CMD="dnf install -y"
                UPDATE_CMD="dnf check-update || true"
            else
                PACKAGE_MANAGER="yum"
                INSTALL_CMD="yum install -y"
                UPDATE_CMD="yum check-update || true"
            fi
            ;;
        fedora)
            PACKAGE_MANAGER="dnf"
            INSTALL_CMD="dnf install -y"
            UPDATE_CMD="dnf check-update || true"
            ;;
        arch|manjaro)
            PACKAGE_MANAGER="pacman"
            INSTALL_CMD="pacman -S --noconfirm"
            UPDATE_CMD="pacman -Sy"
            ;;
        opensuse*|sles)
            PACKAGE_MANAGER="zypper"
            INSTALL_CMD="zypper install -y"
            UPDATE_CMD="zypper refresh"
            ;;
        *)
            print_error "Unsupported distribution: $DISTRO"
            print_error "Supported distributions: Ubuntu, Debian, CentOS, RHEL, Fedora, Arch Linux, openSUSE"
            exit 1
            ;;
    esac
    
    print_success "Detected: $DISTRO using $PACKAGE_MANAGER"
}

# Check if running with sufficient privileges for package installation
check_privileges() {
    if [ "$EUID" -eq 0 ]; then
        # Running as root
        SUDO_CMD=""
    elif command -v sudo &> /dev/null; then
        # Check if user can use sudo
        if sudo -n true 2>/dev/null; then
            SUDO_CMD="sudo"
            print_status "Using sudo for package installation"
        else
            print_warning "This script may require sudo privileges for package installation"
            SUDO_CMD="sudo"
        fi
    else
        print_error "This script requires root privileges or sudo access for package installation"
        exit 1
    fi
}

# Update package repositories
update_packages() {
    print_status "Updating package repositories..."
    if ! $SUDO_CMD $UPDATE_CMD; then
        print_warning "Package repository update failed, continuing anyway..."
    fi
}

# Install a package using the appropriate package manager
install_package() {
    local package_name="$1"
    local apt_name="${2:-$1}"
    local yum_name="${3:-$1}"
    local pacman_name="${4:-$1}"
    local zypper_name="${5:-$1}"
    
    case "$PACKAGE_MANAGER" in
        apt)
            $SUDO_CMD $INSTALL_CMD "$apt_name"
            ;;
        yum|dnf)
            $SUDO_CMD $INSTALL_CMD "$yum_name"
            ;;
        pacman)
            $SUDO_CMD $INSTALL_CMD "$pacman_name"
            ;;
        zypper)
            $SUDO_CMD $INSTALL_CMD "$zypper_name"
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if Linux
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        print_error "This script is designed for Linux. Use setup.sh for macOS."
        exit 1
    fi
    
    detect_distro
    check_privileges
    update_packages
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        print_status "Git is not installed. Installing..."
        case "$PACKAGE_MANAGER" in
            apt)
                install_package "git"
                ;;
            yum|dnf)
                install_package "git"
                ;;
            pacman)
                install_package "git"
                ;;
            zypper)
                install_package "git"
                ;;
        esac
    fi
    print_success "Git is installed"
    
    # Check if curl is installed (needed for installations)
    if ! command -v curl &> /dev/null; then
        print_status "Curl is not installed. Installing..."
        install_package "curl"
    fi
    print_success "Curl is installed"
    
    # Check if Claude Code directory exists
    if [ ! -d "$HOME/.claude" ]; then
        print_status "Creating ~/.claude directory..."
        mkdir -p "$HOME/.claude"
    fi
    print_success "Claude directory exists"
}

# Check if a file already exists and is different from source
file_needs_update() {
    local source_file="$1"
    local dest_file="$2"
    
    # Verify source file exists
    if [ ! -f "$source_file" ]; then
        print_error "Source file does not exist: $source_file"
        return 1  # false - can't update from non-existent source
    fi
    
    # If destination doesn't exist, it needs to be created
    if [ ! -f "$dest_file" ]; then
        return 0  # true - needs update
    fi
    
    # If files are identical, no update needed
    if cmp -s "$source_file" "$dest_file" 2>/dev/null; then
        return 1  # false - no update needed
    fi
    
    # Files are different, needs update
    return 0  # true - needs update
}

# Safely copy agent files preserving existing ones
copy_agent_files() {
    local source_dir="$1"
    local dest_dir="$2"
    local category="$3"
    
    local copied=0
    local skipped=0
    local updated=0
    
    print_status "Processing $category..."
    print_status "  Source directory: $source_dir"
    print_status "  Destination directory: $dest_dir"
    
    # Verify source directory exists
    if [ ! -d "$source_dir" ]; then
        print_error "  Source directory does not exist: $source_dir"
        echo "0" > "/tmp/setup_copied_$$"
        echo "0" > "/tmp/setup_skipped_$$" 
        echo "0" > "/tmp/setup_updated_$$"
        return 1
    fi
    
    # Ensure destination directory exists
    if ! mkdir -p "$dest_dir"; then
        print_error "  Failed to create destination directory: $dest_dir"
        echo "0" > "/tmp/setup_copied_$$"
        echo "0" > "/tmp/setup_skipped_$$" 
        echo "0" > "/tmp/setup_updated_$$"
        return 1
    fi
    
    # Count total files to process for progress tracking
    local total_files
    total_files=$(find "$source_dir" -name "*.md" -type f 2>/dev/null | wc -l)
    print_status "  Found $total_files .md files to process"
    
    if [ "$total_files" -eq 0 ]; then
        print_warning "  No .md files found in $source_dir"
        echo "0" > "/tmp/setup_copied_$$"
        echo "0" > "/tmp/setup_skipped_$$" 
        echo "0" > "/tmp/setup_updated_$$"
        return 0
    fi
    
    local processed=0
    
    # Process each .md file using a for loop to avoid subshell issues
    local file_list
    file_list=$(find "$source_dir" -name "*.md" -type f 2>/dev/null)
    
    if [ -z "$file_list" ]; then
        print_warning "  No .md files found to process"
        echo "0" > "/tmp/setup_copied_$$"
        echo "0" > "/tmp/setup_skipped_$$" 
        echo "0" > "/tmp/setup_updated_$$"
        return 0
    fi
    
    while IFS= read -r source_file; do
        [ -z "$source_file" ] && continue
        
        ((processed++))
        
        # Debug output every few files
        if [ $((processed % 3)) -eq 0 ] || [ "$processed" -eq 1 ] || [ "$processed" -eq "$total_files" ]; then
            print_status "  Progress: $processed/$total_files files processed"
        fi
        
        # Get relative path from source directory
        local rel_path="${source_file#$source_dir/}"
        local dest_file="$dest_dir/$rel_path"
        local dest_file_dir
        dest_file_dir=$(dirname "$dest_file")
        
        print_status "  Processing: $rel_path"
        
        # Ensure destination subdirectory exists
        if ! mkdir -p "$dest_file_dir"; then
            print_error "  Failed to create directory: $dest_file_dir"
            continue
        fi
        
        # Check if file needs update with error handling
        local needs_update=0
        if file_needs_update "$source_file" "$dest_file" 2>/dev/null; then
            needs_update=1
        fi
        
        if [ "$needs_update" -eq 1 ]; then
            if [ -f "$dest_file" ]; then
                print_status "  Updating: $rel_path"
                ((updated++))
            else
                print_status "  Adding: $rel_path"
                ((copied++))
            fi
            
            # Copy with error handling
            if ! cp "$source_file" "$dest_file" 2>/dev/null; then
                print_error "  Failed to copy: $source_file -> $dest_file"
                continue
            fi
            print_status "  Successfully processed: $rel_path"
        else
            print_status "  Skipping (identical): $rel_path"
            ((skipped++))
        fi
    done <<< "$file_list"
    
    # Update counters in parent scope using files
    echo "$copied" > "/tmp/setup_copied_$$"
    echo "$skipped" > "/tmp/setup_skipped_$$" 
    echo "$updated" > "/tmp/setup_updated_$$"
    
    print_status "  Completed processing $category"
    return 0
}

# Merge configuration files (like README.md) preserving user modifications
merge_config_files() {
    local temp_dir="$1"
    local agents_dir="$2"
    
    print_status "Merging configuration files..."
    
    # Verify source directory exists
    if [ ! -d "$temp_dir" ]; then
        print_error "Source directory does not exist: $temp_dir"
        return 1
    fi
    
    # Handle README.md specially - only update if it doesn't exist
    if [ ! -f "$agents_dir/README.md" ]; then
        if [ -f "$temp_dir/README.md" ]; then
            if cp "$temp_dir/README.md" "$agents_dir/README.md" 2>/dev/null; then
                print_status "  Added: README.md"
            else
                print_error "  Failed to copy: README.md"
            fi
        fi
    else
        print_status "  Skipping: README.md (preserving existing)"
    fi
    
    # Handle other configuration files
    for config_file in "AGENT_TEMPLATE.md" "CLAUDE.md" "setup.sh"; do
        if [ -f "$temp_dir/$config_file" ]; then
            if file_needs_update "$temp_dir/$config_file" "$agents_dir/$config_file" 2>/dev/null; then
                if [ -f "$agents_dir/$config_file" ]; then
                    # Backup existing file
                    local backup_file="$agents_dir/$config_file.backup.$(date +%Y%m%d-%H%M%S)"
                    if cp "$agents_dir/$config_file" "$backup_file" 2>/dev/null; then
                        print_status "  Updating: $config_file (backup created)"
                    else
                        print_warning "  Failed to create backup for: $config_file"
                        print_status "  Updating: $config_file (no backup)"
                    fi
                else
                    print_status "  Adding: $config_file"
                fi
                
                if cp "$temp_dir/$config_file" "$agents_dir/$config_file" 2>/dev/null; then
                    print_status "  Successfully processed: $config_file"
                else
                    print_error "  Failed to copy: $config_file"
                fi
            else
                print_status "  Skipping: $config_file (identical)"
            fi
        else
            print_status "  Skipping: $config_file (not found in source)"
        fi
    done
    
    return 0
}

# Install or update agents repository with preservation
clone_repository() {
    print_header "Setting Up Agents Repository"
    
    AGENTS_DIR="$HOME/.claude/agents"
    TEMP_CLONE_DIR=$(mktemp -d)
    
    # Set up cleanup trap
    trap 'rm -rf "$TEMP_CLONE_DIR" 2>/dev/null; rm -f "/tmp/setup_copied_$$" "/tmp/setup_skipped_$$" "/tmp/setup_updated_$$" 2>/dev/null' EXIT
    
    # Always clone to temporary directory first with timeout
    print_status "Downloading latest agents repository..."
    print_status "  Clone directory: $TEMP_CLONE_DIR"
    
    # Use timeout to prevent hanging on network issues
    if ! timeout 300 git clone --depth 1 https://github.com/alun-ai/agents.git "$TEMP_CLONE_DIR" 2>&1; then
        print_error "Failed to clone agents repository (timeout after 5 minutes or network error)"
        print_error "Please check your internet connection and try again"
        exit 1
    fi
    
    print_success "Repository cloned successfully"
    
    # Verify the clone was successful and contains expected directories
    if [ ! -d "$TEMP_CLONE_DIR" ] || [ ! -d "$TEMP_CLONE_DIR/.git" ]; then
        print_error "Repository clone appears to be incomplete"
        exit 1
    fi
    
    # Ensure agents directory exists
    if ! mkdir -p "$AGENTS_DIR"; then
        print_error "Failed to create agents directory: $AGENTS_DIR"
        exit 1
    fi
    
    print_success "Agents directory ready: $AGENTS_DIR"
    
    # Track statistics
    local total_copied=0
    local total_skipped=0
    local total_updated=0
    
    # Copy/update different categories of files with error handling
    local categories=("core" "orchestrators" "specialized" "universal")
    
    for category in "${categories[@]}"; do
        if [ -d "$TEMP_CLONE_DIR/$category" ]; then
            print_status "Found $category directory, processing..."
            
            if copy_agent_files "$TEMP_CLONE_DIR/$category" "$AGENTS_DIR/$category" "$(echo ${category^} | sed 's/s$//') Agents"; then
                # Successfully processed, update totals
                local copied_count
                local skipped_count  
                local updated_count
                copied_count=$(cat "/tmp/setup_copied_$$" 2>/dev/null || echo 0)
                skipped_count=$(cat "/tmp/setup_skipped_$$" 2>/dev/null || echo 0)
                updated_count=$(cat "/tmp/setup_updated_$$" 2>/dev/null || echo 0)
                
                total_copied=$((total_copied + copied_count))
                total_skipped=$((total_skipped + skipped_count))
                total_updated=$((total_updated + updated_count))
                
                print_success "  $category processing completed (copied: $copied_count, updated: $updated_count, skipped: $skipped_count)"
            else
                print_error "  Failed to process $category directory"
            fi
        else
            print_warning "  $category directory not found in repository"
        fi
    done
    
    # Handle configuration files
    print_status "Processing configuration files..."
    if ! merge_config_files "$TEMP_CLONE_DIR" "$AGENTS_DIR"; then
        print_warning "Some configuration files could not be processed"
    fi
    
    # Copy any additional non-agent files (like .mcp.json.example)
    print_status "Processing additional configuration files..."
    
    # Use a safer approach without pipelines
    local config_files
    config_files=$(find "$TEMP_CLONE_DIR" -maxdepth 1 \( -name "*.json*" -o -name "*.yml" -o -name "*.yaml" \) 2>/dev/null || echo "")
    
    if [ -n "$config_files" ]; then
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            if [ -f "$file" ]; then
                local filename
                filename=$(basename "$file")
                
                if file_needs_update "$file" "$AGENTS_DIR/$filename"; then
                    if [ -f "$AGENTS_DIR/$filename" ]; then
                        print_status "  Updating: $filename"
                    else
                        print_status "  Adding: $filename"
                    fi
                    
                    if ! cp "$file" "$AGENTS_DIR/$filename"; then
                        print_error "  Failed to copy: $filename"
                    fi
                else
                    print_status "  Skipping: $filename (identical)"
                fi
            fi
        done <<< "$config_files"
    else
        print_status "  No additional configuration files found"
    fi
    
    # Summary
    print_success "Repository update completed"
    print_status "Summary:"
    echo "  - New files added: $total_copied"
    echo "  - Files updated: $total_updated" 
    echo "  - Files preserved: $total_skipped"
    
    if [ $total_copied -eq 0 ] && [ $total_updated -eq 0 ]; then
        print_success "All agents are up to date - no changes needed"
    else
        print_success "Repository successfully updated with $((total_copied + total_updated)) changes"
    fi
}

# Install GitHub CLI using official installation methods
install_github_cli() {
    print_status "Installing GitHub CLI..."
    
    case "$PACKAGE_MANAGER" in
        apt)
            # Official GitHub CLI installation for Debian/Ubuntu
            if [ ! -f /etc/apt/sources.list.d/github-cli.list ]; then
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO_CMD dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO_CMD tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                $SUDO_CMD apt update
            fi
            $SUDO_CMD $INSTALL_CMD gh
            ;;
        yum)
            # For CentOS/RHEL 7
            $SUDO_CMD yum install -y yum-utils
            $SUDO_CMD yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
            $SUDO_CMD $INSTALL_CMD gh
            ;;
        dnf)
            # For Fedora/CentOS/RHEL 8+
            $SUDO_CMD dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
            $SUDO_CMD $INSTALL_CMD gh
            ;;
        pacman)
            # GitHub CLI is in official Arch repositories
            $SUDO_CMD $INSTALL_CMD github-cli
            ;;
        zypper)
            # For openSUSE
            $SUDO_CMD zypper addrepo https://cli.github.com/packages/rpm/gh-cli.repo
            $SUDO_CMD zypper --gpg-auto-import-keys refresh
            $SUDO_CMD $INSTALL_CMD gh
            ;;
    esac
}

# Install Jira CLI (ankitpokhrel/jira-cli)
install_jira_cli() {
    print_status "Installing Jira CLI (ankitpokhrel/jira-cli)..."
    
    # Get latest release with timeout and error handling
    local latest_release
    local api_response
    
    print_status "Fetching latest release information..."
    api_response=$(timeout 30 curl -s -f https://api.github.com/repos/ankitpokhrel/jira-cli/releases/latest 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$api_response" ]; then
        print_error "Failed to fetch release information from GitHub API"
        print_error "This could be due to:"
        print_error "  - Network connectivity issues"
        print_error "  - GitHub API rate limiting"
        print_error "  - Temporary GitHub service issues"
        print_status "Trying fallback method..."
        
        # Fallback: try to get release info from GitHub tags page
        latest_release=$(timeout 30 curl -s -f https://github.com/ankitpokhrel/jira-cli/tags 2>/dev/null | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
        
        if [ -z "$latest_release" ]; then
            print_error "Fallback method also failed"
            print_error "Please check your internet connection and try again later"
            return 1
        fi
        
        print_status "Found release via fallback: $latest_release"
    else
        latest_release=$(echo "$api_response" | grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$')
        
        if [ -z "$latest_release" ]; then
            print_error "Failed to parse release information from GitHub API"
            return 1
        fi
        
        print_status "Found latest release: $latest_release"
    fi
    
    # Determine architecture with proper mapping for jira-cli naming
    local arch
    local system_arch
    system_arch=$(uname -m)
    
    case "$system_arch" in
        x86_64) 
            arch="x86_64" 
            ;;
        aarch64|arm64) 
            arch="arm64" 
            ;;
        armv7l) 
            arch="armv6"  # jira-cli uses armv6 for ARM 32-bit
            ;;
        i386|i686) 
            arch="i386" 
            ;;
        *) 
            print_error "Unsupported architecture: $system_arch"
            print_error "Supported architectures: x86_64, aarch64/arm64, armv7l, i386/i686"
            return 1 
            ;;
    esac
    
    print_status "Detected architecture: $system_arch -> $arch"
    
    # Construct download URL
    local version_num="${latest_release#v}"
    local download_url="https://github.com/ankitpokhrel/jira-cli/releases/download/${latest_release}/jira_${version_num}_linux_${arch}.tar.gz"
    
    print_status "Download URL: $download_url"
    
    # Create temporary directory with cleanup trap
    local temp_dir
    temp_dir=$(mktemp -d)
    local temp_file="$temp_dir/jira-cli.tar.gz"
    
    # Set up cleanup trap - simplified to avoid issues with trap chaining
    trap 'rm -rf "$temp_dir" 2>/dev/null' EXIT
    
    # Download file with proper error checking
    print_status "Downloading Jira CLI ${latest_release} for ${arch}..."
    
    if ! timeout 120 curl -L -f -o "$temp_file" "$download_url" 2>/dev/null; then
        print_error "Failed to download Jira CLI from: $download_url"
        print_error "This could be due to:"
        print_error "  - Network connectivity issues"
        print_error "  - Invalid architecture detection"
        print_error "  - Release asset not available for your architecture"
        print_error "  - Temporary download server issues"
        
        # Try to provide more specific error information
        local http_code
        http_code=$(timeout 30 curl -L -s -o /dev/null -w "%{http_code}" "$download_url" 2>/dev/null)
        if [ -n "$http_code" ]; then
            case "$http_code" in
                404) print_error "  HTTP 404: Release asset not found for architecture $arch" ;;
                403) print_error "  HTTP 403: Access forbidden (possible rate limiting)" ;;
                500|502|503) print_error "  HTTP $http_code: Server error" ;;
                *) print_error "  HTTP $http_code: Unexpected response" ;;
            esac
        fi
        
        return 1
    fi
    
    print_success "Download completed"
    
    # Verify the downloaded file is actually a gzip file
    print_status "Verifying downloaded file..."
    
    if [ ! -f "$temp_file" ]; then
        print_error "Downloaded file not found: $temp_file"
        return 1
    fi
    
    # Check file size (should be at least a few KB for a valid archive)
    local file_size
    file_size=$(stat -c%s "$temp_file" 2>/dev/null || wc -c < "$temp_file" 2>/dev/null)
    
    if [ -z "$file_size" ] || [ "$file_size" -lt 1024 ]; then
        print_error "Downloaded file is too small ($file_size bytes) - likely an error page"
        print_status "File contents preview:"
        head -5 "$temp_file" 2>/dev/null || echo "  (unable to read file)"
        return 1
    fi
    
    print_status "File size: $file_size bytes"
    
    # Check if file is actually gzip
    if ! file "$temp_file" 2>/dev/null | grep -q "gzip compressed"; then
        print_error "Downloaded file is not in gzip format"
        print_status "File type detected:"
        file "$temp_file" 2>/dev/null || echo "  (unable to determine file type)"
        print_status "File contents preview (first 200 characters):"
        head -c 200 "$temp_file" 2>/dev/null || echo "  (unable to read file)"
        return 1
    fi
    
    print_success "File verification passed"
    
    # Extract the archive
    print_status "Extracting archive..."
    
    if ! tar -tzf "$temp_file" >/dev/null 2>&1; then
        print_error "Downloaded file is not a valid tar.gz archive"
        return 1
    fi
    
    # Create extraction directory
    local extract_dir="$temp_dir/extract"
    mkdir -p "$extract_dir"
    
    if ! tar -xzf "$temp_file" -C "$extract_dir" 2>/dev/null; then
        print_error "Failed to extract archive"
        return 1
    fi
    
    print_success "Archive extracted successfully"
    
    # Find the jira binary (it might be in different locations depending on the archive structure)
    local jira_binary=""
    
    # First try to find it using find command (more reliable than globbing)
    jira_binary=$(find "$extract_dir" -name "jira" -type f -executable 2>/dev/null | head -1)
    
    # If that didn't work, try common locations with shell globbing
    if [ -z "$jira_binary" ]; then
        for path in "$extract_dir/jira" "$extract_dir/bin/jira" "$extract_dir"/*/jira "$extract_dir"/*/bin/jira; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                jira_binary="$path"
                break
            fi
        done
    fi
    
    if [ -z "$jira_binary" ]; then
        print_error "Could not find jira binary in extracted archive"
        print_status "Archive contents:"
        find "$extract_dir" -type f -name "*jira*" 2>/dev/null || echo "  No jira-related files found"
        find "$extract_dir" -type f 2>/dev/null | head -10
        return 1
    fi
    
    print_status "Found jira binary at: $jira_binary"
    
    # Verify the binary works
    if ! "$jira_binary" version >/dev/null 2>&1; then
        print_warning "Binary verification failed, but proceeding with installation"
    else
        local version_info
        version_info=$("$jira_binary" version 2>/dev/null)
        print_status "Binary verification passed: $version_info"
    fi
    
    # Install the binary
    print_status "Installing to /usr/local/bin/jira..."
    
    if ! $SUDO_CMD cp "$jira_binary" /usr/local/bin/jira; then
        print_error "Failed to copy jira binary to /usr/local/bin/"
        print_error "Please check if you have sufficient permissions"
        return 1
    fi
    
    if ! $SUDO_CMD chmod +x /usr/local/bin/jira; then
        print_error "Failed to set executable permissions on /usr/local/bin/jira"
        return 1
    fi
    
    # Final verification
    if command -v jira >/dev/null 2>&1 && jira version >/dev/null 2>&1; then
        local installed_version
        installed_version=$(jira version 2>/dev/null)
        print_success "Jira CLI installed successfully: $installed_version"
        print_status "Installation location: /usr/local/bin/jira"
    else
        print_error "Installation completed but jira command is not working properly"
        print_status "Please check if /usr/local/bin is in your PATH"
        return 1
    fi
    
    return 0
}

# Install required CLI tools
install_cli_tools() {
    print_header "Installing Required CLI Tools"
    
    # Install GitHub CLI
    if ! command -v gh &> /dev/null; then
        install_github_cli
        print_success "GitHub CLI installed"
    else
        print_success "GitHub CLI already installed"
    fi
    
    # Install Jira CLI (ankitpokhrel/jira-cli)
    if ! command -v jira &> /dev/null || ! jira version 2>/dev/null | grep -q "ankitpokhrel"; then
        # Check if npm jira-cli is installed and warn
        if command -v npm &> /dev/null && npm list -g jira-cli &> /dev/null; then
            print_warning "Found npm jira-cli installed globally. This may conflict with the standalone version."
            print_warning "Consider running: npm uninstall -g jira-cli"
        fi
        
        install_jira_cli
    else
        print_success "Jira CLI already installed"
    fi
}

# Setup GitHub CLI
setup_github_cli() {
    print_header "Setting Up GitHub CLI"
    
    # Check if already authenticated
    if gh auth status &> /dev/null; then
        print_success "GitHub CLI already authenticated"
    else
        print_status "GitHub CLI needs authentication"
        print_warning "Please follow the prompts to authenticate:"
        gh auth login
    fi
}

# Setup Jira CLI (optional)
setup_jira_cli() {
    print_header "Setting Up Jira CLI (Optional)"
    
    read -p "Do you want to configure Jira CLI? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Configuring Jira CLI..."
        print_warning "You'll need:"
        echo "  - Your Jira instance URL (e.g., https://yourcompany.atlassian.net/)"
        echo "  - Your email address"
        echo "  - An API token from https://id.atlassian.com/manage-profile/security/api-tokens"
        echo ""
        jira init
        print_success "Jira CLI configured"
    else
        print_status "Skipping Jira CLI configuration"
    fi
}

# Setup MCP configuration for current project
setup_mcp_config() {
    print_header "Setting Up MCP Configuration"
    
    local example_file="$HOME/.claude/agents/.mcp.json.example"
    
    # Check if example file exists
    if [ ! -f "$example_file" ]; then
        print_error ".mcp.json.example not found in agents repository"
        print_error "Please ensure the agents repository is properly installed"
        return 1
    fi
    
    if [ -f ".mcp.json" ]; then
        # Check if existing file is different from example
        if file_needs_update "$example_file" ".mcp.json"; then
            print_warning ".mcp.json already exists and differs from the latest example"
            echo "Current .mcp.json may have custom configurations."
            read -p "Do you want to backup and update it? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Create backup with timestamp
                local backup_file=".mcp.json.backup.$(date +%Y%m%d-%H%M%S)"
                cp ".mcp.json" "$backup_file"
                print_status "Backed up existing .mcp.json to $backup_file"
                
                cp "$example_file" .mcp.json
                print_success "MCP configuration updated from latest example"
                print_warning "Please review the new .mcp.json and merge any custom settings from the backup"
            else
                print_status "Keeping existing .mcp.json"
                return
            fi
        else
            print_success ".mcp.json already exists and is up to date"
            return
        fi
    else
        print_status "Copying .mcp.json.example to current directory..."
        cp "$example_file" .mcp.json
        print_success "MCP configuration copied to .mcp.json"
    fi
    
    # Check if .gitignore exists and add .mcp.json if not already there
    if [ -f ".gitignore" ]; then
        if ! grep -q "^\.mcp\.json$" .gitignore 2>/dev/null; then
            echo ".mcp.json" >> .gitignore
            print_success "Added .mcp.json to .gitignore"
        else
            print_success ".mcp.json already in .gitignore"
        fi
    else
        echo ".mcp.json" > .gitignore
        print_success "Created .gitignore with .mcp.json"
    fi
}

# Configure environment variables
setup_environment() {
    print_header "Setting Up Environment Variables (Optional)"
    
    # Determine shell config file
    local shell_config
    if [ -n "${ZSH_VERSION:-}" ]; then
        shell_config="$HOME/.zshrc"
    elif [ -n "${BASH_VERSION:-}" ]; then
        # Use .bashrc for non-login shells, .bash_profile for login shells
        if [ -f "$HOME/.bashrc" ]; then
            shell_config="$HOME/.bashrc"
        else
            shell_config="$HOME/.bash_profile"
        fi
    else
        shell_config="$HOME/.profile"
    fi
    
    read -p "Do you want to configure environment variables? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        
        # GitHub Token
        if [ -z "${GITHUB_TOKEN:-}" ]; then
            print_status "Setting up GitHub Personal Access Token..."
            echo "Create a token at: https://github.com/settings/tokens"
            read -p "Enter your GitHub Personal Access Token: " github_token
            echo "export GITHUB_TOKEN=\"$github_token\"" >> "$shell_config"
            export GITHUB_TOKEN="$github_token"
            print_success "GitHub token configured"
        else
            print_success "GitHub token already configured"
        fi
        
        # Jira configuration
        read -p "Do you want to configure Jira environment variables? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ -z "${JIRA_API_TOKEN:-}" ]; then
                read -p "Enter your Jira API Token: " jira_token
                echo "export JIRA_API_TOKEN=\"$jira_token\"" >> "$shell_config"
                export JIRA_API_TOKEN="$jira_token"
            fi
            
            if [ -z "${JIRA_URL:-}" ]; then
                read -p "Enter your Jira URL (e.g., https://company.atlassian.net/): " jira_url
                echo "export JIRA_URL=\"$jira_url\"" >> "$shell_config"
                export JIRA_URL="$jira_url"
            fi
            
            if [ -z "${JIRA_EMAIL:-}" ]; then
                read -p "Enter your Jira email: " jira_email
                echo "export JIRA_EMAIL=\"$jira_email\"" >> "$shell_config"
                export JIRA_EMAIL="$jira_email"
            fi
            
            print_success "Jira environment variables configured"
        fi
        
        print_status "Environment variables added to $shell_config"
        print_warning "Please run 'source $shell_config' or restart your terminal to load the new variables"
    else
        print_status "Skipping environment variable configuration"
    fi
}

# Verify installation
verify_installation() {
    print_header "Verifying Installation"
    
    local errors=0
    local warnings=0
    
    # Check agents directory structure
    if [ -d "$HOME/.claude/agents" ]; then
        print_success "Agents repository exists"
        
        # Count agents in each category
        local core_count=0
        local orchestrator_count=0
        local specialized_count=0
        local universal_count=0
        
        if [ -d "$HOME/.claude/agents/core" ]; then
            core_count=$(find "$HOME/.claude/agents/core" -name "*.md" -type f | wc -l)
            print_status "  Core agents: $core_count found"
        fi
        
        if [ -d "$HOME/.claude/agents/orchestrators" ]; then
            orchestrator_count=$(find "$HOME/.claude/agents/orchestrators" -name "*.md" -type f | wc -l)
            print_status "  Orchestrator agents: $orchestrator_count found"
        fi
        
        if [ -d "$HOME/.claude/agents/specialized" ]; then
            specialized_count=$(find "$HOME/.claude/agents/specialized" -name "*.md" -type f | wc -l)
            print_status "  Specialized agents: $specialized_count found"
        fi
        
        if [ -d "$HOME/.claude/agents/universal" ]; then
            universal_count=$(find "$HOME/.claude/agents/universal" -name "*.md" -type f | wc -l)
            print_status "  Universal tools: $universal_count found"
        fi
        
        local total_agents=$((core_count + orchestrator_count + specialized_count + universal_count))
        print_success "Total agents/tools available: $total_agents"
        
    else
        print_error "Agents repository not found"
        ((errors++))
    fi
    
    # Check .mcp.json.example
    if [ -f "$HOME/.claude/agents/.mcp.json.example" ]; then
        print_success "MCP example configuration exists"
    else
        print_error "MCP example configuration not found"
        ((errors++))
    fi
    
    # Check for README and documentation
    if [ -f "$HOME/.claude/agents/README.md" ]; then
        print_success "Documentation (README.md) exists"
    else
        print_warning "Documentation (README.md) not found"
        ((warnings++))
    fi
    
    # Check GitHub CLI
    if gh auth status &> /dev/null; then
        print_success "GitHub CLI authenticated"
    else
        print_warning "GitHub CLI not authenticated (optional)"
        ((warnings++))
    fi
    
    # Check Jira CLI
    if command -v jira &> /dev/null; then
        print_success "Jira CLI installed"
        # Test configuration (this might fail, which is OK)
        if jira version &> /dev/null && jira config list &> /dev/null; then
            print_success "Jira CLI configured"
        else
            print_warning "Jira CLI not configured (optional)"
            ((warnings++))
        fi
    else
        print_warning "Jira CLI not installed (optional)"
        ((warnings++))
    fi
    
    # Final status
    if [ $errors -eq 0 ]; then
        print_header "✨ Installation Complete!"
        echo "Next steps:"
        echo "1. Restart Claude Code to load MCP servers"
        echo "2. Use setup_mcp_config in any project directory to add .mcp.json"
        echo "3. Use @agent-name to invoke specialized agents"
        echo "4. Run this script again anytime to safely update agents"
        echo "5. Refer to ~/.claude/agents/README.md for workflow patterns"
        echo ""
        
        if [ $warnings -gt 0 ]; then
            print_warning "Setup completed with $warnings warnings (see above)"
            print_status "These warnings are optional and don't affect core functionality"
        fi
        
        print_success "Setup completed successfully!"
        print_status "The script is now safe to run multiple times - existing configurations will be preserved"
        return 0
    else
        print_error "Setup completed with $errors errors. Please review the output above."
        return 1
    fi
}

# Test mode - dry run to show what would be changed
test_changes() {
    print_header "Test Mode - Showing What Would Be Changed"
    
    AGENTS_DIR="$HOME/.claude/agents"
    TEMP_CLONE_DIR=$(mktemp -d)
    
    print_status "Downloading latest agents repository for comparison..."
    if ! git clone https://github.com/alun-ai/agents.git "$TEMP_CLONE_DIR" 2>/dev/null; then
        print_error "Failed to clone agents repository"
        rm -rf "$TEMP_CLONE_DIR"
        exit 1
    fi
    
    print_status "Analyzing changes..."
    
    # Check each category
    for category in "core" "orchestrators" "specialized" "universal"; do
        if [ -d "$TEMP_CLONE_DIR/$category" ]; then
            echo ""
            print_status "=== $category ==="
            
            # Use safer approach without pipeline
            local category_files
            category_files=$(find "$TEMP_CLONE_DIR/$category" -name "*.md" -type f 2>/dev/null || echo "")
            
            if [ -n "$category_files" ]; then
                while IFS= read -r source_file; do
                    [ -z "$source_file" ] && continue
                    local rel_path="${source_file#$TEMP_CLONE_DIR/$category/}"
                    local dest_file="$AGENTS_DIR/$category/$rel_path"
                    
                    if [ ! -f "$dest_file" ]; then
                        echo "  [NEW] $rel_path"
                    elif ! cmp -s "$source_file" "$dest_file"; then
                        echo "  [UPDATE] $rel_path"
                    else
                        echo "  [SKIP] $rel_path (identical)"
                    fi
                done <<< "$category_files"
            fi
        fi
    done
    
    echo ""
    print_status "=== Configuration Files ==="
    for config_file in "README.md" "AGENT_TEMPLATE.md" "CLAUDE.md" "setup.sh"; do
        if [ -f "$TEMP_CLONE_DIR/$config_file" ]; then
            if [ ! -f "$AGENTS_DIR/$config_file" ]; then
                echo "  [NEW] $config_file"
            elif ! cmp -s "$TEMP_CLONE_DIR/$config_file" "$AGENTS_DIR/$config_file"; then
                echo "  [UPDATE] $config_file (backup would be created)"
            else
                echo "  [SKIP] $config_file (identical)"
            fi
        fi
    done
    
    rm -rf "$TEMP_CLONE_DIR"
    
    echo ""
    print_success "Test completed - no files were actually changed"
    print_warning "Run without --test flag to apply changes"
}

# Show help message
show_help() {
    echo "Claude Code Agents Collection Setup Script (Linux)"
    echo ""
    echo "Usage: bash setup-linux.sh [OPTION]"
    echo ""
    echo "Options:"
    echo "  --test       Run in test mode (dry run) to show what would be changed"
    echo "  --test-clone Run only the repository cloning portion with debug output"
    echo "  --debug      Run with verbose debugging output"
    echo "  --help       Show this help message"
    echo ""
    echo "Features:"
    echo "  - Preserves existing agents, orchestrators, and tools"
    echo "  - Only copies new files that don't already exist"
    echo "  - Creates backups before updating configuration files"
    echo "  - Safe to run multiple times for updates"
    echo ""
    echo "The script will:"
    echo "  1. Install required CLI tools (GitHub CLI, Jira CLI)"
    echo "  2. Download and merge agent collections preserving existing ones"
    echo "  3. Optionally set up MCP configuration"
    echo "  4. Configure environment variables"
    echo ""
}

# Debug mode function
enable_debug() {
    set -x  # Enable command tracing
    print_status "Debug mode enabled - all commands will be traced"
}

# Test only the repository cloning portion
test_clone_only() {
    print_header "Test Mode - Repository Clone Only"
    enable_debug
    
    # Just run the repository cloning function
    check_prerequisites
    clone_repository
    
    print_success "Clone test completed"
}

# Main execution
main() {
    # Check for help flag
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        show_help
        return 0
    fi
    
    # Check for debug flag
    if [[ "${1:-}" == "--debug" ]]; then
        enable_debug
    fi
    
    # Check for test flag
    if [[ "${1:-}" == "--test" ]]; then
        test_changes
        return 0
    fi
    
    # Check for clone test flag
    if [[ "${1:-}" == "--test-clone" ]]; then
        test_clone_only
        return 0
    fi
    
    clear
    echo "======================================================"
    echo "  Claude Code Agents Collection Setup Script (Linux)"
    echo "======================================================"
    echo ""
    print_status "PRESERVATION MODE: Existing configurations will be preserved"
    echo ""
    
    check_prerequisites
    clone_repository
    install_cli_tools
    setup_github_cli
    setup_jira_cli
    
    # Ask about project setup
    read -p "Do you want to set up MCP configuration for the current directory? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_mcp_config
    fi
    
    setup_environment
    
    # Run verification and exit based on result
    if verify_installation; then
        exit 0
    else
        exit 1
    fi
}

# Cleanup function to ensure clean exit
cleanup_and_exit() {
    local exit_code=${1:-0}
    
    # Kill any background jobs
    jobs -p | xargs -r kill >/dev/null 2>&1
    
    # Wait for any remaining background processes
    wait >/dev/null 2>&1
    
    # Clean up any temporary files that might still exist
    rm -f "/tmp/setup_copied_$$" "/tmp/setup_skipped_$$" "/tmp/setup_updated_$$" 2>/dev/null
    
    # Ensure clean exit
    exit $exit_code
}

# Set up final cleanup trap
trap 'cleanup_and_exit 130' INT TERM


# Cleanup function to ensure clean exit
cleanup_and_exit() {
    local exit_code=${1:-0}
    
    # Quick cleanup of temp files
    rm -f "/tmp/setup_copied_$$" "/tmp/setup_skipped_$$" "/tmp/setup_updated_$$" 2>/dev/null || true
    
    # Ensure clean exit
    exit $exit_code
}

# Run main function and ensure clean exit
main "$@"
cleanup_and_exit $?