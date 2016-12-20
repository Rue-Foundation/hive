# Docker container spec for building the master branch of ethereumJ.
#
# The build process it potentially longer running but every effort was made to
# produce a very minimalistic container that can be reused many times without
# needing to constantly rebuild.
FROM n3ziniuka5/ubuntu-oracle-jdk:16.04-JDK8
#FROM frolvlad/alpine-oraclejdk8:slim         # alpine has issues running leveldb native

# Make sure bash and jq is available for easier wrapper implementation
RUN apt-get install bash

# Inject the startup script
ADD harmony.sh /harmony.sh
RUN chmod +x /harmony.sh

# Export the usual networking ports to allow outside access to the node
EXPOSE 8545 8546 30303

ENTRYPOINT ["/harmony.sh"]

#EOF
