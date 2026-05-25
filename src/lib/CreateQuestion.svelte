<script lang="ts">
  import { m } from '$lib/paraglide/messages.js';

  interface Props {
    success: () => void;
    error: (message: string) => void;
  }

  let { success, error }: Props = $props();

  let questionText = $state('');

  async function submitQuestion(ev: SubmitEvent) {
    ev.preventDefault();

    try {
      const response = await fetch('/api/questions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ text: questionText })
      });

      if (!response.ok) {
        throw new Error(
          m.response_error_ask_serverreturn({
            status: response.status,
            statusText: response.statusText
          })
        );
      }

      questionText = '';
      success();
    } catch (e) {
      error(`${e}`);
    }
  }
</script>

<div class="list-group-item">
  <form onsubmit={submitQuestion}>
    <label for="questionText" class="form-label">{m.app_ask_title()}</label>
    <div class="d-flex justify-content-between">
      <input bind:value={questionText} class="form-control" id="questionText" />
      <button type="submit" class="btn btn-primary ms-2" disabled={questionText === ''}>
        {m.app_ask_action()}
      </button>
    </div>
    <div id="moderationLabel" class="form-text">
      {m.app_ask_moderationnotice()}
    </div>
  </form>
</div>
