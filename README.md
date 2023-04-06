

assuming your docker-machine name is `default` and you want to upgrade to `Docker version 23.0.3, build 3e7cbfd`


```bash
sh build.sh
```


or grab the pre-built 23.0.3 iso here: https://github.com/troyxmccall/boot2docker/releases/download/v23.0.3/boot2docker.iso



I typically run something like:

```bash
docker-machine create --driver=parallels --parallels-disk-size 40000 --parallels-cpu-count -1 --parallels-memory 16384 --parallels-boot2docker-url https://github.com/troyxmccall/boot2docker/releases/download/v23.0.3/boot2docker.iso default
```
