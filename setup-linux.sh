#!/bin/bash

# Claude Code Agents Collection - Automated Setup Script (Linux)
# ============================================================
# This script automates the installation and configuration of the Claude Code Agents collection for Linux
# Supports Ubuntu/Debian (apt), CentOS/RHEL/Fedora (yum/dnf), and Arch Linux (pacman)
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

# Clone the agents repository
clone_repository() {
    print_header "Setting Up Agents Repository"
    
    AGENTS_DIR="$HOME/.claude/agents"
    
    if [ -d "$AGENTS_DIR" ]; then
        print_warning "Agents directory already exists at $AGENTS_DIR"
        read -p "Do you want to update it? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Updating agents repository..."
            cd "$AGENTS_DIR"
            git pull origin main
            print_success "Repository updated"
        else
            print_status "Keeping existing repository"
        fi
    else
        print_status "Cloning agents repository..."
        cd "$HOME/.claude"
        git clone https://github.com/alun-ai/agents.git
        print_success "Repository cloned to $AGENTS_DIR"
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
    
    # Install from GitHub releases
    local latest_release
    latest_release=$(curl -s https://api.github.com/repos/ankitpokhrel/jira-cli/releases/latest | grep -o '"tag_name": "[^"]*' | grep -o '[^"]*$')
    
    if [ -z "$latest_release" ]; then
        print_error "Failed to get latest Jira CLI release"
        return 1
    fi
    
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) print_error "Unsupported architecture: $arch"; return 1 ;;
    esac
    
    local download_url="https://github.com/ankitpokhrel/jira-cli/releases/download/${latest_release}/jira_${latest_release#v}_linux_${arch}.tar.gz"
    local temp_dir
    temp_dir=$(mktemp -d)
    
    print_status "Downloading Jira CLI ${latest_release} for ${arch}..."
    if curl -L "$download_url" | tar -xz -C "$temp_dir"; then
        $SUDO_CMD mv "$temp_dir/bin/jira" /usr/local/bin/jira
        $SUDO_CMD chmod +x /usr/local/bin/jira
        rm -rf "$temp_dir"
        print_success "Jira CLI installed to /usr/local/bin/jira"
    else
        print_error "Failed to download and install Jira CLI"
        rm -rf "$temp_dir"
        return 1
    fi
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
    
    if [ -f ".mcp.json" ]; then
        print_warning ".mcp.json already exists in current directory"
        read -p "Do you want to replace it? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Keeping existing .mcp.json"
            return
        fi
    fi
    
    print_status "Copying .mcp.json.example to current directory..."
    cp "$HOME/.claude/agents/.mcp.json.example" .mcp.json
    print_success "MCP configuration copied to .mcp.json"
    
    # Check if .gitignore exists and add .mcp.json if not already there
    if [ -f ".gitignore" ]; then
        if ! grep -q "^\.mcp\.json$" .gitignore; then
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
    
    # Check agents directory
    if [ -d "$HOME/.claude/agents" ]; then
        print_success "Agents repository exists"
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
    
    # Check GitHub CLI
    if gh auth status &> /dev/null; then
        print_success "GitHub CLI authenticated"
    else
        print_warning "GitHub CLI not authenticated (optional)"
    fi
    
    # Check Jira CLI
    if command -v jira &> /dev/null; then
        print_success "Jira CLI installed"
        # Test configuration (this might fail, which is OK)
        if jira list --query "project = TEST" --max-results 1 &> /dev/null; then
            print_success "Jira CLI configured"
        else
            print_warning "Jira CLI not configured (optional)"
        fi
    else
        print_warning "Jira CLI not installed (optional)"
    fi
    
    if [ $errors -eq 0 ]; then
        print_header "✨ Installation Complete!"
        echo "Next steps:"
        echo "1. Restart Claude Code to load MCP servers"
        echo "2. Copy .mcp.json to your project directory when needed"
        echo "3. Use @agent-name to invoke specialized agents"
        echo "4. Refer to README.md for workflow patterns"
        echo ""
        print_success "Setup completed successfully!"
    else
        print_error "Setup completed with errors. Please review the output above."
        exit 1
    fi
}

# Main execution
main() {
    clear
    echo "======================================================"
    echo "  Claude Code Agents Collection Setup Script (Linux)"
    echo "======================================================"
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
    verify_installation
}

# Run main function
main "$@"