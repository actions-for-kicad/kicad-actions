FROM kicad/kicad:9.0
FROM python:3-slim

USER root

COPY run.py /run.py

RUN pip install PyYaml

CMD ["python", "run.py"]
