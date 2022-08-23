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