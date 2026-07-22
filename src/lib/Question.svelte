<script lang="ts">
  import { m } from '$lib/paraglide/messages.js';
  import type { Question } from './types';
  import { QuestionState } from './types';

  interface Props {
    item: Question;
    loggedIn: boolean;
  }

  let { item = $bindable(), loggedIn }: Props = $props();

  let deleted = $state(false);

  async function upvote() {
    try {
      const response = await fetch(`/api/question/${item.id}/upvote`, {
        method: 'POST'
      });

      if (!response.ok) {
        throw new Error('Failed to upvote');
      }

      item.upvotes += 1;
      item.upvoted = true;
    } catch (error) {
      console.error('Failed to upvote:', error);
    }
  }

  async function changeState(state: QuestionState) {
    try {
      const response = await fetch(`/api/question/${item.id}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ state: state })
      });

      if (!response.ok) {
        throw new Error('Failed to update state');
      }

      item.state = state;
    } catch (error) {
      console.error('Failed to change state:', error);
    }
  }

  async function deleteQuestion() {
    try {
      const response = await fetch(`/api/question/${item.id}`, {
        method: 'DELETE'
      });

      if (!response.ok) {
        throw new Error('Failed to delete');
      }

      deleted = true;
    } catch (error) {
      console.error('Failed to delete question:', error);
    }
  }
</script>

{#if !deleted}
  <li
    class={[
      'list-group-item d-flex justify-content-between',
      item.state === QuestionState.Answering && 'active'
    ]}
  >
    {#if item.state === QuestionState.Answered}
      <span class="text-muted">{item.text}</span>
    {:else}
      {item.text}
    {/if}
    <div>
      <div class="btn-group" role="group">
        {#if loggedIn}
          <button onclick={() => deleteQuestion()} type="button" class="btn btn-danger">
            {m.app_questions_item_delete()}
          </button>
          <button
            onclick={() => changeState(QuestionState.Hidden)}
            type="button"
            class={['btn btn-secondary', item.state === QuestionState.Hidden && 'active']}
          >
            {m.app_questions_item_status_hidden()}
          </button>
          <button
            onclick={() => changeState(QuestionState.Unanswered)}
            type="button"
            class={['btn btn-secondary', item.state === QuestionState.Unanswered && 'active']}
          >
            {m.app_questions_item_status_unanswered()}
          </button>
          <button
            onclick={() => changeState(QuestionState.Answering)}
            type="button"
            class={['btn btn-secondary', item.state === QuestionState.Answering && 'active']}
          >
            {m.app_questions_item_status_answering()}
          </button>
          <button
            onclick={() => changeState(QuestionState.Answered)}
            type="button"
            class={['btn btn-secondary', item.state === QuestionState.Answered && 'active']}
          >
            {m.app_questions_item_status_answered()}
          </button>
          <button
            onclick={() => changeState(QuestionState.HiddenAnswered)}
            type="button"
            class={['btn btn-secondary', item.state === QuestionState.HiddenAnswered && 'active']}
          >
            Hidden and answered
          </button>
        {/if}
      </div>
      <button
        onclick={upvote}
        disabled={item.upvoted}
        type="button"
        class={['btn', item.state === QuestionState.Answering ? 'btn-light' : 'btn-primary']}
        style="min-width: 8em"
      >
        {#if item.upvoted}
          {m.app_questions_item_upvoted()}
        {:else}
          {m.app_questions_item_upvote()}
        {/if}
        <span class="badge bg-secondary">{item.upvotes}</span>
      </button>
    </div>
  </li>
{/if}
