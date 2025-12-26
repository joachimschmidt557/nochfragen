CREATE TABLE surveys (
    id integer NOT NULL PRIMARY KEY AUTOINCREMENT,
    text text NOT NULL,
    state integer NOT NULL
);

CREATE TABLE survey_options (
    id integer NOT NULL PRIMARY KEY AUTOINCREMENT,
    survey integer NOT NULL,
    text text NOT NULL,
    votes integer NOT NULL,
    FOREIGN KEY (survey) REFERENCES surveys (id) ON DELETE CASCADE ON UPDATE CASCADE
);
