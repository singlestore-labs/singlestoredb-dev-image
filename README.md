# SingleStoreDB Dev Container

The SingleStoreDB Dev Container is the fastest way to develop with SingleStore on your laptop or in a CI/CD environment. This container is **not supported for production workloads or benchmarks** so please keep that in mind when using it.

## How to run the container using Docker

```bash
docker run \
    -d --name singlestore-dev \
    -e SINGLESTORE_LICENSE="YOUR SINGLESTORE LICENSE" \
    -e ROOT_PASSWORD="YOUR ROOT PASSWORD" \
    ghcr.io/singlestore-labs/singlestoredb-dev
```

> **Note**
> **If you are running on a Mac and have the newer Mac M1 or M2 chipset (Apple Silicon)**: You will need to add `--platform linux/amd64` to the `docker run` command to tell Docker to run the container using x86 based virtualization.

## How to use Docker volumes for persistent storage

You can use a Docker volume to setup persistent storage by mounting the volume to `/data` in the container. You can do this by simply adding `-v VOLUME_NAME:/data` or `-v /data` to the Docker run command. Make sure to replace `VOLUME_NAME` with a name for the volume.

> **Warning**
> This does not directly support host mounts, as host mounts start off empty. If you want to use a host mount, you will need to first initialize the mount with the contents of `/data` in the Docker image.

```bash
docker run \
    -d --name singlestore-dev \
    -e SINGLESTORE_LICENSE="YOUR SINGLESTORE LICENSE" \
    -e ROOT_PASSWORD="YOUR ROOT PASSWORD" \
    -v my_cool_volume:/data \
    ghcr.io/singlestore-labs/singlestoredb-dev
```

After creating the container with a volume, you can re-create the container using the same volume to keep your data around. This can be used to upgrade SingleStore to new versions without loosing your data. Keep in mind that SingleStoreDB does **not** support downgrading. Make sure to take a backup of the volume before running the upgrade.

## How to initialize this container with a SQL file?

When this docker image starts for the first time it will check to see if `/init.sql` exists in it's filesystem. If `/init.sql` is found, the container will run it against the database as soon as SingleStoreDB is ready.

One way to do this is mounting a `init.sql` from your machine into the container using the `-v` flag. Here is an example of doing this:

```bash
docker run \
    -d --name singlestore-dev \
    -e SINGLESTORE_LICENSE="YOUR SINGLESTORE LICENSE" \
    -e ROOT_PASSWORD="YOUR ROOT PASSWORD" \
    -v ${PWD}/test_init.sql:/init.sql \
    ghcr.io/singlestore-labs/singlestoredb-dev
```

Replace `${PWD}/test_init.sql` with an absolute path to the SQL file you want to initialize SingleStore with.

> **Note**
> `/init.sql` will only be run once. If you want to run it again you will need to delete the file `/data/.init.sql.done` and then restart the container.


## How do use this container in a CI/CD environment?

This Docker image defines a healthcheck which runs every 5 seconds. Any CI/CD system which respects the healthcheck should automatically wait for SingleStore to be running and healthy. So, all you need to do is define a service in your CI/CD system of choice which uses this Docker image.

### Github Actions

Here is an example workflow which runs SingleStore as a service and queries it from the job.

```yaml
name: my-workflow
on: push

jobs:
  my-job:
    runs-on: ubuntu-latest
    needs: build-image

    services:
      singlestoredb:
        image: ghcr.io/singlestore-labs/singlestoredb-dev
        ports:
          - 3306:3306
          - 8080:8080
          - 9000:9000
        env:
          ROOT_PASSWORD: test
          SINGLESTORE_LICENSE: ${{ secrets.SINGLESTORE_LICENSE }}

    steps:
      - name: sanity check using mysql client
        run: |
          mysql -u root -ptest -e "SELECT 1" -h 127.0.0.1
```