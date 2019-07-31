# Solo.io Gloo and Kubernetes

## Pre-requisites

* Gloo command line tool
  * [Gloo install docs](https://gloo.solo.io/installation/gateway/kubernetes/#install-command-line-tool-cli)
  * macOS: `brew install solo-io/tap/glooctl`
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

To run demos, execute the following commands.

```shell
./start_cluster.sh

./run_gloo_auth_demo.sh

./run_gloo_adv_rate_limit.sh
```

## Exercises

1. Virtual Service Routing
   * create route from `/echo` to echo-server
   * create route from `/petstore` to petstore
   * create route from `/` with header `x-my-type` to
     * `x-my-type:pet` to petstore
     * `x-my-type:echo` to echo-server
1. Authentication Server
   * all requests`/echo` allowed
   * requests to  `/petstore` with header `x-my-user` allowed; others denied
   * requests to `/` with header `x-my-user` allowed
   * appropriate body error message for declined requests, e.g., `not authorized path`, `missing header`, etc.
   * add header to approved requests `x-authorized` with value `true` for authenticated requests, i.e. request includes
     `x-my-user` header; `false` for other approved requests
1. Rate Limiting
   * Allow 1 request per minute for all requests to `/echo`
   * Allow 2 requests per minute for all requests to `/petstore`
   * Allow 2 requests per minute to all authorized users, ie. have header `x-authorized:true`
   * **Bonus**: rate limit per unique authorized user
1. Routing to external servers
   * Reference [External Routing docs](https://gloo.solo.io/user_guides/gateway/external_services/static_upstream/) to
     create a route to a different external service of your choosing
   * **Bonus**: add in authentication and rate limiting for new external service routes
