FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        dpkg-dev \
        qt6-base-dev \
    && rm -rf /var/lib/apt/lists/*

COPY linux/docker/build-deb.sh /usr/local/bin/build-deb
RUN chmod 0755 /usr/local/bin/build-deb

WORKDIR /src
ENTRYPOINT ["/usr/local/bin/build-deb"]
