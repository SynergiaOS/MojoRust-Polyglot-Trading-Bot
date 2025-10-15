#!/bin/bash

# Rust Data Consumer Build Script
# This script builds the data consumer with the correct environment settings

set -e

echo "Building Rust data consumer..."

# Clear any problematic Rust flags that might cause LTO conflicts
unset CARGO_ENCODED_RUSTFLAGS
unset RUSTFLAGS

# Set working directory
cd /home/marcin/Projects/MojoRust/rust-modules

# Build in debug mode first
echo "Building in debug mode..."
cargo build --bin data_consumer

if [ $? -eq 0 ]; then
    echo "✅ Debug build successful!"

    # Try release build
    echo "Building in release mode..."
    cargo build --bin data_consumer --release

    if [ $? -eq 0 ]; then
        echo "✅ Release build successful!"
        echo "Binary location: target/release/data_consumer"

        # Test Docker build compatibility
        echo "Testing Docker build compatibility..."
        if [ -f "Dockerfile.data-consumer" ]; then
            echo "✅ Dockerfile.data-consumer found"
            echo "To build with Docker: docker build -f Dockerfile.data-consumer -t data-consumer ."
        else
            echo "❌ Dockerfile.data-consumer not found"
        fi
    else
        echo "❌ Release build failed, but debug build succeeded"
        echo "Binary location: target/debug/data_consumer"
    fi
else
    echo "❌ Debug build failed"
    exit 1
fi