FROM hive/clients/ethereumj:develop

ADD dag.sh dag.sh
RUN chmod 755 /dag.sh

ENTRYPOINT ["/dag.sh"]