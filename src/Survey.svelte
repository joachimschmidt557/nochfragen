<script>
  export let item;
  export let loggedIn;

  let choice = -1;

  const vote = 0;
  const modifyVisibility = 1;

  const hidden = 0;
  const visible = 1;
  const deleted = 2;

  async function submit() {
    await fetch(`api/survey/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({ mode: vote, vote: choice, visibility: hidden }),
    }).then(() => {
      item.voted = true;
    });
  }

  async function show() {
    await fetch(`api/survey/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({
        mode: modifyVisibility,
        vote: 0,
        visibility: visible,
      }),
    }).then(() => (item.visibility = visible));
  }

  async function hide() {
    await fetch(`api/survey/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({
        mode: modifyVisibility,
        vote: 0,
        visibility: hidden,
      }),
    }).then(() => (item.visibility = hidden));
  }

  async function del() {
    await fetch(`api/survey/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({
        mode: modifyVisibility,
        vote: 0,
        visibility: deleted,
      }),
    }).then(() => (item.visibility = deleted));
  }

  function calcPercent(votes) {
    const total = item.options.reduce((acc, option) => acc + option.votes, 0);
    const p = total > 0 ? (votes / total) * 100 : 0;
    return `${p}%`;
  }
</script>

{#if item.visibility !== deleted}
  <li class="list-group-item">
    <div class="d-flex w-100 justify-content-between">
      {item.text}
      <div class="btn-group" role="group">
        {#if loggedIn}
          <button on:click={del} type="button" class="btn btn-danger">
            Delete
          </button>
          {#if item.visibility === visible}
            <button on:click={hide} type="button" class="btn btn-primary">
              Hide
            </button>
          {:else}
            <button on:click={show} type="button" class="btn btn-primary">
              Show
            </button>
          {/if}
        {/if}
      </div>
    </div>

    <div class="list-group">
      {#each item.options as option, index}
        <label class="list-group-item">
          {#if !item.voted}
            <input
              class="form-check-input me-1"
              type="radio"
              bind:group={choice}
              value={index}
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
        disabled={choice == -1}>Submit</button
      >
    {/if}
  </li>
{/if}
