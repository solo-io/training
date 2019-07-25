#!/usr/bin/env bash
# Expects
# brew install kubernetes-cli kubernetes-helm skaffold httpie

# Optional
# brew install go jq; brew cask install minikube

# Based on GlooE Custom Auth server example
# https://gloo.solo.io/enterprise/authentication/custom_auth/

K8S_TOOL=kind     # kind or minikube
TILLER_MODE=local # local or cluster
GLOO_MODE=ent     # oss or ent
GLOO_VERSION=0.17.3

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

K8S_TOOL="${K8S_TOOL:-kind}" # kind or minikube

case "$K8S_TOOL" in
  kind)
    if [[ -x $(command -v go) ]] && [[ $(go version) =~ "go1.12.[6-9]" ]]; then
      # Install latest version of kind https://kind.sigs.k8s.io/
      GO111MODULE="on" go get sigs.k8s.io/kind@v0.4.0
    fi

    DEMO_CLUSTER_NAME="${DEMO_CLUSTER_NAME:-kind}"

    # Delete existing cluster, i.e. restart cluster
    if [[ $(kind get clusters) == *"$DEMO_CLUSTER_NAME"* ]]; then
      kind delete cluster --name "$DEMO_CLUSTER_NAME"
    fi

    # Setup local Kubernetes cluster using kind (Kubernetes IN Docker) with control plane and worker nodes
    kind create cluster --name "$DEMO_CLUSTER_NAME" --wait 60s

    # Configure environment for kubectl to connect to kind cluster
    export KUBECONFIG="$(kind get kubeconfig-path --name=$DEMO_CLUSTER_NAME)"
    ;;

  minikube)
    DEMO_CLUSTER_NAME="${DEMO_CLUSTER_NAME:-minikube}"

    minikube delete --profile "$DEMO_CLUSTER_NAME" && true # Ignore errors
    minikube start --profile "$DEMO_CLUSTER_NAME"

    source <(minikube docker-env -p "$DEMO_CLUSTER_NAME")
    ;;

  gcloud)
    DEMO_CLUSTER_NAME="${DEMO_CLUSTER_NAME:-gke-gloo}"

    gcloud container clusters delete "$DEMO_CLUSTER_NAME" && true # Ignore errors
    gcloud container clusters create "$DEMO_CLUSTER_NAME"

    gcloud container clusters get-credentials "$DEMO_CLUSTER_NAME"

    kubectl create clusterrolebinding cluster-admin-binding \
      --clusterrole cluster-admin \
      --user $(gcloud config get-value account)
    ;;

esac

# Tell skaffold how to connect to local Kubernetes cluster running in non-default profile name
skaffold config set --kube-context $(kubectl config current-context) local-cluster true

TILLER_MODE="${TILLER_MODE:-local}" # local or cluster

case "$TILLER_MODE" in
  local)
    # Run Tiller locally (external) to Kubernetes cluster as it's faster
    TILLER_PID_FILE=/tmp/tiller.pid
    if [[ -f $TILLER_PID_FILE ]]; then
      (cat "$TILLER_PID_FILE" | xargs kill) && true # Ignore errors killing old Tiller process
      rm "$TILLER_PID_FILE"
    fi
    TILLER_PORT=":44134"
    ((tiller --storage=secret --listen=$TILLER_PORT) & echo $! > "$TILLER_PID_FILE" &)
    export HELM_HOST=$TILLER_PORT
    ;;

  cluster)
    unset HELM_HOST
    # Install Helm and Tiller
    kubectl --namespace kube-system create serviceaccount tiller

    kubectl create clusterrolebinding tiller-cluster-rule \
      --clusterrole=cluster-admin \
      --serviceaccount=kube-system:tiller

    helm init --service-account tiller

    # Wait for tiller to be fully running
    kubectl --namespace kube-system rollout status deployment/tiller-deploy --watch=true
    ;;
esac

GLOO_MODE="${GLOO_MODE:-oss}" # oss or ent

case "$GLOO_MODE" in
  ent)
    if [[ -f ~/scripts/secret/glooe_license_key.sh ]]; then
      # export GLOOE_LICENSE_KEY=<valid key>
      source ~/scripts/secret/glooe_license_key.sh
    fi
    if [[ -z $GLOOE_LICENSE_KEY ]]; then
      echo "You must set GLOOE_LICENSE_KEY with GlooE activation key"
      exit
    fi

    helm repo add glooe http://storage.googleapis.com/gloo-ee-helm
    helm upgrade --install glooe glooe/gloo-ee \
      --namespace gloo-system \
      --version "${GLOO_VERSION:-0.17.0}" \
      --set-string license_key=$GLOOE_LICENSE_KEY
    ;;

  oss)
    helm repo add gloo https://storage.googleapis.com/solo-public-helm
    helm upgrade --install gloo gloo/gloo \
      --namespace gloo-system \
      --version "${GLOO_VERSION:-0.17.0}"
    ;;
esac

#
# Deploy example application
#

# Deploy echo-server service
( cd echo-server; skaffold run )

# Wait for deployment to be deployed and running
kubectl --namespace default rollout status deployment/echo-server --watch=true

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

# Wait for deployment to be deployed and running
kubectl --namespace gloo-system rollout status deployment/gateway-proxy --watch=true

# Wait for Virtual Service changes to get applied to proxy
until [[ "$(kubectl --namespace gloo-system get virtualservice default -o=jsonpath='{.status.state}')" = "1" ]]; do
  sleep 5
done

# Port-forward HTTP port vs use `glooctl proxy url` as port-forward is more resistent to IP changes and works with kind
( kubectl --namespace gloo-system port-forward deployment/gateway-proxy 8080:8080 >/dev/null )&

sleep 15

PROXY_URL="http://localhost:8080"

# curl --silent --show-error ${PROXY_URL:-http://localhost:8080}/ | jq
http --json ${PROXY_URL:-http://localhost:8080}/

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
