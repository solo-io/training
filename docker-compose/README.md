# Solo.io Gloo and Docker-Compose

```shell
docker-compose up --detach

curl localhost:8080/petstore
curl localhost:8080/petstore/findPets
curl localhost:8080/petstore/findWithId/1
curl localhost:8080/petstore/findWithId/2

docker-compose down
```
