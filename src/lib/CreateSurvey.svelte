<script>
  import { _, t, format } from 'svelte-i18n';

  let { success, error } = $props();

  let questionText = $state('');
  let newOptionText = $state('');
  let options = $state([]);

  async function submitQuestion(ev) {
    ev.preventDefault();

    await fetch(`api/surveys`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ text: questionText, options: options })
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(
            $_('response.error.surveys.serverreturn', {
              values: {
                status: response.status,
                statusText: response.statusText
              }
            })
          );
        }

        questionText = '';
        options = [];
        success();
      })
      .catch((e) => error(e));
  }

  function addOption() {
    options = options.concat(newOptionText);
    newOptionText = '';
  }
</script>

<div class="list-group-item">
  <form onsubmit={submitQuestion}>
    <label for="surveyQuestionText" class="form-label">{$_('app.surveycreationmodal.title')}</label>
    <div class="d-flex justify-content-between mb-2">
      <input bind:value={questionText} class="form-control" id="surveyQuestionText" />
      <button
        type="submit"
        class="btn btn-primary ms-2"
        disabled={questionText === '' || options.length == 0}
        >{$_('app.surveycreationmodal.action')}</button
      >
    </div>
    {#each options as option, index}
      <div class="input-group mb-2">
        <input bind:value={options[index]} class="form-control" />
        <button
          onclick={() => (options = options.filter((_, i) => i != index))}
          class="btn btn-outline-danger"
          type="button">{$_('app.surveycreationmodal.remove')}</button
        >
      </div>
    {/each}
    <div class="input-group mb-2">
      <input bind:value={newOptionText} class="form-control" />
      <button
        onclick={addOption}
        class="btn btn-outline-secondary"
        type="button"
        disabled={newOptionText === ''}>{$_('app.surveycreationmodal.add')}</button
      >
    </div>
    <div id="createSurveyLabel" class="form-text">
      {$_('app.surveycreationmodal.description')}
    </div>
  </form>
</div>
