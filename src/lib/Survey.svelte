<script lang="ts">
  import { m } from '$lib/paraglide/messages.js';
  import type { Survey } from './types';
  import { SurveyState } from './types';

  interface Props {
    item: Survey;
    loggedIn: boolean;
  }

  let { item = $bindable(), loggedIn }: Props = $props();

  let choice = $state(-1);
  let deleted = $state(false);
  let submitError = $state<string | null>(null);

  let total = $derived(item.options.reduce((acc, option) => acc + option.votes, 0));

  async function submit() {
    try {
      const response = await fetch(`/api/survey/${item.id}/option/${choice}/vote`, {
        method: 'PUT'
      });

      if (!response.ok) {
        throw new Error('Failed to vote');
      }

      item.voted = true;
      submitError = null;
    } catch (error) {
      submitError = `${error}`;
    }
  }

  async function show() {
    try {
      const response = await fetch(`/api/survey/${item.id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          state: SurveyState.Visible
        })
      });

      if (!response.ok) {
        throw new Error('Failed to show survey');
      }

      item.state = SurveyState.Visible;
    } catch (error) {
      console.error('Failed to show survey:', error);
    }
  }

  async function hide() {
    try {
      const response = await fetch(`/api/survey/${item.id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          state: SurveyState.Hidden
        })
      });

      if (!response.ok) {
        throw new Error('Failed to hide survey');
      }

      item.state = SurveyState.Hidden;
    } catch (error) {
      console.error('Failed to hide survey:', error);
    }
  }

  async function del() {
    try {
      const response = await fetch(`/api/survey/${item.id}`, {
        method: 'DELETE'
      });

      if (!response.ok) {
        throw new Error('Failed to delete survey');
      }

      deleted = true;
    } catch (error) {
      console.error('Failed to delete survey:', error);
    }
  }

  function calcPercent(votes: number) {
    const p = total > 0 ? (votes / total) * 100 : 0;
    return `${p}%`;
  }
</script>

{#if !deleted}
  <li class="list-group-item">
    {#if submitError}
      <div class="alert alert-danger" role="alert">
        {submitError}
      </div>
    {/if}
    <div class="d-flex w-100 justify-content-between">
      {item.text}
      <div class="btn-group" role="group">
        {#if loggedIn}
          <button onclick={del} type="button" class="btn btn-danger">
            {m.app_surveys_delete()}
          </button>
          {#if item.state === SurveyState.Visible}
            <button onclick={hide} type="button" class="btn btn-primary">
              {m.app_surveys_hide()}
            </button>
          {:else}
            <button onclick={show} type="button" class="btn btn-primary">
              {m.app_surveys_show()}
            </button>
          {/if}
        {/if}
      </div>
    </div>

    <div class="list-group">
      {#each item.options as option (option.id)}
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
            ></div>
          </div>
        </label>
      {/each}
    </div>
    {#if !item.voted}
      <button onclick={submit} class="btn btn-primary mt-2" disabled={choice == -1}>
        {m.app_surveys_submit()}
      </button>
    {/if}
  </li>
{/if}
