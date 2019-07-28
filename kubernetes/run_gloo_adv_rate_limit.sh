#!/usr/bin/env bash

# Expects
# brew install kubernetes-cli kubernetes-helm skaffold httpie

# Optional
# brew install go jq; brew cask install minikube

# Based on GlooE Custom Auth server example
# https://gloo.solo.io/enterprise/authentication/custom_auth/

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

PROXY_URL="http://localhost:8080"

#
# Add custom auth-server
#

# Deploy auth-server service
( cd auth_server_rate_limiting_adv; skaffold run )

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
        regex: /service/service\d
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
# curl --verbose --silent --show-error --write-out "%{http_code}\n" $PROXY_URL/service/service1 | jq
http --json $PROXY_URL/service/service1 user:Scott

printf "Should return 403\n"
# curl --verbose --silent --show-error --write-out "%{http_code}\n" $PROXY_URL/service/service2 | jq
http --json $PROXY_URL/service/service2 user:Scott

#
# Add Envoy Rate Limiting
#

kubectl --namespace gloo-system get settings/default --output yaml | tee original_settings.yaml

# Edit Envoy Rate Server Settings
# glooctl edit settings --namespace gloo-system --name default ratelimit custom-server-config

# descriptors:
# - key: account_id
#   descriptors:
#   - key: service
#     value: service1
#     descriptors:
#     - key: plan
#       value: BASIC
#       rateLimit:
#         requestsPerUnit: 1
#         unit: MINUTE
#     - key: plan
#       value: PLUS
#       rateLimit:
#         requestsPerUnit: 2
#         unit: MINUTE
#   - key: service
#     value: service2
#     descriptors:
#     - key: plan
#       value: BASIC
#       rateLimit:
#         requestsPerUnit: 1
#         unit: MINUTE
#     - key: plan
#       value: PLUS
#       rateLimit:
#         requestsPerUnit: 2
#         unit: MINUTE

kubectl --namespace gloo-system patch settings default \
  --type='merge' \
  --patch "$(cat<<EOF
spec:
  extensions:
    configs:
      envoy-rate-limit:
        customConfig:
          descriptors:
          - key: account_id
            descriptors:
            - key: service
              value: service1
              descriptors:
              - key: plan
                value: BASIC
                rateLimit:
                  requestsPerUnit: 1
                  unit: MINUTE
              - key: plan
                value: PLUS
                rateLimit:
                  requestsPerUnit: 2
                  unit: MINUTE
            - key: service
              value: service2
              descriptors:
              - key: plan
                value: BASIC
                rateLimit:
                  requestsPerUnit: 1
                  unit: MINUTE
              - key: plan
                value: PLUS
                rateLimit:
                  requestsPerUnit: 2
                  unit: MINUTE
EOF
)"

# glooctl edit virtualservice --namespace gloo-system --name default ratelimit custom-envoy-config

# rate_limits:
# - actions:
#   - requestHeaders:
#       descriptorKey: account_id
#       headerName: x-account-id
#   - requestHeaders:
#       descriptorKey: service
#       headerName: x-service
#   - requestHeaders:
#       descriptorKey: plan
#       headerName: x-plan

kubectl --namespace gloo-system patch virtualservice default \
  --type='merge' \
  --patch "$(cat<<EOF
spec:
  virtualHost:
    virtualHostPlugins:
      extensions:
        configs:
          envoy-rate-limit:
            rate_limits:
            - actions:
              - requestHeaders:
                  descriptorKey: account_id
                  headerName: x-account-id
              - requestHeaders:
                  descriptorKey: service
                  headerName: x-service
              - requestHeaders:
                  descriptorKey: plan
                  headerName: x-plan
EOF
)"

sleep 15

# Succeed
printf "Should return 200\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Scott" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Scott

# Rate limited - too many calls per minute
printf "Should return 429\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Scott" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Scott

# Rate limited - same account; too many calls per minute
printf "Should return 429\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Yuval" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Yuval

# Succeed - different account
printf "Should return 200\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Jonathan" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Jonathan

# Succeed - PLUS plan so 2 calls per minute
printf "Should return 200\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Jonathan" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Jonathan

# Rate limited - too many calls per minute
printf "Should return 429\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Jonathan" --output /dev/null $PROXY_URL/service/service1
http --headers --json $PROXY_URL/service/service1 user:Jonathan

#
# Rate Limiting descriptor experiments
#

# Edit Envoy Rate Server Settings
# glooctl edit settings --namespace gloo-system --name default ratelimit custom-server-config

# descriptors:
# - key: account_id
#   descriptors:
#   - key: generic_key
#     value: service1
#     descriptors:
#     - key: plan
#       value: BASIC
#       rateLimit:
#         requestsPerUnit: 1
#         unit: MINUTE
#     - key: plan
#       value: PLUS
#       rateLimit:
#         requestsPerUnit: 2
#         unit: MINUTE
#   - key: generic_key
#     value: service2
#     descriptors:
#     - key: plan
#       value: BASIC
#       rateLimit:
#         requestsPerUnit: 1
#         unit: MINUTE
#     - key: plan
#       value: PLUS
#       rateLimit:
#         requestsPerUnit: 2
#         unit: MINUTE

kubectl --namespace gloo-system apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Settings
metadata:
  annotations:
    helm.sh/hook: pre-install
  labels:
    app: gloo
    gloo: settings
  name: default
  namespace: gloo-system
spec:
  bindAddr: 0.0.0.0:9977
  discoveryNamespace: gloo-system
  extensions:
    configs:
      envoy-rate-limit:
        customConfig:
          descriptors:
          - key: account_id
            descriptors:
            - key: generic_key
              value: service1
              descriptors:
              - key: plan
                value: BASIC
                rateLimit:
                  requestsPerUnit: 1
                  unit: MINUTE
              - key: plan
                value: PLUS
                rateLimit:
                  requestsPerUnit: 2
                  unit: MINUTE
            - key: generic_key
              value: service2
              descriptors:
              - key: plan
                value: BASIC
                rateLimit:
                  requestsPerUnit: 1
                  unit: MINUTE
              - key: plan
                value: PLUS
                rateLimit:
                  requestsPerUnit: 2
                  unit: MINUTE
      extauth:
        extauthzServerRef:
          name: gloo-system-auth-server-8000
          namespace: gloo-system
        requestBody:
          maxRequestBytes: 10240
        requestTimeout: 1s
      rate-limit:
        ratelimit_server_ref:
          name: rate-limit
          namespace: gloo-system
  kubernetesArtifactSource: {}
  kubernetesConfigSource: {}
  kubernetesSecretSource: {}
  refreshRate: 60s
EOF

# add route specifc rate limiting
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
        prefix: /service/service1
      routeAction:
        single:
          upstream:
            name: default-echo-server-8080
            namespace: gloo-system
      routePlugins:
        extensions:
          configs:
            envoy-rate-limit:
              includeVhRateLimits: false
              rateLimits:
              - actions:
                - requestHeaders:
                    descriptorKey: account_id
                    headerName: x-account-id
                - genericKey:
                    descriptorValue: service1
                - requestHeaders:
                    descriptorKey: plan
                    headerName: x-plan
    - matcher:
        prefix: /service/service2
      routeAction:
        single:
          upstream:
            name: default-echo-server-8080
            namespace: gloo-system
      routePlugins:
        extensions:
          configs:
            envoy-rate-limit:
              includeVhRateLimits: false
              rateLimits:
              - actions:
                - requestHeaders:
                    descriptorKey: account_id
                    headerName: x-account-id
                - genericKey:
                    descriptorValue: service2
                - requestHeaders:
                    descriptorKey: plan
                    headerName: x-plan
    virtualHostPlugins:
      extensions:
        configs:
          extauth:
            customAuth: {}
EOF

sleep 60

# Succeed
printf "Should return 200\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Scott" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Scott

# Rate limited - too many calls per minute
printf "Should return 429\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Scott" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Scott

# Rate limited - same account; too many calls per minute
printf "Should return 429\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Yuval" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Yuval

# Succeed - different account
printf "Should return 200\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Jonathan" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Jonathan

# Succeed - PLUS plan so 2 calls per minute
printf "Should return 200\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Jonathan" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Jonathan

# Rate limited - too many calls per minute
printf "Should return 429\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Jonathan" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Jonathan

#
# Rate Limiting descriptor experiments 2
#

# Edit Envoy Rate Server Settings
# glooctl edit settings --namespace gloo-system --name default ratelimit custom-server-config

# descriptors:
# - key: account_id
#   descriptors:
#   - key: generic_key
#     value: service1
#     descriptors:
#     - key: plan
#       value: BASIC
#       rateLimit:
#         requestsPerUnit: 1
#         unit: MINUTE
#     - key: plan
#       value: PLUS
#       rateLimit:
#         requestsPerUnit: 2
#         unit: MINUTE
#   - key: generic_key
#     value: service2
#     descriptors:
#     - key: plan
#       value: BASIC
#       rateLimit:
#         requestsPerUnit: 1
#         unit: MINUTE
#     - key: plan
#       value: PLUS
#       rateLimit:
#         requestsPerUnit: 2
#         unit: MINUTE

kubectl --namespace gloo-system apply --filename - <<EOF
apiVersion: gloo.solo.io/v1
kind: Settings
metadata:
  annotations:
    helm.sh/hook: pre-install
  labels:
    app: gloo
    gloo: settings
  name: default
  namespace: gloo-system
spec:
  bindAddr: 0.0.0.0:9977
  discoveryNamespace: gloo-system
  extensions:
    configs:
      envoy-rate-limit:
        customConfig:
          descriptors:
          - key: account_id
            descriptors:
            - key: generic_key
              value: service1
              descriptors:
              - key: plan
                value: BASIC
                rateLimit:
                  requestsPerUnit: 1
                  unit: MINUTE
              - key: plan
                value: PLUS
                rateLimit:
                  requestsPerUnit: 2
                  unit: MINUTE
              - key: plan
                value: PLUS
                descriptors:
                - key: header_match
                  value: special
                  rateLimit:
                    requestsPerUnit: 3
                    unit: MINUTE
            - key: generic_key
              value: service2
              descriptors:
              - key: plan
                value: BASIC
                rateLimit:
                  requestsPerUnit: 1
                  unit: MINUTE
              - key: plan
                value: PLUS
                rateLimit:
                  requestsPerUnit: 2
                  unit: MINUTE
      extauth:
        extauthzServerRef:
          name: gloo-system-auth-server-8000
          namespace: gloo-system
        requestBody:
          maxRequestBytes: 10240
        requestTimeout: 1s
      rate-limit:
        ratelimit_server_ref:
          name: rate-limit
          namespace: gloo-system
  kubernetesArtifactSource: {}
  kubernetesConfigSource: {}
  kubernetesSecretSource: {}
  refreshRate: 60s
EOF

# add route specifc rate limiting
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
        prefix: /service/service1
      routeAction:
        single:
          upstream:
            name: default-echo-server-8080
            namespace: gloo-system
      routePlugins:
        extensions:
          configs:
            envoy-rate-limit:
              includeVhRateLimits: false
              rateLimits:
              - actions:
                - requestHeaders:
                    descriptorKey: account_id
                    headerName: x-account-id
                - genericKey:
                    descriptorValue: service1
                - requestHeaders:
                    descriptorKey: plan
                    headerName: x-plan
                - headerValueMatch:
                    descriptorValue: special
                    headers:
                    - name: 'x-special-header'
                      presentMatch: true
    - matcher:
        prefix: /service/service2
      routeAction:
        single:
          upstream:
            name: default-echo-server-8080
            namespace: gloo-system
      routePlugins:
        extensions:
          configs:
            envoy-rate-limit:
              includeVhRateLimits: false
              rateLimits:
              - actions:
                - requestHeaders:
                    descriptorKey: account_id
                    headerName: x-account-id
                - genericKey:
                    descriptorValue: service2
                - requestHeaders:
                    descriptorKey: plan
                    headerName: x-plan
    virtualHostPlugins:
      extensions:
        configs:
          extauth:
            customAuth: {}
EOF

sleep 60

# Succeed
printf "Should return 200\n"
# curl --silent --show-error --write-out "%{http_code}\n" --header "user:Scott" --output /dev/null $PROXY_URL/service/service1
http --headers $PROXY_URL/service/service1 user:Jonathan x-special-header:somevalue
