# Solo.io Gloo and Kubernetes

## Pre-requisites

* Kubernetes cluster
  * [Minikube](https://github.com/kubernetes/minikube)
    * macOS: `brew install kubernetes-cli; brew cash minikube`
    * Minikube requires a virtualization driver that also must be installed; defaults to [Virtual Box](https://www.virtualbox.org/wiki/Downloads)
  * OR
  * [Kind](https://kind.sigs.k8s.io/) Kubernets IN Docker
    * `GO111MODULE="on" go get sigs.k8s.io/kind@v0.4.0`
    * `export KUBECONFIG="$(kind get kubeconfig-path)"`

* [Helm](https://github.com/helm/helm) Kubernetes Package Manager
  * macOS: `brew install kubernetes-helm`
* [Skaffold](https://github.com/GoogleContainerTools/skaffold) Kubernetes Build tool
  * macOS: `brew install skaffold`
  * Command Summary
    * `skaffold build` - compiles code and builds docker image
    * `skaffold run` - builds image and deploys to k8s cluster
    * `skaffold dev` - builds and deploys to k8s cluster, rebuids/deploys on change, and streams logs to console
* OPTIONAL: [HTTPie](https://httpie.org/) http curl-like tool
  * macOS: `brew install httpie`

To use Gloo Enterprise, set an environment variable for Gloo key
`export GLOOE_LICENSE_KEY=<valid Gloo Enterprise key>`

## Labs

To run demo, execute the following commands.

```shell
./start_cluster.sh

./run_gloo_auth_demo.sh
```
