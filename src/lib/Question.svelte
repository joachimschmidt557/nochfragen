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

  let editing = $state(false);
  let editText = $state('');
  let editAlert = $state('');
  let saving = $state(false);

  function openEdit() {
    editing = true;
    editText = item.text;
    editAlert = '';
  }

  function cancelEdit() {
    editing = false;
    editText = '';
    editAlert = '';
  }

  async function saveEdit() {
    editAlert = '';
    if (editText.trim().length === 0) {
      editAlert = m.app_questions_item_edit_empty();
      return;
    }
    if (editText.length > 500) {
      editAlert = m.app_questions_item_edit_too_long({ count: 500 });
      return;
    }

    try {
      saving = true;
      const response = await fetch(`/api/question/${item.id}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ text: editText })
      });

      if (!response.ok) {
        throw new Error('Failed to edit question');
      }

      item.text = editText;
      editing = false;
    } catch (error) {
      editAlert = `${error}`;
    } finally {
      saving = false;
    }
  }

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
    {#if editing}
      {#if editAlert !== ''}
        <div class="alert alert-danger" role="alert">
          {editAlert}
        </div>
      {/if}
      <div class="d-flex justify-content-between flex-grow-1">
        <input bind:value={editText} class="form-control" id="editQuestion" />
        <div class="btn-group ms-2" role="group">
          <button onclick={cancelEdit} type="button" class="btn btn-secondary">
            {m.app_questions_item_edit_cancel()}
          </button>
          <button onclick={saveEdit} type="button" class="btn btn-primary" disabled={saving}>
            {m.app_questions_item_edit_save()}
          </button>
        </div>
      </div>
    {:else}
      {#if item.state === QuestionState.Answered}
        <span class="text-muted">{item.text}</span>
      {:else}
        {item.text}
      {/if}
      <div>
        <div class="btn-group" role="group">
          {#if loggedIn}
            <button onclick={openEdit} type="button" class="btn btn-outline-secondary">
              {m.app_questions_item_edit()}
            </button>
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
              {m.app_questions_item_status_hidden_and_answered()}
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
    {/if}
  </li>
{/if}
