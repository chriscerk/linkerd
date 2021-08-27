# from https://www.artificialworlds.net/blog/2020/04/22/creating-a-tiny-docker-image-of-a-rust-project/
#
# 1: Build the exe
FROM rust:1.53 as builder
WORKDIR /usr/src

# 1a: Prepare for static linking
RUN rustup component add rustfmt

# 1b: Download and compile Rust dependencies (and store as a separate Docker layer)
RUN USER=root cargo new signer
COPY rust/b3 ./b3
COPY rust/dill ./dill
WORKDIR /usr/src/signer
COPY rust/signer/Cargo.toml ./
RUN cargo install --path .

# 1c: Build the exe using the actual source code
COPY rust/signer/src ./src
RUN ["touch", "src/main.rs"]
RUN cargo install --path .

# 2: Copy the exe to an empty Docker image
FROM rust:1.53-slim
COPY --from=builder /usr/local/cargo/bin/pickle_signer .
COPY rust/signer/keys ./keys
ARG SIGN_GRPC_PORT=9090
ENV SIGN_GRPC_PORT=$SIGN_GRPC_PORT
ARG TRACING_SERVICE_NAME=signing-svc
ENV TRACING_SERVICE_NAME=$TRACING_SERVICE_NAME
ARG TRACING_COLLECTOR_ENDPOINT=http://collector.linkerd-jaeger:14268/api/traces
ENV TRACING_COLLECTOR_ENDPOINT=$TRACING_COLLECTOR_ENDPOINT
ARG RUST_LOG=TRACE
ENV RUST_LOG=$RUST_LOG
CMD ./pickle_signer \
        --port $WORD_GRPC_PORT \
        --tracing-service-name $TRACING_SERVICE_NAME \
        --trace-collector-endpoint $TRACING_COLLECTOR_ENDPOINT
