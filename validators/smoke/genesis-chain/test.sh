#!/bin/sh
set -e

sleep 10s

echo "Hello world!"

# Simply query the 5th block and check that it's correct
reply=`curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["0x05", false],"id":0}' "$HIVE_CLIENT_IP:8545"`

hash=`echo $reply | sed 's/,/\n/g' | grep hash | cut -d ':' -f 2 | tr -d '"'`
test "$hash" == "0x144a62b8c977d61d2dd145fffbc917a61092e6d1be4b7192d834bda8d8ef55fd"
