# SingleStoreDB Dev Image <!-- omit in toc -->
[![Github Actions status image](https://github.com/singlestore-labs/singlestoredb-dev-image/actions/workflows/build.yml/badge.svg)](https://github.com/singlestore-labs/singlestoredb-dev-image/actions)

The SingleStoreDB Dev Image is the fastest way to develop with [SingleStore][singlestore] on your laptop or in a CI/CD environment. This Docker image is **not supported for production workloads or benchmarks** so please keep that in mind when using it.

If you have any questions or issues, please file an issue on the [GitHub repo][gh-issues] or our [forums].

- [How to run the Docker image?](#how-to-run-the-docker-image)
- [How to open a SQL shell?](#how-to-open-a-sql-shell)
- [How to access the SingleStore Studio UI?](#how-to-access-the-singlestore-studio-ui)
- [How to access the Data API?](#how-to-access-the-data-api)
- [Where to go from here?](#where-to-go-from-here)
- [How to pick an image tag (or SingleStoreDB version)?](#how-to-pick-an-image-tag-or-singlestoredb-version)
- [How to use Docker volumes for persistent storage?](#how-to-use-docker-volumes-for-persistent-storage)
- [How to initialize this container with a SQL file?](#how-to-initialize-this-container-with-a-sql-file)
- [How do use this container in a CI/CD environment?](#how-do-use-this-container-in-a-cicd-environment)
  - [Github Actions](#github-actions)
- [How to upgrade from `singlestore/cluster-in-a-box`?](#how-to-upgrade-from-singlestorecluster-in-a-box)

## How to run the Docker image?

[Sign up][try-free] for a free SingleStore license. This allows you to run up to 4 nodes up to 32 gigs each for free. Grab your license key from [SingleStore portal][portal] to use in the docker run command below.

We recommend using an explicit image version tag whenever possible. You can find a [list of image tags here][versions] and inspect [the changelog here][changelog].

```bash
docker run \
    -d --name singlestoredb-dev \
    -e SINGLESTORE_LICENSE="YOUR SINGLESTORE LICENSE" \
    -e ROOT_PASSWORD="YOUR ROOT PASSWORD" \
    --platform linux/amd64 \
    -p 3306:3306 -p 8080:8080 -p 9000:9000 \
    ghcr.io/singlestore-labs/singlestoredb-dev:latest
```

> **Note**
> The `--platform` flag is only needed to enable support with the new Mac M1 or M2 chipset (Apple Silicon). You can safely remove or ignore that flag on amd64 compatible hardware.

## How to open a SQL shell?

The image includes a shell which you can run interactively using `docker exec` like so:

```bash
docker exec -it singlestoredb-dev singlestore -p
```

The above command will prompt you for the root password. You can also provide the root password at the command line immediately after the `-p` flag like so:

```bash
docker exec -it singlestoredb-dev singlestore -pYOUR_ROOT_PASSWORD
```

You can also connect to SingleStore using any MySQL compatible client on your own machine using the following connection details:

| Key      | Value              |
| -------- | ------------------ |
| Host     | 127.0.0.1          |
| Port     | 3306               |
| Username | root               |
| Password | YOUR_ROOT_PASSWORD |

## How to access the SingleStore Studio UI?

SingleStore Studio is a convenient way to manage SingleStoreDB and run queries via a browser based UI. Studio runs by default on port 8080 in the container. Assuming you have forwarded port 8080 to your local machine, you can access studio at http://localhost:8080.

When opening Studio you will see a login screen. Use the username `root` and the `ROOT_PASSWORD` you set when starting the container.

## How to access the Data API?

In addition to supporting the MySQL Protocol, SingleStore also has a JSON over HTTP protocol called the [Data API][data-api] which you can access at port 9000 in the container. Assuming you have forwarded port 9000 to your local machine, the following curl command demonstrates how you can use the Data API:

```bash
~ ➜ curl -s -XPOST -H "content-type: application/json" -d '{ "sql": "select 1" }' root:YOUR_ROOT_PASSWORD@localhost:9000/api/v1/query/rows
{
  "results": [
    {
      "rows": [
        {
          "1": 1
        }
      ]
    }
  ]
}
```

> **Note**
> For more information on how to use the Data API please [visit the documentation.][data-api]

## Where to go from here?

Now that you have SingleStore running, please check out the following sections of our official documentation for guides on what to do next.

 * [Connect to SingleStore](https://docs.singlestore.com/db/latest/en/connect-to-your-cluster.html)
 * [Developer Resources](https://docs.singlestore.com/db/latest/en/developer-resources.html)
 * [Integrations](https://docs.singlestore.com/db/latest/en/integrate-with-singlestoredb.html)
 * [Load Data](https://docs.singlestore.com/db/latest/en/load-data.html)

## How to pick an image tag (or SingleStoreDB version)?

The SingleStoreDB Dev Image uses Docker Image tags to track different versions of the product. Currently there are two groups of tags related to the Cloud and On-Premises versions of the product. You can see a listing of recent versions on the [Github package page][versions].

To run a particular version of SingleStoreDB, look up the version in the [changelog] to find the corresponding Docker Image tag to use. If the version is only released in SingleStoreDB Cloud, then you will need to append the suffix `-cloud`. Otherwise you should use the suffix `-onprem`.

**For example**, if you wanted to use SingleStoreDB 7.8.13, you would use the image `ghcr.io/singlestore-labs/singlestoredb-dev:0.0.6-onprem`

> **Note**
> The latest tag points to the latest Cloud version as it is released more frequently than our On-Premises version. There are also standalone `cloud` and `onprem` tags which you can use to always run the latest version following their respective products.

## How to use Docker volumes for persistent storage?

You can use a Docker volume to setup persistent storage by mounting the volume to `/data` in the container. You can do this by simply adding `-v VOLUME_NAME:/data` or `-v /data` to the Docker run command. Make sure to replace `VOLUME_NAME` with a name for the volume.

```bash
docker run \
    -d --name singlestoredb-dev \
    -e SINGLESTORE_LICENSE="YOUR SINGLESTORE LICENSE" \
    -e ROOT_PASSWORD="YOUR ROOT PASSWORD" \
    -p 3306:3306 -p 8080:8080 -p 9000:9000 \
    -v my_cool_volume:/data \
    ghcr.io/singlestore-labs/singlestoredb-dev
```

After creating the container with a volume, you can re-create the container using the same volume to keep your data around. This can be used to upgrade SingleStore to new versions without loosing your data. Keep in mind that SingleStoreDB does **not** support downgrading. Make sure to take a backup of the volume before running the upgrade.

You can also persist log files by mounting a volume to `/logs`.

> **Note**
> In order to use a host volume with this image, you will need to chown the volume to UID=999 and GID=998 before mounting it to `/data` or `/logs`. The volume will be initialized automatically if empty.

## How to initialize this container with a SQL file?

When this docker image starts for the first time it will check to see if `/init.sql` exists in its filesystem. If `/init.sql` is found, the container will run it against the database as soon as SingleStoreDB is ready.

One way to do this is mounting a `init.sql` from your machine into the container using the `-v` flag. Here is an example of doing this:

```bash
docker run \
    -d --name singlestoredb-dev \
    -e SINGLESTORE_LICENSE="YOUR SINGLESTORE LICENSE" \
    -e ROOT_PASSWORD="YOUR ROOT PASSWORD" \
    -p 3306:3306 -p 8080:8080 -p 9000:9000 \
    -v ${PWD}/test/init.sql:/init.sql \
    ghcr.io/singlestore-labs/singlestoredb-dev
```

Replace `${PWD}/test/init.sql` with an absolute path to the SQL file you want to initialize SingleStore with.

> **Note**
> `/init.sql` will only be run once. If you want to run it again you will need to delete the file `/data/.init.sql.done` and then restart the container.

## How do use this container in a CI/CD environment?

This Docker image defines a healthcheck which runs every 5 seconds. Any CI/CD system or container runtime which respects the healthcheck should automatically wait for SingleStore to be running and healthy.

### Github Actions

Here is an example workflow which runs SingleStore as a container service and queries it from the job.

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

## How to upgrade from `singlestore/cluster-in-a-box`?

Before this image existed, there was another Docker Image called `singlestore/cluster-in-a-box`. The docker run command for the previous image looked something like this:

```bash
docker run -i --init \
    --name singlestore-ciab \
    -e LICENSE_KEY=${LICENSE_KEY} \
    -e ROOT_PASSWORD=${ROOT_PASSWORD} \
    -p 3306:3306 -p 8080:8080 \
    singlestore/cluster-in-a-box
```

The differences between the old image and the new image are the following:

 * The image no longer needs to be initialized before you can use it
 * Startup time is much better - roughly 5 seconds with the new image versus a minute with the old image
 * The [Data API][data-api] and External Functions features are enabled by default
 * Upgrade between versions is supported and tested (downgrade is not supported)
 * The new image is distributed through the Github Container Repository rather than the Docker Hub

In all cases we recommend using the new image unless you need to run a older version of SingleStore which has not been released in `singlestoredb-dev-image`.

[versions]: https://github.com/singlestore-labs/singlestoredb-dev-image/pkgs/container/singlestoredb-dev/versions
[changelog]: CHANGELOG.md
[try-free]: https://www.singlestore.com/try-free/
[singlestore]: https://www.singlestore.com
[gh-issues]: https://github.com/singlestore-labs/demo-realtime-digital-marketing/issues
[forums]: https://www.singlestore.com/forum/
[portal]: https://portal.singlestore.com/
[data-api]: https://docs.singlestore.com/managed-service/en/reference/data-api.html
