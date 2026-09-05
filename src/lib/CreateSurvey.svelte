<script lang="ts">
  import { m } from '$lib/paraglide/messages.js';

  interface Props {
    success: () => void;
    error: (message: string) => void;
  }

  let { success, error }: Props = $props();

  let questionText = $state('');
  let newOptionText = $state('');
  let options: string[] = $state([]);

  async function submitQuestion(ev: SubmitEvent) {
    ev.preventDefault();

    try {
      const response = await fetch(`/api/surveys`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ text: questionText, options: options })
      });

      if (!response.ok) {
        throw new Error(
          m.response_error_survey_serverreturn({
            status: response.status,
            statusText: response.statusText
          })
        );
      }

      questionText = '';
      options = [];
      success();
    } catch (e) {
      error(`${e}`);
    }
  }

  function addOption() {
    options.push(newOptionText);
    newOptionText = '';
  }
</script>

<div class="list-group-item">
  <form onsubmit={submitQuestion}>
    <label for="surveyQuestionText" class="form-label">{m.app_surveycreationmodal_title()}</label>
    <div class="d-flex justify-content-between mb-2">
      <input bind:value={questionText} class="form-control" id="surveyQuestionText" />
      <button
        type="submit"
        class="btn btn-primary ms-2"
        disabled={questionText === '' || options.length == 0}
      >
        {m.app_surveycreationmodal_action()}
      </button>
    </div>
    {#each options as option, index (option + index)}
      <div class="input-group mb-2">
        <input bind:value={options[index]} class="form-control" />
        <button
          onclick={() => (options = options.filter((_, i) => i != index))}
          class="btn btn-outline-danger"
          type="button"
        >
          {m.app_surveycreationmodal_remove()}
        </button>
      </div>
    {/each}
    <div class="input-group mb-2">
      <input bind:value={newOptionText} class="form-control" />
      <button
        onclick={addOption}
        class="btn btn-outline-secondary"
        type="button"
        disabled={newOptionText === ''}
      >
        {m.app_surveycreationmodal_add()}
      </button>
    </div>
    <div id="createSurveyLabel" class="form-text">
      {m.app_surveycreationmodal_description()}
    </div>
  </form>
</div>
