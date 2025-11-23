

assuming your docker-machine name is `default` and you want to upgrade to `Docker version 24.0.7, build afdd53b`


```bash
sh build.sh
```


or grab the pre-built v24.0.7 iso here: https://github.com/troyxmccall/boot2docker/releases/download/v24.0.7/boot2docker.iso

----

on macOS I typically run something like:

```bash
docker-machine create --driver=parallels --parallels-disk-size 40000 --parallels-cpu-count -1 --parallels-memory 16384 --parallels-boot2docker-url https://github.com/troyxmccall/boot2docker/releases/download/v24.0.7/boot2docker.iso default
```

----

### updating deps (in the Dockerfile)

```bash
docker run -it --rm -v "$(pwd)":/workdir debian:bullseye bash -c "apt-get update && apt-get install -y wget jq git && cd /workdir && bash update.sh"
```
