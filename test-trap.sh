#!/bin/bash

# Test script to verify trap handling
set -euo pipefail

# Global variables
TEMP_CLONE_DIR=""
JIRA_TEMP_DIR=""

# Cleanup temporary directories and files safely
cleanup_temp_dirs() {
    echo "Cleanup function called"
    # Clean up temporary directories if they exist
    if [ -n "${TEMP_CLONE_DIR:-}" ] && [ -d "${TEMP_CLONE_DIR:-}" ]; then
        echo "Cleaning up TEMP_CLONE_DIR: $TEMP_CLONE_DIR"
        rm -rf "$TEMP_CLONE_DIR" 2>/dev/null || true
    fi
    
    if [ -n "${JIRA_TEMP_DIR:-}" ] && [ -d "${JIRA_TEMP_DIR:-}" ]; then
        echo "Cleaning up JIRA_TEMP_DIR: $JIRA_TEMP_DIR"
        rm -rf "$JIRA_TEMP_DIR" 2>/dev/null || true
    fi
    
    echo "Cleanup completed"
}

# Cleanup function to ensure clean exit
cleanup_and_exit() {
    local exit_code=${1:-0}
    echo "Cleanup and exit called with code: $exit_code"
    
    # Clean up temporary directories and files
    cleanup_temp_dirs
    
    # Ensure clean exit
    exit $exit_code
}

# Set up signal traps for clean exit
trap 'cleanup_and_exit 130' INT TERM
trap 'cleanup_temp_dirs' EXIT

echo "Setting up temporary directories..."
TEMP_CLONE_DIR=$(mktemp -d)
JIRA_TEMP_DIR=$(mktemp -d)

echo "Created directories:"
echo "  TEMP_CLONE_DIR: $TEMP_CLONE_DIR"
echo "  JIRA_TEMP_DIR: $JIRA_TEMP_DIR"

echo "Sleeping for 10 seconds... press Ctrl+C to test interrupt handling"
sleep 10

echo "Script completed normally"