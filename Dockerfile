FROM kicad/kicad:10.0-full

USER root

COPY entrypoint.sh /entrypoint.sh
COPY glb/ /glb/

ENTRYPOINT ["/entrypoint.sh"]
