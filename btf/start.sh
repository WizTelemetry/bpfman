#!/bin/sh

set -e

echo "Initializing BPF maps with socket-tracer and tcp-stats-go..."

# Get kernel version
KERNEL_VERSION=$(uname -r)
echo "Current kernel version: ${KERNEL_VERSION}"

# First check for exact match BTF file
BTF_FILE="/opt/bpfman/btf/${KERNEL_VERSION}.vmlinux"

# If exact match not found, try finding a potentially matching BTF file
if [ ! -f "${BTF_FILE}" ]; then
    # Get the kernel base version (like 4.19.90)
    KERNEL_BASE=$(echo ${KERNEL_VERSION} | cut -d'-' -f1)
    # Find any BTF file that starts with the base version
    POTENTIAL_BTF=$(find /opt/bpfman/btf -name "${KERNEL_BASE}*.vmlinux" -type f | head -1)
    if [ -n "${POTENTIAL_BTF}" ]; then
        BTF_FILE="${POTENTIAL_BTF}"
        echo "Found potential matching BTF file: ${BTF_FILE}"
    fi
fi

# Proper signal handling for container environment
cleanup() {
    echo "Received signal, cleaning up..."
    
    # Clean up socket-tracer
    if [ -n "${SOCKET_TRACER_PID}" ] && ps -p ${SOCKET_TRACER_PID} > /dev/null; then
        echo "Stopping socket-tracer (PID: ${SOCKET_TRACER_PID})"
        kill -TERM ${SOCKET_TRACER_PID} 2>/dev/null || true
        # Give it a moment to exit gracefully
        sleep 2
        # Force kill if still running
        if ps -p ${SOCKET_TRACER_PID} > /dev/null; then
            kill -9 ${SOCKET_TRACER_PID} 2>/dev/null || true
        fi
    fi
    
    # Clean up tcp-stats-go
    if [ -n "${TCP_STATS_PID}" ] && ps -p ${TCP_STATS_PID} > /dev/null; then
        echo "Stopping tcp-stats-go (PID: ${TCP_STATS_PID})"
        kill -TERM ${TCP_STATS_PID} 2>/dev/null || true
        # Give it a moment to exit gracefully
        sleep 2
        # Force kill if still running
        if ps -p ${TCP_STATS_PID} > /dev/null; then
            kill -9 ${TCP_STATS_PID} 2>/dev/null || true
        fi
    fi
    
    echo "Exiting container..."
    exit 0
}

# Set up signal trapping
trap cleanup INT TERM

# Only start eBPF agents if we found a custom BTF file
if [ -f "${BTF_FILE}" ]; then
    echo "Using BTF file: ${BTF_FILE}"
    
    # Start socket-tracer
    echo "Starting socket-tracer..."
    /usr/local/bin/socket-tracer --init-only --btf-path "${BTF_FILE}" &
    
    # Store socket-tracer PID for cleanup
    SOCKET_TRACER_PID=$!
    echo "socket-tracer started with PID ${SOCKET_TRACER_PID}"
    
    # Start tcp-stats-go
    echo "Starting tcp-stats-go..."
    /usr/local/bin/tcp-stats-go --init-only --btf-path "${BTF_FILE}" &
    
    # Store tcp-stats-go PID for cleanup
    TCP_STATS_PID=$!
    echo "tcp-stats-go started with PID ${TCP_STATS_PID}"

    # Wait briefly to ensure both processes have time to initialize and load BPF programs
    sleep 3

    # Verify socket-tracer is running
    if ! ps -p ${SOCKET_TRACER_PID} > /dev/null; then
        echo "ERROR: socket-tracer failed to start"
        exit 1
    fi
    
    # Verify tcp-stats-go is running
    if ! ps -p ${TCP_STATS_PID} > /dev/null; then
        echo "ERROR: tcp-stats-go failed to start"
        exit 1
    fi
else
    echo "No suitable BTF file found for kernel ${KERNEL_VERSION}"
    # only start tcp-stats-go if no custom BTF file is found
    echo "Starting tcp-stats-go..."
    /usr/local/bin/tcp-stats-go --init-only --btf-path "${BTF_FILE}" &
fi

echo "Starting bpfman-rpc..."
# Using exec for the primary container process to ensure signal handling
exec ./bpfman-rpc --timeout=0