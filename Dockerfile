FROM kicad/kicad:10.0-full

USER root

# cwebp, for pcb_output_image_webp. kicad-cli renders PNG and JPEG only, so the
# WebP is converted from the render; libwebp's encoder is the whole dependency
# and it is a few hundred kilobytes.
RUN apt-get -o Acquire::Retries=3 update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends webp \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY glb/ /glb/
COPY img/ /img/

ENTRYPOINT ["/entrypoint.sh"]
