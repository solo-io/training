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

# export DOCKER_IP=$(/sbin/ifconfig docker0 | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')

nomad run fabio.nomad

nomad run prometheus.nomad

nomad run petstore.nomad

sleep 10

export PETSTORE_IP=$(docker inspect $(docker ps | grep petstore | awk '{print $1}') -f '{{printf "%v" (index (index (index .NetworkSettings.Ports "8080/tcp") 0) "HostIp")}}')
export PETSTORE_PORT=$(docker inspect $(docker ps | grep petstore | awk '{print $1}') -f '{{printf "%v" (index (index (index .NetworkSettings.Ports "8080/tcp") 0) "HostPort")}}')
export PETSTORE_URL=http://${PETSTORE_IP}:${PETSTORE_PORT}

printf "PETSTORE_URL (%s) should equal 'http://172.17.0.1:20222'\n" $PETSTORE_URL

echo "Call petstore direct"
# curl $PETSTORE_URL/api/pets
http --json $PETSTORE_URL/api/pets

# glooctl add route --default --path-prefix /petstore --dest-name petstore --prefix-rewrite /api/pets --yaml > vs-default.yaml

consul kv put gloo/gateway.solo.io/v1/VirtualService/gloo-system/default - <<EOF
metadata:
  name: default
  namespace: gloo-system
virtualHost:
  domains:
  - '*'
  name: gloo-system.default
  routes:
  - matcher:
      prefix: /petstore/findWithId
    routeAction:
      single:
        destinationSpec:
          rest:
            functionName: findPetById
            parameters:
              headers:
                :path: /petstore/findWithId/{id}
        upstream:
          name: petstore
          namespace: gloo-system
  - matcher:
      prefix: /petstore/findPets
    routeAction:
      single:
        destinationSpec:
          rest:
            functionName: findPets
            parameters: {}
        upstream:
          name: petstore
          namespace: gloo-system
  - matcher:
      prefix: /petstore
    routeAction:
      single:
        upstream:
          name: petstore
          namespace: gloo-system
    routePlugins:
      prefixRewrite:
        prefixRewrite: /api/pets
EOF

# glooctl create upstream consul --name petstore --consul-service petstore --consul-service-tags http --service-spec-type "" --yaml > us-petstore.yaml

consul kv put gloo/gloo.solo.io/v1/Upstream/gloo-system/petstore - <<EOF
metadata:
  name: petstore
  namespace: gloo-system
upstreamSpec:
  consul:
    serviceName: petstore
    serviceTags:
    - http
    serviceSpec:
      rest:
        swaggerInfo:
          url: http://172.17.0.1:20222/swagger.json
        transformations:
          addPet:
            body:
              text: '{"id": {{ default(id, "") }},"name": "{{ default(name, "")}}","tag":
                "{{ default(tag, "")}}"}'
            headers:
              :method:
                text: POST
              :path:
                text: /api/pets
              content-type:
                text: application/json
          deletePet:
            headers:
              :method:
                text: DELETE
              :path:
                text: /api/pets/{{ default(id, "") }}
              content-type:
                text: application/json
          findPetById:
            body: {}
            headers:
              :method:
                text: GET
              :path:
                text: /api/pets/{{ default(id, "") }}
              content-length:
                text: "0"
              content-type: {}
              transfer-encoding: {}
          findPets:
            body: {}
            headers:
              :method:
                text: GET
              :path:
                text: /api/pets?tags={{default(tags, "")}}&limit={{default(limit,
                  "")}}
              content-length:
                text: "0"
              content-type: {}
              transfer-encoding: {}
EOF

nomad run gloo.nomad

sleep 15

export GATEWAY_IP=$(docker inspect $(docker ps | grep gateway-proxy | awk '{print $1}') -f '{{printf "%v" (index (index (index .NetworkSettings.Ports "8080/tcp") 0) "HostIp")}}')
export GATEWAY_PORT=$(docker inspect $(docker ps | grep gateway-proxy | awk '{print $1}') -f '{{printf "%v" (index (index (index .NetworkSettings.Ports "8080/tcp") 0) "HostPort")}}')
export GATEWAY_URL=http://${GATEWAY_IP}:${GATEWAY_PORT}

echo "Call through Gloo"
# curl $GATEWAY_URL/petstore
http --json $GATEWAY_URL/petstore

# curl $GATEWAY_URL/petstore/findWithId/2
http --json $GATEWAY_URL/petstore/findWithId/2
