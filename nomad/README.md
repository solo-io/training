# Solo.io Gloo and Hashicorp Nomad

```shell
DOCKER_IP=$(/sbin/ifconfig docker0 | grep 'inet addr' | cut -d: -f2 | awk '{print $1}')

nomad run petstore.nomad

docker ps

export PETSTORE_IP=$(docker inspect $(docker ps | grep petstore | awk '{print $1}') -f '{{printf "%v" (index (index (index .NetworkSettings.Ports "8080/tcp") 0) "HostIp")}}')
export PETSTORE_PORT=$(docker inspect $(docker ps | grep petstore | awk '{print $1}') -f '{{printf "%v" (index (index (index .NetworkSettings.Ports "8080/tcp") 0) "HostPort")}}')
export PETSTORE_URL=http://${PETSTORE_IP}:${PETSTORE_PORT}

printf "PETSTORE_URL (%s) should equal 'http://172.17.0.1:20222'\n", $PETSTORE_URL

# curl $PETSTORE_URL/api/pets
http --json $PETSTORE_URL/api/pets

nomad run gloo.nomad

# curl $DOCKER_IP:28080/petstore
http --json $DOCKER_IP:28080/petstore
```
