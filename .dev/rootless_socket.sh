#!/bin/sh

# Docker username
TARGET_USER_NAME="docker_rootless"

if [ -z "$DOCKER_USER_ID" ]; then
    USER_ID=$(id -u "$TARGET_USER_NAME" 2>/dev/null)

    if [ $? -eq 0 ]; then
        export DOCKER_USER_ID="$USER_ID"
        echo "✅ DOCKER_USER_ID: $DOCKER_USER_ID (username: $TARGET_USER_NAME)"
    else
        echo "⚠️ Error: User '$TARGET_USER_NAME' Not Found."
    fi
fi

USER_DOCKER_SOCKET_PATH="/run/user/$DOCKER_USER_ID"

if [ -d "$USER_DOCKER_SOCKET_PATH" ]; then
    sudo setfacl -m u:$(whoami):x "$USER_DOCKER_SOCKET_PATH"
    sudo setfacl -m u:$(whoami):rw "$USER_DOCKER_SOCKET_PATH/docker.sock"

    echo "✅ Done: $(whoami) -> $(id -un "$DOCKER_USER_ID") ($DOCKER_USER_ID)"
else
    echo "⚠️ Error: Path Not Found: `$USER_DOCKER_SOCKET_PATH`. Check if Docker is running under `$(id -un "$DOCKER_USER_ID")`."
fi
