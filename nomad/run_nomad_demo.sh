#!/usr/bin/env bash

# Expects
# brew install nomad consul vault httpie

# Optional
# brew install jq

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

# Get directory this script is located in to access script local files
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Cleanup from past sessions

NOMAD_PID_FILE="$SCRIPT_DIR/nomad.pid"
if [[ -f "$NOMAD_PID_FILE" ]]; then
  (cat "$NOMAD_PID_FILE" | xargs kill) && true # Ignore errors killing old process
  rm "$NOMAD_PID_FILE"
fi

VAULT_PID_FILE="$SCRIPT_DIR/vault.pid"
if [[ -f "$VAULT_PID_FILE" ]]; then
  (cat "$VAULT_PID_FILE" | xargs kill) && true # Ignore errors killing old process
  rm "$VAULT_PID_FILE"
fi

CONSUL_PID_FILE="$SCRIPT_DIR/consul.pid"
if [[ -f "$CONSUL_PID_FILE" ]]; then
  (cat "$CONSUL_PID_FILE" | xargs kill) && true # Ignore errors killing old process
  rm "$CONSUL_PID_FILE"
fi

# Start Consul
consul agent -dev --client 0.0.0.0 -data-dir=$(pwd)/consul-data >consul.log 2>&1 &

echo $! > "$CONSUL_PID_FILE"

# Start Vault
vault server -dev -dev-root-token-id=root \
  -log-level=trace \
  -dev-listen-address 0.0.0.0:8200 \
  >vault.log 2>&1 &

echo $! > "$VAULT_PID_FILE"

sleep 5

# Start Nomad
sudo nomad agent -config $(pwd)/nomad-data \
  -vault-enabled=true \
  -vault-address=http://127.0.0.1:8200 \
  -vault-token=root \
  -network-interface docker0 \
  >nomad.log 2>&1 &

echo $! > "$NOMAD_PID_FILE"

sleep 20

VAULT_ADDR=http://127.0.0.1:8200 vault policy write gloo ./gloo-policy.hcl

nomad run ./petstore.nomad
nomad run ./gloo.nomad

DOCKER_IP=$(/sbin/ifconfig docker0 | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')

curl $DOCKER_IP:28080/petstore
