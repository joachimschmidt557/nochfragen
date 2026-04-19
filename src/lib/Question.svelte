<script lang="ts">
  import { _ } from 'svelte-i18n';
  import type { Question } from './types';

  interface Props {
    item: Question;
    loggedIn: boolean;
  }

  let { item = $bindable(), loggedIn }: Props = $props();

  let deleted = $state(false);

  const hidden = 0;
  const unanswered = 1;
  const answering = 2;
  const answered = 3;
  const hiddenAnswered = 4;

  async function upvote() {
    await fetch(`/api/question/${item.id}/upvote`, {
      method: 'POST'
    });

    item.upvotes += 1;
    item.upvoted = true;
  }

  async function changeState(state: number) {
    await fetch(`/api/question/${item.id}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ state: state })
    });

    item.state = state;
  }

  async function deleteQuestion() {
    await fetch(`/api/question/${item.id}`, {
      method: 'DELETE'
    });

    deleted = true;
  }
</script>

{#if !deleted}
  <li
    class={item.state === answering
      ? 'list-group-item active d-flex justify-content-between'
      : 'list-group-item d-flex justify-content-between'}
  >
    {#if item.state === answered}
      <span class="text-muted">{item.text}</span>
    {:else}
      {item.text}
    {/if}
    <div>
      <div class="btn-group" role="group">
        {#if loggedIn}
          <button onclick={() => deleteQuestion()} type="button" class="btn btn-danger">
            {$_('app.questions.item.delete')}
          </button>
          <button
            onclick={() => changeState(hidden)}
            type="button"
            class={item.state === hidden ? 'btn btn-secondary active' : 'btn btn-secondary'}
          >
            {$_('app.questions.item.status.hidden')}
          </button>
          <button
            onclick={() => changeState(unanswered)}
            type="button"
            class={item.state === unanswered ? 'btn btn-secondary active' : 'btn btn-secondary'}
          >
            {$_('app.questions.item.status.unanswered')}
          </button>
          <button
            onclick={() => changeState(answering)}
            type="button"
            class={item.state === answering ? 'btn btn-secondary active' : 'btn btn-secondary'}
          >
            {$_('app.questions.item.status.answering')}
          </button>
          <button
            onclick={() => changeState(answered)}
            type="button"
            class={item.state === answered ? 'btn btn-secondary active' : 'btn btn-secondary'}
          >
            {$_('app.questions.item.status.answered')}
          </button>
          <button
            onclick={() => changeState(hiddenAnswered)}
            type="button"
            class={item.state === hiddenAnswered ? 'btn btn-secondary active' : 'btn btn-secondary'}
          >
            Hidden and answered
          </button>
        {/if}
      </div>
      <button
        onclick={upvote}
        disabled={item.upvoted}
        type="button"
        class={item.state === answering ? 'btn btn-light' : 'btn btn-primary'}
        style="min-width: 8em"
      >
        {#if item.upvoted}
          {$_('app.questions.item.upvoted')}
        {:else}
          {$_('app.questions.item.upvote')}
        {/if}
        <span class="badge bg-secondary">{item.upvotes}</span>
      </button>
    </div>
  </li>
{/if}
