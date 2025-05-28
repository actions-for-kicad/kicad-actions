FROM kicad/kicad:9.0
FROM python:3.13-slim

USER root

COPY entrypoint.sh /entrypoint.sh

# ENTRYPOINT ["/entrypoint.sh"]
ENTRYPOINT ["python", "--version"]
