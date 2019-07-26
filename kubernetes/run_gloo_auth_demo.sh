#!/usr/bin/env bash

PROXY_URL="http://localhost:8080"

#
# Deploy and configure custom auth-server
#

# Deploy auth-server service
( cd auth_server_go_grpc; skaffold run )

# Wait for deployment to be deployed and running
kubectl --namespace gloo-system rollout status deployment/auth-server --watch=true

# Patch Gloo Settings and default Virtual Service to reference custom auth service
kubectl --namespace gloo-system patch settings default \
  --type='merge' \
  --patch "$(cat<<EOF
spec:
  extensions:
    configs:
      extauth:
        extauthzServerRef:
          name: gloo-system-auth-server-8000
          namespace: gloo-system
        requestBody:
          maxRequestBytes: 10240
        requestTimeout: 1s
EOF
)"

# Update Virtual Service to reference custom auth-server
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
    virtualHostPlugins:
      extensions:
        configs:
          extauth:
            customAuth: {}
EOF

sleep 5
until [[ $(kubectl --namespace gloo-system get virtualservice default -o=jsonpath='{.status.state}') = "1" ]]; do
  sleep 5
done

sleep 10

printf "Should return 200\n"
# curl --verbose --silent --show-error --write-out "%{http_code}\n" --headers "x-user: authorized" ${PROXY_URL:-http://localhost:8080}/ | jq
http --json ${PROXY_URL:-http://localhost:8080}/ x-user:authorized

printf "Should return 403\n"
# curl --verbose --silent --show-error --write-out "%{http_code}\n" ${PROXY_URL:-http://localhost:8080}/ | jq
http --json ${PROXY_URL:-http://localhost:8080}/
