<script>
  import { _, t, format } from 'svelte-i18n';

  let { success, error } = $props();

  let questionText = $state('');

  async function submitQuestion(ev) {
    ev.preventDefault();

    try {
      const response = await fetch('api/questions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ text: questionText })
      });

      if (!response.ok) {
        throw new Error(
          $_('response.error.ask.serverreturn', {
            values: {
              status: response.status,
              statusText: response.statusText
            }
          })
        );
      }

      questionText = '';
      success();
    } catch (e) {
      error(e);
    }
  }
</script>

<div class="list-group-item">
  <form onsubmit={submitQuestion}>
    <label for="questionText" class="form-label">{$_('app.ask.title')}</label>
    <div class="d-flex justify-content-between">
      <input bind:value={questionText} class="form-control" id="questionText" />
      <button type="submit" class="btn btn-primary ms-2" disabled={questionText === ''}
        >{$_('app.ask.action')}</button
      >
    </div>
    <div id="moderationLabel" class="form-text">
      {$_('app.ask.moderationnotice')}
    </div>
  </form>
</div>
