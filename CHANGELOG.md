# Changelog

## [0.0.6] - 2022-08-29

 - Split the image into two tags, one tracking SingleStoreDB On-Premises (`onprem`) and the other tracking SingleStoreDB Cloud (`cloud`). The changelog will track the version numbers for each image tag going forward.

| Tag Suffix | SingleStoreDB Version |
| ---------- | --------------------- |
| `cloud`    | 7.9.8                 |
| `onprem`   | 7.8.13                |

## [0.0.5] - 2022-08-26

 - Support upgrading using a persistent volume

## [0.0.4] - 2022-08-25

 - Added more documentation to the readme
 - Reorganized repo layout to make everything easier to find
 - The healthcheck now verifies the leaf node is also healthy
 - Match the UID and GID from the previous Cluster in a Box image to support upgrade
 - Added more tests
 - Changed image username to `singlestore`
 - `/data` now contains more SingleStore state including the plancache and memsql.cnf files
 - Moved tracelogs and auditlogs to `/logs` to separate them from data
 - Support host volumes as long as the UID/GID is correct
 - Support automatic restart if the master or leaf node crash
 - Fail with a non-zero exit code if either of memsqld_safe or studio crash

## [0.0.3] - 2022-08-24

 - Tweaks to the readme
 - Dependabot configuration
 - Made image labels more consistent

## [0.0.2] - 2022-08-23

 - Changed how the github actions work to minimize Github container repository pollution
 - No changes to internal versions

## [0.0.1] - 2022-08-23

 - SingleStoreDB version 7.9.8 (beta release)
 - Client version 1.0.7
 - Studio version 4.0.7

[0.0.4]: https://github.com/singlestore-labs/singlestoredb-dev-image/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/singlestore-labs/singlestoredb-dev-image/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/singlestore-labs/singlestoredb-dev-image/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/singlestore-labs/singlestoredb-dev-image/releases/tag/v0.0.1