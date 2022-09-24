# nochfragen

A small web app for asking and moderating questions

## Introduction

Questions can be submitted by any user. Initially, questions are
hidden for non-moderators. Moderators can make hidden questions
visible and can hide visible questions. In addition, moderators can
also delete questions, making them hidden for everyone.

Any user can upvote a question, but a session cannot give more than
one upvote for a single question.

`nochfragen` uses redis as an emphemeral storage backend.

## Building

### Backend

```
zig build
```

### Frontend

```
npm i
npm run build
```

## Usage

```
Usage: nochfragen [-h] [--set-password <PASS>] [--listen-address <IP:PORT>] [--redis-address <IP:PORT>] [--root-dir <PATH>]

Options:

    -h, --help
            Display this help and exit.

        --set-password <PASS>
            Set a new password and exit

        --listen-address <IP:PORT>
            Address to listen for connections

        --redis-address <IP:PORT>
            Address to connect to redis

        --root-dir <PATH>
            Path to the static HTML, CSS and JS content

```

## Configuration

- `nochfragen:password` in redis: The password (scrypt hashed)
  required to access moderation features

## License

`nochfragen` is licensed under the MIT (Expat) License.
