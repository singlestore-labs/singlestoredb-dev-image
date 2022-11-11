# Changelog

## 0.1.4 - 2022-11-10
 - Extension script support

## 0.1.3 - 2022-10-17
 - SingleStoreDB Version 7.9.12

## 0.1.2 - 2022-10-06
 - Allow SingleStoreDB global variables to be set via environment variables
 - SingleStore Studio version 4.0.8
 - Improved test failure output

## 0.1.1 - 2022-10-05
 - SingleStoreDB Version 7.9.11

## 0.1.0 - 2022-09-30

 - SingleStoreDB Version 7.9.10
 - SingleStoreDB Toolbox Version 1.13.13
 - Bugfix: ensure that we set license as early as possible to support running on larger machines

## 0.0.8 - 2022-09-08

 - Removed the -cloud and -onprem tags, replacing it with a method to support switching the SingleStoreDB version at runtime or by building a custom image.
 - Added toolbox (v1.13.10) to the image to support the dynamic version switching behavior
 - Updated readme with more details on mount points, version selection, and Apple Silicon behavior
 - Fixed bug which could allow the healthcheck to succeed too early during a container restart

## 0.0.7 - 2022-09-01

 - Moved Studio later in the startup process so it can be used as a backup healthcheck

## 0.0.6 - 2022-08-29

 - Split the image into two tags, one tracking SingleStoreDB On-Premises (`onprem`) and the other tracking SingleStoreDB Cloud (`cloud`). The changelog will track the version numbers for each image tag going forward.
 - SingleStoreDB Cloud Version = 7.9.8-325fd05545
 - SingleStoreDB On-Premises Version = 7.8.13-f8fec5f0db

## 0.0.5 - 2022-08-26

 - Support upgrading using a persistent volume

## 0.0.4 - 2022-08-25

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

## 0.0.3 - 2022-08-24

 - Tweaks to the readme
 - Dependabot configuration
 - Made image labels more consistent

## 0.0.2 - 2022-08-23

 - Changed how the github actions work to minimize Github container repository pollution
 - No changes to internal versions

## 0.0.1 - 2022-08-23

 - SingleStoreDB version 7.9.8 (beta release)
 - Client version 1.0.7
 - Studio version 4.0.7
