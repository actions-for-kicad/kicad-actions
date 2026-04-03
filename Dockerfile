FROM kicad/kicad:9.0.3

USER root

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
