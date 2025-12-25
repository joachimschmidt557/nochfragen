// @generated automatically by Diesel CLI.

diesel::table! {
    questions (id) {
        id -> Integer,
        text -> Text,
        upvotes -> Integer,
        state -> Integer,
        created_at -> Integer,
        modified_at -> Integer,
        answering_at -> Integer,
        answered_at -> Integer,
    }
}
