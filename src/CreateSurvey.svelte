<script>
  import { createEventDispatcher } from "svelte";

  const dispatch = createEventDispatcher();

  let questionText = "";
  let newOptionText = "";
  let options = [];

  async function submitQuestion() {
    await fetch(`api/surveys`, {
      method: "POST",
      body: JSON.stringify({ text: questionText, options: options }),
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(
            `Server returned ${response.status} ${response.statusText}.`
          );
        }

        questionText = "";
        options = [];
        dispatch("success", "");
      })
      .catch((error) => dispatch("error", error));
  }

  function addOption() {
    options = options.concat(newOptionText);
    newOptionText = "";
  }
</script>

<div class="list-group-item">
  <form on:submit|preventDefault={submitQuestion}>
    <label for="questionText" class="form-label">Create a survey</label>
    <div class="d-flex justify-content-between mb-2">
      <input bind:value={questionText} class="form-control" id="questionText" />
      <button
        type="submit"
        class="btn btn-primary ms-2"
        disabled={questionText === "" || options.length == 0}
        >Create survey</button
      >
    </div>
    {#each options as option, index}
      <div class="input-group mb-2">
        <input bind:value={option} class="form-control" />
        <button
          on:click={() => (options = options.filter((_, i) => i != index))}
          class="btn btn-outline-danger"
          type="button">Remove option</button
        >
      </div>
    {/each}
    <div class="input-group mb-2">
      <input bind:value={newOptionText} class="form-control" />
      <button
        on:click={addOption}
        class="btn btn-outline-secondary"
        type="button"
        disabled={newOptionText === ""}>Add option</button
      >
    </div>
    <div id="createSurveyLabel" class="form-text">
      Surveys are hidden by default
    </div>
  </form>
</div>
