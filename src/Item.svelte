<script>
  import { _, t, format } from "svelte-i18n";

  export let item;
  export let loggedIn;

  const hidden = 0;
  const unanswered = 1;
  const deleted = 2;
  const answering = 3;
  const answered = 4;

  async function upvote() {
    await fetch(`api/question/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({ upvote: true, state: 0 }),
    }).then(() => {
      item.upvotes += 1;
      item.upvoted = true;
    });
  }

  async function changeState(state) {
    await fetch(`api/question/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({ upvote: false, state: state }),
    }).then(() => (item.state = state));
  }
</script>

{#if item.state !== deleted}
  <li
    class={item.state === answering
      ? "list-group-item active d-flex justify-content-between"
      : "list-group-item d-flex justify-content-between"}
  >
    {#if item.state === answered}
      <span class="text-muted">{item.text}</span>
    {:else}
      {item.text}
    {/if}
    <div>
      <div class="btn-group" role="group">
        {#if loggedIn}
          <button
            on:click={() => changeState(deleted)}
            type="button"
            class="btn btn-danger"
          >
            {$_("app.questions.item.delete")}
          </button>
          <button
            on:click={() => changeState(hidden)}
            type="button"
            class={item.state === hidden
              ? "btn btn-secondary active"
              : "btn btn-secondary"}
          >
            {$_("app.questions.item.status.hidden")}
          </button>
          <button
            on:click={() => changeState(unanswered)}
            type="button"
            class={item.state === unanswered
              ? "btn btn-secondary active"
              : "btn btn-secondary"}
          >
            {$_("app.questions.item.status.unanswered")}
          </button>
          <button
            on:click={() => changeState(answering)}
            type="button"
            class={item.state === answering
              ? "btn btn-secondary active"
              : "btn btn-secondary"}
          >
            {$_("app.questions.item.status.answering")}
          </button>
          <button
            on:click={() => changeState(answered)}
            type="button"
            class={item.state === answered
              ? "btn btn-secondary active"
              : "btn btn-secondary"}
          >
            {$_("app.questions.item.status.answered")}
          </button>
        {/if}
      </div>
      <button
        on:click={upvote}
        disabled={item.upvoted}
        type="button"
        class={item.state === answering ? "btn btn-light" : "btn btn-primary"}
        style="min-width: 8em"
      >
        {#if item.upvoted}
          {$_("app.questions.item.upvoted")}
        {:else}
          {$_("app.questions.item.upvote")}
        {/if}
        <span class="badge bg-secondary">{item.upvotes}</span>
      </button>
    </div>
  </li>
{/if}
