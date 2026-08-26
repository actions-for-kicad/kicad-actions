FROM kicad/kicad:10.0

USER root

COPY entrypoint.sh /entrypoint.sh
COPY glb_postprocess.py /glb_postprocess.py

ENTRYPOINT ["/entrypoint.sh"]
