#!/bin/sh

# Check if .devcontainer directory exists in the current folder
if [ -d "./.devcontainer" ]; then
    echo "✅ .devcontainer directory found. Proceeding with permissions setup..."

    PROJECT_PATH="./ai_worktree"

    # Apply permissions recursively to all files and folders inside, 
    # but not to the current directory itself
    # chmod -R u+wX,g+wX,o+wX *

    chmod -R u+wX,g+wX,o+wX $PROJECT_PATH/coverage $PROJECT_PATH/log $PROJECT_PATH/tmp

    echo "🚀 Permissions updated successfully for all subdirectories and files in $PROJECT_PATH"

else
    echo "❌ Error: .devcontainer directory not found!"
    echo "Please ensure you are in the project root directory before running this script."
    exit 1
fi
