# Solo.io Gloo and Hashicorp Nomad

```shell
DOCKER_IP=$(/sbin/ifconfig docker0 | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')

curl $DOCKER_IP:28080/petstore
```
