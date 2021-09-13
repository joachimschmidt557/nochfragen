# gutefrage

A small web app for asking and moderating questions

## Introduction

Questions can be submitted by any user. Initially, questions are
hidden for non-moderators. Moderators can make hidden questions
visible and can hide visible questions. In addition, moderators can
also delete questions, making them hidden for everyone.

Any user can upvote a question, but a session cannot give more than
one upvote for a single question.

`gutefrage` uses redis as an emphemeral storage backend.

## Building

### Backend

```
go build
```

### Frontend

```
npm i
npm run build
```

## Usage

```
Usage of ./gutefrage:
  -listen-address string
    	Address to listen for connections (default "0.0.0.0:8000")
  -redis-address string
    	Address to connect to redis (default "localhost:6379")
```

## Configuration

- `gutefrage.password` in redis: The password required to access
  moderation features
