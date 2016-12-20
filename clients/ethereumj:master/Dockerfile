# Docker container spec for building the develop branch of ethereumJ.
#
# The build process it potentially longer running but every effort was made to
# produce a very minimalistic container that can be reused many times without
# needing to constantly rebuild.
FROM frolvlad/alpine-oraclejdk8:slim

# Build Harmony on the fly and delete all build tools afterwards
RUN \
  apk add --update git                                                && \
  git clone --depth 1 -b hive https://github.com/ether-camp/ethereum-harmony.git && \
  (cd ethereum-harmony && ./gradlew build -x test)


# Make sure bash and jq is available for easier wrapper implementation
RUN apk add --update bash jq

# Inject the startup script
ADD harmony.sh /harmony.sh
RUN chmod +x /harmony.sh

# Export the usual networking ports to allow outside access to the node
EXPOSE 8545 8546 30303

ENTRYPOINT ["/harmony.sh"]

#EOF
