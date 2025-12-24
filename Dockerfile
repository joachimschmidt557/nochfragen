FROM rust:1.92-alpine AS backend

WORKDIR /app
COPY backend ./backend

WORKDIR /app/backend
RUN cargo build --release

FROM node:22-alpine3.20 AS frontend

WORKDIR /app
COPY src ./src
COPY package.json package-lock.json svelte.config.js vite.config.js .env ./

RUN npm i
RUN npm run build

FROM alpine:3.20 AS app

WORKDIR /app
COPY --from=backend /app/backend/target/release/backend /app/nochfragen
COPY --from=frontend /app/build ./build

ENTRYPOINT ["/app/nochfragen"]
