# ============================================================
# Stage 1: Build amneziawg-go
# ============================================================

FROM golang:1.25-alpine3.24 AS awg-go-builder

RUN apk add --no-cache git

WORKDIR /build

ARG AWG_GO_REF=v0.2.18
RUN git clone \
    --branch "$AWG_GO_REF" \
    --depth 1 \
    https://github.com/amnezia-vpn/amneziawg-go.git

WORKDIR /build/amneziawg-go

ENV GOOS=linux
ENV GOARCH=arm
ENV GOARM=7
ENV CGO_ENABLED=0

RUN go build -o /out/amneziawg-go


# ============================================================
# Stage 2: Build awg tools
# ============================================================

FROM alpine:3.24 AS awg-tools-builder

RUN apk add --no-cache \
    bash \
    git \
    make \
    gcc \
    musl-dev \
    linux-headers \
    pkgconf

WORKDIR /build

ARG AWG_TOOLS_REF=v1.0.20260223
RUN git clone \
    --branch "$AWG_TOOLS_REF" \
    --depth 1 \
    https://github.com/amnezia-vpn/amneziawg-tools.git


WORKDIR /build/amneziawg-tools/src

RUN make

RUN mkdir -p /out

RUN cp wg /out/awg
RUN cp wg-quick/linux.bash /out/awg-quick

RUN chmod +x /out/awg
RUN chmod +x /out/awg-quick


# ============================================================
# Stage 3: Runtime image
# ============================================================

FROM alpine:3.24

RUN apk add --no-cache openresolv

RUN apk add --no-cache \
    bash \
    iproute2 \
    iptables \
    iputils \
    openresolv \
    openrc \
    procps

COPY --from=awg-go-builder \
    /out/amneziawg-go \
    /usr/local/bin/amneziawg-go

COPY --from=awg-tools-builder \
    /out/awg \
    /usr/local/bin/awg

COPY --from=awg-tools-builder \
    /out/awg-quick \
    /usr/local/bin/awg-quick

COPY start.sh /start.sh

RUN chmod +x \
    /usr/local/bin/amneziawg-go \
    /usr/local/bin/awg \
    /usr/local/bin/awg-quick \
    /start.sh

VOLUME ["/config"]

HEALTHCHECK \
    --interval=30s \
    --timeout=5s \
    --start-period=20s \
    --retries=3 \
    CMD awg show awg0 latest-handshakes \
        | awk '{ if ($2 > 0) found=1 } END { exit(found ? 0 : 1) }'

RUN sed -i 's/^tty/#tty/' /etc/inittab

ENTRYPOINT ["sh", "-c"]
CMD ["/sbin/init & sleep 2 && /start.sh && wait"]

