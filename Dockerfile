FROM alpine:3.20 as backend

RUN apk add --no-cache curl

RUN curl -LS https://github.com/mattnite/gyro/releases/download/0.7.0/gyro-0.7.0-linux-x86_64.tar.gz | tar xz

RUN curl -LS https://ziglang.org/download/0.10.1/zig-linux-x86_64-0.10.1.tar.xz | tar xJ

WORKDIR /app
COPY backend ./backend
COPY build.zig gyro.lock gyro.zzz ./

RUN /gyro-0.7.0-linux-x86_64/bin/gyro fetch
RUN /zig-linux-x86_64-0.10.1/zig build -Drelease-safe

FROM node:22-alpine3.20 as frontend

WORKDIR /app
COPY src ./src
COPY package.json package-lock.json rollup.config.js ./

RUN npm i
RUN npm run build

FROM alpine:3.20 as app

WORKDIR /app
COPY public ./public
COPY --from=backend /app/zig-out/bin/nochfragen .
COPY --from=frontend /app/public/build ./public/build

ENTRYPOINT ["/app/nochfragen"]
