export interface Question {
  id: number;
  text: string;
  upvotes: number;
  state: number;
  upvoted: boolean;
}

export interface SurveyOption {
  id: number;
  text: string;
  votes: number;
}

export interface Survey {
  id: number;
  text: string;
  state: number;
  voted: boolean;
  options: SurveyOption[];
}
