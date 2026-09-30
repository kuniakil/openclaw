#!/bin/sh
set -e

# --- SSH server setup ---
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    echo "[entrypoint-ssh] Setting up SSH server..."
    
    # Generate host keys if not already present
    if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
        ssh-keygen -A
    fi
    
    mkdir -p /var/run/sshd
    
    # Setup for root user (since Zeabur runs as root by default)
    mkdir -p /root/.ssh
    SSH_KEY_CLEAN=$(echo "$SSH_PUBLIC_KEY" | sed 's/^"//;s/"$//')
    echo "$SSH_KEY_CLEAN" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    
    # Setup for node user (just in case)
    mkdir -p /home/node/.ssh
    echo "$SSH_KEY_CLEAN" > /home/node/.ssh/authorized_keys
    chmod 600 /home/node/.ssh/authorized_keys
    chmod 700 /home/node/.ssh
    chown -R node:node /home/node/.ssh

    # Start sshd daemon in background
    /usr/sbin/sshd
    echo "[entrypoint-ssh] SSH server started."
fi
