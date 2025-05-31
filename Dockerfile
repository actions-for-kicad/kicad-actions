# FROM python:3-slim
FROM kicad/kicad:9.0

USER root

COPY run.py /run.py

RUN apt install python3 pip3
RUN pip install PyYaml

CMD ["kicad-cli"]

# CMD ["python", "run.py"]
