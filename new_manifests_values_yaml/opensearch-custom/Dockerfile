FROM opensearchproject/opensearch:3.4.0

USER 0

# OpenShift-friendly permissions for non-root execution (uid/gid 1000).
RUN chown -R 1000:1000 /usr/share/opensearch \
    && chmod -R g+rwX /usr/share/opensearch \
    && chmod +x /usr/share/opensearch/opensearch-docker-entrypoint.sh

USER 1000
