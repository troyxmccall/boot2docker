

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

To update Docker within the major version configured in `update.sh`, without
waiting for the kernel or guest-tools download servers:

```bash
docker run -it --rm -v "$(pwd)":/workdir debian:trixie bash -c "apt-get update && apt-get install -y ca-certificates wget jq git && cd /workdir && bash update.sh --docker-only"
```

To update all dependencies:

```bash
docker run -it --rm -v "$(pwd)":/workdir debian:trixie bash -c "apt-get update && apt-get install -y ca-certificates wget jq git && cd /workdir && bash update.sh"
```

The updater writes the Dockerfile only after every requested lookup succeeds.
VirtualBox metadata and Guest Additions downloads fall back to Oracle's download
server if `download.virtualbox.org` is unavailable.
Download errors are printed with the failing command. Updating the Dockerfile
does not change the running VM; `bash build.sh` builds the ISO and restarts
the `default` machine with it.

Linux stays on the 6.1 longterm series for compatibility with the pinned Parallels
Boot2Docker tools (`19.0.0-54570`). The updater leaves this tools version unchanged;
newer Parallels Desktop releases may not publish a Boot2Docker tools archive.
