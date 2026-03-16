/**
 * Feedback sheet reactive store — controls overlay open state.
 */

class FeedbackStore {
  #open = $state(false);

  get open() {
    return this.#open;
  }

  show() {
    this.#open = true;
  }

  hide() {
    this.#open = false;
  }
}

export const feedbackStore = new FeedbackStore();
