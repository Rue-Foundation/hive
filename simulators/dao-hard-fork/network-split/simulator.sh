#!/bin/bash
set -e

# Create and start a valid bootnode for the clients to find each other
BOOTNODE_KEYHEX=5ce1f6fc42c817c38939498ee7fcdd9a06fa9d947d02d42dfe814406f370c4eb
BOOTNODE_ENODEID=6433e8fb82c4638a8a6d499d40eb7d8158883219600bfd49acb968e3a37ccced04c964fa87b3a78a2da1b71dc1b90275f4d055720bb67fad4a118a56925125dc

BOOTNODE_IP=`ifconfig eth0 | grep 'inet addr' | cut -d: -f2 | awk '{print $1}'`
BOOTNODE_ENODE="enode://$BOOTNODE_ENODEID@$BOOTNODE_IP:30303"

/bootnode --nodekeyhex $BOOTNODE_KEYHEX --addr=0.0.0.0:30303 &

# Configure the simulation parameters
NO_FORK_NODES=1	 # Number of plain no-fork nodes to boot up (+1 miner)
PRO_FORK_NODES=1	# Number of plain pro-fork nodes to boot up (+1 miner)
PRE_FORK_PEERS=3	# Number of peers to require pre-fork (total - 1)
POST_FORK_PEERS=1 # Number of peers to require post-fork (same camp - 1)

# netPeerCount executes an RPC request to a node to retrieve its current number
# of connected peers.
#
# If looks up the IP address of the node from the hive simulator and executes the
# actual peer lookup. As the result is hex encoded, it will decode and return it.
function netPeerCount {
	local peers=`curl -sf -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":0}' $1:8545 | jq '.result' | tr -d '"'`
	echo $((16#${peers#*x}))
}

# waitPeers verifies whether a node has a given number of peers, and if not waits
# a bit and retries a few times (to avoid devp2p pending handshakes and similar
# anomalies). If the peer count doesn't converge to the desired target, the method
# will fail.
function waitPeers {
	local ip=`curl -sf $HIVE_SIMULATOR/nodes/$1`

	for i in `seq 1 100`; do
		# Fetch the current peer count and stop if it's correct
		peers=`netPeerCount $ip`
		echo "Script waitPeers result $peers vs $2 for $ip"
		if [ "$peers" == "$2" ]; then
			break
		fi
		# Seems peer count is wrong, unless too many trials, sleep a bit and retry
		if [ "$i" == "100" ]; then
			echo "Invalid peer count for $1 ($ip): have $peers, want $2"
			exit -1
		fi

		sleep 2
	done
}

# ethBlockNumber executes an RPC request to a node to retrieve its current block
# number.
#
# If looks up the IP address of the node from the hive simulator and executes the
# actual number lookup. As the result is hex encoded, it will decode and return it.
function ethBlockNumber {
	local block=`curl -sf -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' $1:8545 | jq '.result' | tr -d '"'`
	echo $((16#${block#*x}))
}

# waitBlock waits until the block number of a remote node is at least the specified
# one, periodically polling and sleeping otherwise. There is no timeout, the method
# will block until it succeeds.
function waitBlock {
    echo "Wait for block with [$1] [$2]"
	local ip=`curl -sf $HIVE_SIMULATOR/nodes/$1`
	echo "Script waitBlock ip ${ip}"

	while [ true ]; do
		block=`ethBlockNumber $ip`
		echo " "
		if [ "$block" -gt "$2" ]; then
			break
		fi
		echo "Script waitBlock result ${block}"
		sleep 2
	done
}

function startMining {
    echo "Start mining [$1]"
    local ip=`curl -sf $HIVE_SIMULATOR/nodes/$1`

	while [ true ]; do
		result=`curl -sf -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"miner_start","params":[],"id":1}' $ip:8545 | jq '.result' | tr -d '"'`
		echo " "
		if [ "$result" == "true" ]; then
			break
		fi
		echo "Script startMining result ${result}"
		sleep 2
	done
}

nofork=()
profork=()

## Start the miners for the two camps
nofork+=(`curl -sf -X POST --data-urlencode "HIVE_BOOTNODE=$BOOTNODE_ENODE" $HIVE_SIMULATOR/nodes?HIVE_FORK_DAO_VOTE=0\&HIVE_MINER=0x0000000000000000000000000000000000000001\&HIVE_MINER_NO_AUTO_MINE=1`)
profork+=(`curl -sf -X POST --data-urlencode "HIVE_BOOTNODE=$BOOTNODE_ENODE" $HIVE_SIMULATOR/nodes?HIVE_FORK_DAO_VOTE=1\&HIVE_MINER=0x0000000000000000000000000000000000000001\&HIVE_MINER_NO_AUTO_MINE=1`)
sleep 1

# Start a batch of clients for the no-fork camp
for i in `seq 1 $NO_FORK_NODES`; do
	echo "Starting no-fork client #$i..."
	nofork+=(`curl -sf -X POST --data-urlencode "HIVE_BOOTNODE=$BOOTNODE_ENODE" $HIVE_SIMULATOR/nodes?HIVE_FORK_DAO_VOTE=0`)
	sleep 1 # Wait a bit until it's registered by the bootnode
done

# Start a batch of clients for the pro-fork camp
for i in `seq 1 $PRO_FORK_NODES`; do
	echo "Starting pro-fork client #$i..."
	profork+=(`curl -sf -X POST --data-urlencode "HIVE_BOOTNODE=$BOOTNODE_ENODE" $HIVE_SIMULATOR/nodes?HIVE_FORK_DAO_VOTE=1`)
	sleep 1 # Wait a bit until it's registered by the bootnode
done

allnodes=( "${nofork[@]}" "${profork[@]}" )

# Wait a bit for the nodes to all find each other
for id in ${allnodes[@]}; do
	waitPeers $id $PRE_FORK_PEERS
done

echo "Start mining"
startMining ${nofork[0]}
startMining ${profork[0]}

echo "Profork peers ${profork[*]}"
echo "Nofork peers ${nofork[*]}"

# Wait until all miners pass the DAO fork block range
#waitBlock ${nofork[$NO_FORK_NODES]} $((HIVE_FORK_DAO_BLOCK + 10))
#waitBlock ${profork[$PRO_FORK_NODES]} $((HIVE_FORK_DAO_BLOCK + 10))
waitBlock ${nofork[0]} $((HIVE_FORK_DAO_BLOCK + 10))
waitBlock ${profork[0]} $((HIVE_FORK_DAO_BLOCK + 10))

# Check that we have two disjoint set of nodes
echo "Final check with waitPeers"
for id in ${allnodes[@]}; do
	waitPeers $id $POST_FORK_PEERS
done
