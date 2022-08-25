FROM almalinux:8.6-20220706

RUN yum makecache --refresh && \
    yum install -y yum-utils wget procps && \
    yum update -y curl && \
    yum-config-manager --save --setopt=skip_missing_names_on_install=0 && \
    yum -y update-minimal --setopt=tsflags=nodocs --security --sec-severity=Important --sec-severity=Critical && \
    dnf --enablerepo=* clean all && \
    dnf update -y && \
    yum remove -y vim-minimal platform-python-pip.noarch && \
    yum update -y expat libxml2 libgcrypt && \
    yum clean all

ENV JQ_VERSION='1.6'
RUN wget --no-check-certificate https://raw.githubusercontent.com/stedolan/jq/master/sig/jq-release.key -O /tmp/jq-release.key && \
    wget --no-check-certificate https://raw.githubusercontent.com/stedolan/jq/master/sig/v${JQ_VERSION}/jq-linux64.asc -O /tmp/jq-linux64.asc && \
    wget --no-check-certificate https://github.com/stedolan/jq/releases/download/jq-${JQ_VERSION}/jq-linux64 -O /tmp/jq-linux64 && \
    gpg --import /tmp/jq-release.key && \
    gpg --verify /tmp/jq-linux64.asc /tmp/jq-linux64 && \
    cp /tmp/jq-linux64 /usr/bin/jq && \
    chmod +x /usr/bin/jq && \
    rm -f /tmp/jq-release.key && \
    rm -f /tmp/jq-linux64.asc && \
    rm -f /tmp/jq-linux64

ARG BOOTSTRAP_LICENSE
ARG RELEASE_CHANNEL
ARG CLIENT_VERSION
ARG SERVER_VERSION
ARG STUDIO_VERSION

RUN yum-config-manager --add-repo https://release.memsql.com/${RELEASE_CHANNEL}/rpm/x86_64/repodata/memsql.repo && \
    yum install -y \
    singlestore-client-${CLIENT_VERSION} \
    singlestoredb-server${SERVER_VERSION} \
    singlestoredb-studio-${STUDIO_VERSION} && \
    yum clean all

ADD scripts/setup-singlestore-user.sh /scripts/setup-singlestore-user.sh
RUN /scripts/setup-singlestore-user.sh

RUN mkdir -p /data && chown -R singlestore:singlestore /data
RUN mkdir -p /logs && chown -R singlestore:singlestore /logs
RUN mkdir -p /startup && chown -R singlestore:singlestore /startup

# remove /var/lib/memsql, this image uses /data and /logs to store everything
# we also need to be able to detect when we are upgrading from the old cluster in a box image
RUN rm -rf /var/lib/memsql

ADD assets/memsqlctl.hcl /etc/memsql/memsqlctl.hcl
RUN chown singlestore:singlestore /etc/memsql/memsqlctl.hcl

RUN touch /data/nodes.hcl && chown singlestore:singlestore /data/nodes.hcl

ADD assets/studio.hcl /var/lib/singlestoredb-studio/studio.hcl
RUN chown -R singlestore:singlestore /var/lib/singlestoredb-studio

USER singlestore

ADD scripts/init.sh /scripts/init.sh
RUN /scripts/init.sh

ADD scripts/start.sh /scripts/start.sh
CMD ["/scripts/start.sh"]

ADD licenses /licenses

ADD scripts/healthcheck.sh /scripts/healthcheck.sh
HEALTHCHECK --interval=7s --timeout=30s --start-period=5s --retries=3 CMD /scripts/healthcheck.sh

EXPOSE 3306/tcp
EXPOSE 8080/tcp
EXPOSE 9000/tcp