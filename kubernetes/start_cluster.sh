#!/usr/bin/env bash

# Expects
# brew install kubernetes-cli kubernetes-helm skaffold httpie

# Optional
# brew install go jq; brew cask install minikube

# Based on GlooE Custom Auth server example
# https://gloo.solo.io/enterprise/authentication/custom_auth/

K8S_TOOL=minikube   # kind or minikube
TILLER_MODE=local   # local or cluster
GLOO_MODE=ent       # oss or ent

if [[ GLOO_MODE == oss ]]; then
  GLOO_VERSION=0.18.2 # oss
else
  GLOO_VERSION=0.17.3 # ent
fi

# GLOOE_LICENSE_KEY=

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

K8S_TOOL="${K8S_TOOL:-minikube}" # kind or minikube

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

    # brew install hyperkit
    # minikube config set vm-driver hyperkit
    # minikube config set cpus 4
    # minikube config set memory 4096

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
      --version "${GLOO_VERSION:-0.17.3}" \
      --set-string license_key=$GLOOE_LICENSE_KEY
    ;;

  oss)
    helm repo add gloo https://storage.googleapis.com/solo-public-helm
    helm upgrade --install gloo gloo/gloo \
      --namespace gloo-system \
      --version "${GLOO_VERSION:-0.18.2}"
    ;;

esac

#
# Deploy example application
#

# Deploy echo-server service
kubectl --namespace default apply --filename - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: echo-server
  namespace: default
  labels:
    app: echo-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: echo-server
  template:
    metadata:
      labels:
        app: echo-server
    spec:
      containers:
      - name: echo-server
        image: quay.io/sololabs/echo-server:v1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: echo-server
  labels:
    app: echo-server
spec:
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: echo-server
EOF

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
if [[ $GLOO_VERSION < 0.18.0 ]]; then
  kubectl --namespace gloo-system rollout status deployment/gateway-proxy --watch=true
else
  kubectl --namespace gloo-system rollout status deployment/gateway-proxy-v2 --watch=true
fi

# Wait for Virtual Service changes to get applied to proxy
until [[ "$(kubectl --namespace gloo-system get virtualservice default -o=jsonpath='{.status.state}')" = "1" ]]; do
  sleep 5
done

# Port-forward HTTP port vs use `glooctl proxy url` as port-forward is more resistent to IP changes and works with kind
if [[ $GLOO_VERSION < 0.18.0 ]]; then
  ( kubectl --namespace gloo-system port-forward deployment/gateway-proxy 8080:8080 >/dev/null )&
else
  ( kubectl --namespace gloo-system port-forward deployment/gateway-proxy-v2 8080:8080 >/dev/null )&
fi

sleep 20

PROXY_URL="http://localhost:8080"

# curl --silent --show-error ${PROXY_URL:-http://localhost:8080}/ | jq
http --json ${PROXY_URL:-http://localhost:8080}/
