
ARG KAI_VERSION # Since KAI_VERSION is used for a FROM later; must be declared before first FROM (of any image)
FROM gcr.io/singlestore-public/internal-mongoproxy:v$KAI_VERSION AS kai
FROM almalinux:8.6-20220901 AS base

ARG SECURITY_UPDATES_AS_OF=2022-09-30

RUN rpm --import https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux

RUN dnf upgrade -y almalinux-release && \
    yum -y clean all

RUN yum makecache --refresh && \
    yum install -y yum-utils wget procps java-11-openjdk && \
    yum update -y curl && \
    yum-config-manager --save --setopt=skip_missing_names_on_install=0 && \
    yum -y update-minimal --setopt=tsflags=nodocs --nobest --security --sec-severity=Important --sec-severity=Critical && \
    dnf --enablerepo=* clean all && \
    dnf update -y && \
    yum remove -y vim-minimal platform-python-pip.noarch && \
    yum update -y expat libxml2 libgcrypt && \
    yum clean all

RUN cd /tmp && \
    wget https://download.java.net/openjdk/jdk21/ri/openjdk-21+35_linux-x64_bin.tar.gz && \
    tar xzvf openjdk-21+35_linux-x64_bin.tar.gz && \
    mv jdk-21 /usr/local/ && \
    rm -f openjdk-21+35_linux-x64_bin.tar.gz && \
    cd ..

ENV JQ_VERSION='1.6'
RUN wget --no-check-certificate https://raw.githubusercontent.com/jqlang/jq/master/sig/jq-release-old.key -O /tmp/jq-release.key && \
    wget --no-check-certificate https://raw.githubusercontent.com/jqlang/jq/master/sig/v${JQ_VERSION}/jq-linux64.asc -O /tmp/jq-linux64.asc && \
    wget --no-check-certificate https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux64 -O /tmp/jq-linux64 && \
    gpg --import /tmp/jq-release.key && \
    gpg --verify /tmp/jq-linux64.asc /tmp/jq-linux64 && \
    cp /tmp/jq-linux64 /usr/bin/jq && \
    chmod +x /usr/bin/jq && \
    rm -f /tmp/jq-release.key && \
    rm -f /tmp/jq-linux64.asc && \
    rm -f /tmp/jq-linux64

ARG BOOTSTRAP_LICENSE
ARG CONFIG

RUN yum-config-manager --add-repo https://repo.mongodb.org/yum/redhat/9/mongodb-org/8.0/x86_64/ && \
    yum-config-manager --save --setopt=repo.mongodb.org_yum_redhat_9_mongodb-org_8.0_x86_64_.gpgkey=https://www.mongodb.org/static/pgp/server-8.0.asc && \
    yum install -y mongodb-mongosh && \
    yum -y clean all

ADD scripts/mongosh /usr/local/bin/mongosh
ADD scripts/mongosh-auth /usr/local/bin/mongosh-auth
ADD scripts/singlestore-auth /usr/local/bin/singlestore-auth

RUN yum-config-manager --add-repo https://release.memsql.com/$(echo "${CONFIG}" | jq -r .channel)/rpm/x86_64/repodata/memsql.repo && \
    yum install -y \
    singlestore-client-$(echo "${CONFIG}" | jq -r .client) \
    singlestoredb-toolbox-$(echo "${CONFIG}" | jq -r .toolbox) \
    singlestoredb-studio-$(echo "${CONFIG}" | jq -r .studio) && \
    yum clean all

ADD scripts/setup-singlestore-user.sh /scripts/setup-singlestore-user.sh
RUN /scripts/setup-singlestore-user.sh

RUN mkdir -p /server && chown -R singlestore:singlestore /server
RUN mkdir -p /data && chown -R singlestore:singlestore /data
RUN mkdir -p /logs && chown -R singlestore:singlestore /logs
RUN mkdir -p /kai && chown -R singlestore:singlestore /kai

# remove /var/lib/memsql, this image uses /data and /logs to store everything
# we also need to be able to detect when we are upgrading from the old cluster in a box image
RUN rm -rf /var/lib/memsql

ADD assets/memsqlctl.hcl /etc/memsql/memsqlctl.hcl
RUN chown singlestore:singlestore /etc/memsql/memsqlctl.hcl

RUN touch /data/nodes.hcl && chown singlestore:singlestore /data/nodes.hcl

ADD assets/studio.hcl /var/lib/singlestoredb-studio/studio.hcl
RUN chown -R singlestore:singlestore /var/lib/singlestoredb-studio

USER singlestore

RUN sdb-toolbox-config -y register-host \
    --localhost \
    --cluster-hostname 127.0.0.1 \
    --skip-auto-config \
    --memsqlctl-config-path /etc/memsql/memsqlctl.hcl \
    --tar-install-dir /server

ADD scripts/install.sh /scripts/install.sh
RUN /scripts/install.sh "$(echo "${CONFIG}" | jq -r .engine_channel):$(echo "${CONFIG}" | jq -r .server)"

ADD scripts/memsqlctl /bin/memsqlctl
ADD scripts/init.sh /scripts/init.sh
RUN /scripts/init.sh "${BOOTSTRAP_LICENSE}"

ADD scripts/switch-version.sh /scripts/switch-version.sh

ADD scripts/start.sh /scripts/start.sh
CMD ["/scripts/start.sh"]

ADD licenses /licenses

ADD scripts/healthcheck.sh /scripts/healthcheck.sh
HEALTHCHECK --interval=5s --timeout=5s --start-period=90s --retries=3 CMD /scripts/healthcheck.sh

COPY --from=kai / /kai

EXPOSE 3306/tcp
EXPOSE 8080/tcp
EXPOSE 9000/tcp
EXPOSE 27017/tcp
