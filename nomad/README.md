# Solo.io Gloo and Hashicorp Nomad

Pre-requisites

* Vagrant
* Virtual Box

```shell
vagrant up && vagrant ssh
[vagrant@nomad:~$] cd /vagrant && ./run_nomad_demo.sh
```

Ports

* Nomad UI - <http://localhost:4646>
* Fabio UI - <http://localhost:9998/>
* Prometheus LB - <http://localhost:9999>
* Gloo admin UI - <http://localhost:19000/>
* Consul UI - <http://localhost:8500>
* Vault UI - <http://localhost:8200> token:root
