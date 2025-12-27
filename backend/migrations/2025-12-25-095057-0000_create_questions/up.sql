CREATE TABLE questions (
    id integer NOT NULL PRIMARY KEY AUTOINCREMENT,
    text text NOT NULL,
    upvotes integer NOT NULL,
    state integer NOT NULL,
    created_at integer NOT NULL,
    modified_at integer NOT NULL,
    answering_at integer NOT NULL,
    answered_at integer NOT NULL
);
