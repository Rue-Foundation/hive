#!/usr/bin/env bash

# Immediately abort the script on any error encountered
set -e

cd /ethereumj && git pull

# Initialize the local testchain with the genesis state
echo "Initializing database with genesis state..."
FLAGS="-PmainClass=org.ethereum.Start -PjvmArgs=\"-Dethash.dir=/root/.ethash -Dethash.blockNumber=0 -Xmx2G\""

# Run the go-ethereum implementation with the requested flags
echo "Parameters $FLAGS"
echo "Running DAG generation..."
cd /ethereumj
./gradlew run -PmainClass=org.ethereum.Start -PjvmArgs="-Dethash.dir=/root/.ethash -Dethash.blockNumber=0 -Xmx2G"

