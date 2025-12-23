FROM alpine:3.20 AS backend

RUN apk add --no-cache curl

RUN curl -LS https://github.com/mattnite/gyro/releases/download/0.7.0/gyro-0.7.0-linux-x86_64.tar.gz | tar xz

RUN curl -LS https://ziglang.org/download/0.10.1/zig-linux-x86_64-0.10.1.tar.xz | tar xJ

WORKDIR /app
COPY backend-zig ./backend-zig
COPY build.zig gyro.lock gyro.zzz ./

RUN /gyro-0.7.0-linux-x86_64/bin/gyro fetch
RUN /zig-linux-x86_64-0.10.1/zig build -Drelease-safe

FROM node:22-alpine3.20 AS frontend

WORKDIR /app
COPY src ./src
COPY package.json package-lock.json svelte.config.js vite.config.js .env ./

RUN npm i
RUN npm run build

FROM alpine:3.20 AS app

WORKDIR /app
COPY --from=backend /app/zig-out/bin/nochfragen .
COPY --from=frontend /app/build ./build

ENTRYPOINT ["/app/nochfragen"]
