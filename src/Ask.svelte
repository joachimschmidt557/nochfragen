<script>
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();

  let questionText = "";

  async function submitQuestion() {
    await fetch(`/api/questions`, {
      method: "POST",
      body: JSON.stringify({ text: questionText }),
    }).then(() => {
      questionText = "";
      dispatch("success", "");
    }).catch((error) => dispatch("error", error));
  }
</script>

<div class="list-group-item">
  <form on:submit|preventDefault={submitQuestion}>
    <label for="questionText" class="form-label">Ask a question</label>
    <div class="d-flex justify-content-between">
      <input bind:value={questionText} class="form-control" id="questionText" />
      <button type="submit" class="btn btn-primary">Ask</button>
    </div>
    <div id="moderationLabel" class="form-text">Questions are subject to moderation</div>
  </form>
</div>
