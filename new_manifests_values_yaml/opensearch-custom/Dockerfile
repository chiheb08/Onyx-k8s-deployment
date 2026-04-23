FROM opensearchproject/opensearch:3.4.0

USER 0

# OpenShift-friendly permissions for arbitrary non-root UIDs.
# Do NOT pin USER 1000. Let OpenShift run with a random UID.
RUN chgrp -R 0 /usr/share/opensearch \
    && chmod -R g=u /usr/share/opensearch \
    && chmod 0755 /usr/share/opensearch \
    && chmod 0755 /usr/share/opensearch/opensearch-docker-entrypoint.sh

# Intentionally no USER here: OpenShift will inject a random non-root UID.
