FROM kicad/kicad:9.0
FROM python:3-slim

USER root

COPY src /src
COPY main.py /main.py

RUN pip install PyYaml

CMD ["python", "main.py"]
