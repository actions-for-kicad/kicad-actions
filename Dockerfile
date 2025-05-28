FROM kicad/kicad:9.0
FROM python:3-slim

USER root

COPY entrypoint.sh /entrypoint.sh

RUN pip install PyYaml

# ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "--version"]
