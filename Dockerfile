FROM rust:1.92-alpine AS backend

RUN apk add --no-cache sqlite-dev sqlite-static

WORKDIR /app
COPY backend .
RUN cargo build --release

FROM node:22-alpine3.20 AS frontend

WORKDIR /app
COPY src ./src
COPY package.json package-lock.json svelte.config.js vite.config.js .env ./

RUN npm i
RUN npm run build

FROM alpine:3.23 AS app

WORKDIR /app
COPY --from=backend /app/target/release/nochfragen /app/nochfragen
COPY --from=frontend /app/build ./build

EXPOSE 8080

ENV ROOT_DIR=build
ENV LISTEN_ADDRESS=0.0.0.0:8080
ENTRYPOINT ["/app/nochfragen"]
