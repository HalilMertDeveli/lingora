// Writing tasks of the general course (docs/genel-mufredat.md §3, `write`
// exercises). Keyed by the exercise's taskId ("<node id>w"). Kept on the
// server so the app cannot change the rubric the model is given; each task
// must match its exercise in assets/courses/tr_en/*.json.

/** Error types feedback may focus on; same names as lib/models/course.dart. */
export const FOCUS_TYPES = ["article", "tense", "preposition", "word_order", "be"] as const;
export type FocusType = (typeof FOCUS_TYPES)[number];

export interface WritingTask {
  level: "A1" | "A2" | "B1" | "B2" | "C1";
  /** What the learner is asked to write, in Turkish (as in the app). */
  task: string;
  minWords: number;
  maxWords: number;
  /** What a good answer contains (the app's checklist). */
  checklist: string[];
  /** At most three error types the corrections concentrate on. */
  focus: FocusType[];
  /** Task-specific rubric notes for the model, in English. */
  rubric: string;
}

/** Filled by the content phases (Faz 2b: S5–S8 skill units). */
export const WRITING_TASKS: Record<string, WritingTask> = {};
