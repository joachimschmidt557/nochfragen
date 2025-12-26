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

diesel::table! {
    survey_options (id) {
        id -> Integer,
        survey -> Integer,
        text -> Text,
        votes -> Integer,
    }
}

diesel::table! {
    surveys (id) {
        id -> Integer,
        text -> Text,
        state -> Integer,
    }
}

diesel::joinable!(survey_options -> surveys (survey));

diesel::allow_tables_to_appear_in_same_query!(questions, survey_options, surveys,);
