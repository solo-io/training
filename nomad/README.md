# Solo.io Gloo and Hashicorp Nomad

Pre-requisites

* Vagrant and Virtual Box

```shell
vagrant up && vagrant ssh
[vagrant@nomad:~$] cd /vagrant
[vagrant@nomad:/vagrant$] ./run_nomad_demo.sh
```

To expose Gloo admin ui from vagrant after installing gloo on nomad, run the follow to effectively bridge from `docker0`
network interface to host <http://localhost:19000>

```shell
socat tcp:localhost:19000,fork TCP:172.17.0.1:29000 &
```
