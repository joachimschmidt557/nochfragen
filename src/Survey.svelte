<script>
  import { _, t, format } from "svelte-i18n";
  export let item;
  export let loggedIn;

  let choice = -1;

  let deleted = false;

  const vote = 0;
  const modifyState = 1;

  const hidden = 0;
  const visible = 1;

  async function submit() {
    await fetch(`api/survey/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({ mode: vote, vote: choice, state: hidden }),
    }).then(() => {
      item.voted = true;
    });
  }

  async function show() {
    await fetch(`api/survey/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({
        mode: modifyState,
        vote: 0,
        state: visible,
      }),
    }).then(() => (item.state = visible));
  }

  async function hide() {
    await fetch(`api/survey/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({
        mode: modifyState,
        vote: 0,
        state: hidden,
      }),
    }).then(() => (item.state = hidden));
  }

  async function del() {
    await fetch(`api/survey/${item.id}`, {
      method: "DELETE",
    }).then(() => (deleted = true));
  }

  function calcPercent(votes) {
    const total = item.options.reduce((acc, option) => acc + option.votes, 0);
    const p = total > 0 ? (votes / total) * 100 : 0;
    return `${p}%`;
  }
</script>

{#if !deleted}
  <li class="list-group-item">
    <div class="d-flex w-100 justify-content-between">
      {item.text}
      <div class="btn-group" role="group">
        {#if loggedIn}
          <button on:click={del} type="button" class="btn btn-danger">
            {$_("app.surveys.delete")}
          </button>
          {#if item.state === visible}
            <button on:click={hide} type="button" class="btn btn-primary">
              {$_("app.surveys.hide")}
            </button>
          {:else}
            <button on:click={show} type="button" class="btn btn-primary">
              {$_("app.surveys.show")}
            </button>
          {/if}
        {/if}
      </div>
    </div>

    <div class="list-group">
      {#each item.options as option}
        <label class="list-group-item">
          {#if !item.voted}
            <input
              class="form-check-input me-1"
              type="radio"
              bind:group={choice}
              value={option.id}
              disabled={item.voted}
            />
          {/if}
          {option.text} ({option.votes})
          <div class="progress">
            <div
              class="progress-bar"
              role="progressbar"
              style:width={calcPercent(option.votes)}
            />
          </div></label
        >
      {/each}
    </div>
    {#if !item.voted}
      <button
        on:click={submit}
        class="btn btn-primary mt-2"
        disabled={choice == -1}>{$_("app.surveys.submit")}</button
      >
    {/if}
  </li>
{/if}
