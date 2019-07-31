#!/usr/bin/env bash

PROXY_URL="http://localhost:8080"

# Create default Virtual Service with route to the application root
kubectl --namespace gloo-system apply --filename - <<EOF
apiVersion: gateway.solo.io/v1
kind: VirtualService
metadata:
  name: default
  namespace: gloo-system
spec:
  virtualHost:
    domains:
    - '*'
    name: gloo-system.default
    routes:
    - matcher:
        prefix: /
      routeAction:
        single:
          upstream:
            name: default-echo-server-8080
            namespace: gloo-system
EOF

# Patch Gloo Settings and default Virtual Service to reference custom auth service

sleep 5

# Deploy auth-server service
( cd auth_server_exercise; skaffold run )

# Wait for deployment to be deployed and running
kubectl --namespace gloo-system rollout status deployment/auth-server --watch=true

printf "Should return 200\n"
# curl --silent --show-error ${PROXY_URL:-http://localhost:8080}/echo | jq
http --json ${PROXY_URL:-http://localhost:8080}/echo

printf "Should return 200 with x-authorized:true\n"
# curl --silent --show-error --headers "x-my-user: Scott" ${PROXY_URL:-http://localhost:8080}/echo | jq
http --json ${PROXY_URL:-http://localhost:8080}/echo x-my-user:Scott

printf "Should return 403\n"
# curl --silent --show-error ${PROXY_URL:-http://localhost:8080}/petstore | jq
http --json ${PROXY_URL:-http://localhost:8080}/petstore

printf "Should return 200\n"
# curl --silent --show-error --headers "x-my-user: Scott" ${PROXY_URL:-http://localhost:8080}/petstore | jq
http --json ${PROXY_URL:-http://localhost:8080}/petstore x-my-user:Scott

printf "Should return 200 from echo-server\n"
# curl --silent --show-error --headers "x-my-user: Scott" --headers "x-my-type: echo" ${PROXY_URL:-http://localhost:8080}/ | jq
http --json ${PROXY_URL:-http://localhost:8080}/ x-my-user:Scott x-my-type:echo

printf "Should return 200 from petstore\n"
# curl --silent --show-error --headers "x-my-user: Scott" --headers "x-my-type: pet" ${PROXY_URL:-http://localhost:8080}/ | jq
http --json ${PROXY_URL:-http://localhost:8080}/ x-my-user:Scott x-my-type:pet

printf "Should return 404\n"
# curl --silent --show-error --headers "x-my-user: Scott" --headers "x-my-type: foo" ${PROXY_URL:-http://localhost:8080}/ | jq
http --json ${PROXY_URL:-http://localhost:8080}/ x-my-user:Scott x-my-type:foo

printf "Should return 403\n"
# curl --silent --show-error --headers "x-my-type: echo" ${PROXY_URL:-http://localhost:8080}/ | jq
http --json ${PROXY_URL:-http://localhost:8080}/ x-my-type:echo

#
# Rate Limiting
#

# Update Gloo settings with Rate Limit descriptors

# Update Virtual Service with Rate Limit descriptors

sleep 60

printf "Should return 200\n"
# curl --silent --show-error ${PROXY_URL:-http://localhost:8080}/echo | jq
http --json ${PROXY_URL:-http://localhost:8080}/echo

printf "Should return 429 rate limited\n"
# curl --silent --show-error ${PROXY_URL:-http://localhost:8080}/echo | jq
http --json ${PROXY_URL:-http://localhost:8080}/echo

printf "Should return 200\n"
# curl --silent --show-error --headers "x-my-user: Scott" ${PROXY_URL:-http://localhost:8080}/petstore | jq
http --json ${PROXY_URL:-http://localhost:8080}/petstore x-my-user:Scott

printf "Should return 200\n"
# curl --silent --show-error --headers "x-my-user: Scott" ${PROXY_URL:-http://localhost:8080}/petstore | jq
http --json ${PROXY_URL:-http://localhost:8080}/petstore x-my-user:Scott

printf "Should return 429 rate limited\n"
# curl --silent --show-error --headers "x-my-user: Scott" ${PROXY_URL:-http://localhost:8080}/petstore | jq
http --json ${PROXY_URL:-http://localhost:8080}/petstore x-my-user:Scott
