export enum QuestionState {
  Hidden = 0,
  Unanswered = 1,
  Answering = 2,
  Answered = 3,
  HiddenAnswered = 4
}

export interface Question {
  id: number;
  text: string;
  upvotes: number;
  state: QuestionState;
  upvoted: boolean;
}

export enum SurveyState {
  Hidden = 0,
  Visible = 1
}

export interface SurveyOption {
  id: number;
  text: string;
  votes: number;
}

export interface Survey {
  id: number;
  text: string;
  state: SurveyState;
  voted: boolean;
  options: SurveyOption[];
}
