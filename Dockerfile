FROM kicad/kicad:10.0

USER root

COPY entrypoint.sh /entrypoint.sh
COPY glb/ /glb/

ENTRYPOINT ["/entrypoint.sh"]
