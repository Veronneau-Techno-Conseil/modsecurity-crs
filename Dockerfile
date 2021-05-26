#FROM registry.apps.k8s.vertechcon.lan/nginx-ubuntu:0.0.1
#FROM debian:sid
FROM nginx:1.20.0

ARG CRS_RELEASE=v3.3.0

RUN apt update && apt-get install software-properties-common -y

RUN apt update && apt install -y \
        autoconf \
        automake \
        build-essential 
RUN apt install -y \
        cmake \
        gcc \
        gettext \
        make \
        libtool
RUN apt install -y \
        libcurl4-gnutls-dev \
        liblua5.3-dev \
        pkg-config \
        libpcre3 \
        libpcre3-dev 
RUN apt install -y \
        libxml2 \
        libxml2-dev \
        libcurl4 \
        libgeoip-dev 
RUN apt install -y \
        doxygen \
        ruby \
        wget \
        moreutils \
        zlib1g-dev 

RUN apt install git -y

WORKDIR /sources

RUN git clone https://github.com/LMDB/lmdb --branch LMDB_0.9.23 --depth 1 \
 && make -C lmdb/libraries/liblmdb install

RUN git clone https://github.com/lloyd/yajl --branch 2.1.0 --depth 1 \
 && cd yajl \
 && ./configure \
 && make install 

RUN wget --quiet https://github.com/ssdeep-project/ssdeep/releases/download/release-2.14.1/ssdeep-2.14.1.tar.gz \
 && tar -xvzf ssdeep-2.14.1.tar.gz \
 && cd ssdeep-2.14.1 \
 && ./configure \
 && make install 

RUN git clone https://github.com/SpiderLabs/ModSecurity --branch v3.0.4 --depth 1 \
 && cd ModSecurity \
 && ./build.sh \
 && git submodule init \
 && git submodule update \
 && ./configure --with-yajl=/sources/yajl/build/yajl-2.1.0/ \
 && make install \
 && rm -r ./*

COPY etc/modsecurity.d/*.conf /etc/modsecurity.d/
COPY conf.d/*.conf /etc/nginx/conf.d/
COPY nginx.conf /etc/nginx/
COPY docker-entrypoint.sh /

RUN git clone https://github.com/SpiderLabs/ModSecurity-nginx --branch v1.0.1 --depth 1 \
    && mkdir /etc/nginx/ssl/ 

RUN version="$(/usr/sbin/nginx -v 2>&1 | cut -d '/' -f 2)" \
 && wget --quiet http://nginx.org/download/nginx-"$version".tar.gz \
 && tar -xvzf nginx-"$version".tar.gz \
 && cd ./nginx-"$version" \
 && ./configure --with-compat --add-dynamic-module=../ModSecurity-nginx \
 && make modules \
 && cp objs/ngx_http_modsecurity_module.so /etc/nginx/modules/ \
 && wget --quiet https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended \
    -O /etc/modsecurity.d/modsecurity.conf \
 && wget --quiet https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/unicode.mapping \
    -O /etc/modsecurity.d/unicode.mapping

RUN rm -r ./*

RUN chgrp -R 0 /var/cache/nginx/ /var/log/ /var/run/ /usr/share/nginx/ /etc/nginx/ /etc/modsecurity.d/ \
 && chmod -R g=u /var/cache/nginx/ /var/log/ /var/run/ /usr/share/nginx/ /etc/nginx/ /etc/modsecurity.d/

ENV PARANOIA=1 \
    ANOMALY_INBOUND=5 \
    ANOMALY_OUTBOUND=4 \
    ACCESSLOG=/var/log/nginx/access.log \
    NGINX_KEEPALIVE_TIMEOUT=60s \
    BACKEND=http://localhost:80 \
    DNS_SERVER= \
    ERRORLOG=/var/log/nginx/error.log \
    LOGLEVEL=warn \
    METRICS_ALLOW_FROM='127.0.0.0/24' \
    METRICS_DENY_FROM='all' \
    METRICSLOG=/dev/null \
    MODSEC_AUDIT_LOG_FORMAT=JSON \
    MODSEC_AUDIT_LOG_TYPE=Serial \
    MODSEC_AUDIT_LOG=/dev/stdout \
    MODSEC_AUDIT_STORAGE=/var/log/modsecurity/audit/ \
    MODSEC_DATA_DIR=/tmp/modsecurity/data \
    MODSEC_DEBUG_LOG=/dev/null \
    MODSEC_DEBUG_LOGLEVEL=0 \
    MODSEC_PCRE_MATCH_LIMIT_RECURSION=100000 \
    MODSEC_PCRE_MATCH_LIMIT=100000 \
    MODSEC_REQ_BODY_ACCESS=on \
    MODSEC_REQ_BODY_LIMIT=13107200 \
    MODSEC_REQ_BODY_NOFILES_LIMIT=131072 \
    MODSEC_RESP_BODY_ACCESS=on \
    MODSEC_RESP_BODY_LIMIT=1048576 \
    MODSEC_RULE_ENGINE=on \
    MODSEC_TAG=modsecurity \
    MODSEC_TMP_DIR=/tmp/modsecurity/tmp \
    MODSEC_UPLOAD_DIR=/tmp/modsecurity/upload \
    PORT=80 \
    PROXY_TIMEOUT=60s \
    PROXY_SSL_CERT_KEY=/etc/nginx/conf/server.key \
    PROXY_SSL_CERT=/etc/nginx/conf/server.crt \
    PROXY_SSL_VERIFY=off \
    SERVERNAME=localhost \
    SSL_PORT=443 \
    TIMEOUT=60s \
    WORKER_CONNECTIONS=1024 \
    LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib \
    USER=nginx 

COPY opt/modsecurity/activate-rules.sh /opt/modsecurity/
COPY etc/modsecurity.d/*.conf /etc/modsecurity.d/

# Change default shell to bash
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008,SC2016
RUN apt-get update && apt-get -y install --no-install-recommends ca-certificates curl iproute2 

RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/*


RUN mkdir /opt/owasp-crs && curl -SL https://github.com/coreruleset/coreruleset/archive/${CRS_RELEASE}.tar.gz | tar -zxf - --strip-components=1 -C /opt/owasp-crs 
RUN mv -v /opt/owasp-crs/crs-setup.conf.example /opt/owasp-crs/crs-setup.conf \
 && ln -sv /opt/owasp-crs /etc/modsecurity.d/ \
 && rm -rf /var/lib/apt/lists/*

# Generate self-signed certificates (if needed)
RUN mkdir -p /usr/share/TLS
COPY openssl.conf /etc/nginx/conf/
RUN openssl req -x509 -days 365 -new \
      -config /etc/nginx/conf/openssl.conf \
      -keyout /etc/nginx/conf/server.key \
      -out /etc/nginx/conf/server.crt

WORKDIR /


ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

