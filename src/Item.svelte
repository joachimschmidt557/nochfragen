<script>
  export let item;
  export let loggedIn;

  const hidden = 0;
  const visible = 1;
  const deleted = 2;

  async function upvote() {
    await fetch(`api/question/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({ upvote: true, state: 0 }),
    }).then(() => {
      item.upvotes += 1;
      item.upvoted = true;
    });
  }

  async function show() {
    await fetch(`api/question/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({ upvote: false, state: visible }),
    }).then(() => (item.state = visible));
  }

  async function hide() {
    await fetch(`api/question/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({ upvote: false, state: hidden }),
    }).then(() => (item.state = hidden));
  }

  async function del() {
    await fetch(`api/question/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({ upvote: false, state: deleted }),
    }).then(() => (item.state = deleted));
  }
</script>

{#if item.state !== deleted}
  <li class="list-group-item d-flex justify-content-between">
    {item.text}
    <div class="btn-group" role="group">
      {#if loggedIn}
        <button on:click={del} type="button" class="btn btn-danger">
          Delete
        </button>
        {#if item.state === visible}
          <button on:click={hide} type="button" class="btn btn-primary">
            Hide
          </button>
        {:else}
          <button on:click={show} type="button" class="btn btn-primary">
            Show
          </button>
        {/if}
      {/if}
      <button
        on:click={upvote}
        disabled={item.upvoted}
        type="button"
        class="btn btn-primary"
      >
        Upvote ({item.upvotes})
      </button>
    </div>
  </li>
{/if}
