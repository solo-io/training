#!/usr/bin/env bash

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


# # Start Consul
# consul agent -dev --client 0.0.0.0

# # Start Vault
# vault server -dev -dev-root-token-id=root \
#   -log-level=trace \
#   -dev-listen-address 0.0.0.0:8200

# # Start Nomad
# sudo nomad agent -dev \
#   -vault-enabled=true \
#   -vault-address=http://127.0.0.1:8200 \
#   -vault-token=root \
#   -network-interface docker0


vault policy write gloo /vagrant/gloo-policy.hcl

export DOCKER_IP=$(/sbin/ifconfig docker0 | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')

nomad run petstore.nomad

sleep 10

docker ps

export PETSTORE_IP=$(docker inspect $(docker ps | grep petstore | awk '{print $1}') -f '{{printf "%v" (index (index (index .NetworkSettings.Ports "8080/tcp") 0) "HostIp")}}')
export PETSTORE_PORT=$(docker inspect $(docker ps | grep petstore | awk '{print $1}') -f '{{printf "%v" (index (index (index .NetworkSettings.Ports "8080/tcp") 0) "HostPort")}}')
export PETSTORE_URL=http://${PETSTORE_IP}:${PETSTORE_PORT}

printf "PETSTORE_URL (%s) should equal 'http://172.17.0.1:20222'\n", $PETSTORE_URL

echo "Call petstore direct"
# curl $PETSTORE_URL/api/pets
http --json $PETSTORE_URL/api/pets

nomad run gloo.nomad

sleep 10

echo "Call through Gloo"
# curl $DOCKER_IP:28080/petstore
http --json $DOCKER_IP:28080/petstore

# curl $DOCKER_IP:28080/petstore/findWithId/2
http --json $DOCKER_IP:28080/petstore/findWithId/2
