FROM kicad/kicad:9.0

USER root

COPY entrypoint.sh /entrypoint.sh

# ENTRYPOINT ["/entrypoint.sh"]
ENTRYPOINT ["python", "--version"]
