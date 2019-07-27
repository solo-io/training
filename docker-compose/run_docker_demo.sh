#!/usr/bin/env bash
# Expects
# brew install httpie

# Optional
# brew install jq

# Based on Gloo Gateway local example
# https://gloo.solo.io/installation/gateway/docker-compose/

# Will exit script if we would use an uninitialised variable:
set -o nounset
# Will exit script when a simple command (not a control structure) fails:
set -o errexit

function print_error {
  read line file <<<$(caller)
  echo "An error occurred in line $line of file $file:" >&2
  sed "${line}q;d" "$file" >&2
}
trap print_error ERR

docker-compose up --detach

sleep 20

# curl --silent --show-error ${PROXY_URL:-http://localhost:8080}/petstore | jq
http --json http://localhost:8080/petstore

# curl --silent --show-error ${PROXY_URL:-http://localhost:8080}/petstore/findPets | jq
http --json http://localhost:8080/petstore/findPets

# curl --silent --show-error ${PROXY_URL:-http://localhost:8080}/petstore/findWithId/1 | jq
http --json http://localhost:8080/petstore/findWithId/1

echo "To clean up run docker-compose down"
