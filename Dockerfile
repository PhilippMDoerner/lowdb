ARG  NIM_VERSION=1.4.0
FROM nimlang/nim:${NIM_VERSION}
RUN  apt-get update && apt-get install -y sqlite3 postgresql-client

WORKDIR /usr/src/app

COPY . /usr/src/app
RUN nimble install -y