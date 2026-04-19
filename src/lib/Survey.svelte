<script lang="ts">
  import { _ } from 'svelte-i18n';
  import type { Survey } from './types';

  interface Props {
    item: Survey;
    loggedIn: boolean;
  }

  let { item = $bindable(), loggedIn }: Props = $props();

  let choice = $state(-1);

  let deleted = $state(false);

  let total = $derived(item.options.reduce((acc, option) => acc + option.votes, 0));

  const hidden = 0;
  const visible = 1;

  async function submit() {
    await fetch(`/api/survey/${item.id}/option/${choice}/vote`, {
      method: 'PUT'
    });

    item.voted = true;
  }

  async function show() {
    await fetch(`/api/survey/${item.id}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        state: visible
      })
    });

    item.state = visible;
  }

  async function hide() {
    await fetch(`/api/survey/${item.id}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        state: hidden
      })
    });

    item.state = hidden;
  }

  async function del() {
    await fetch(`/api/survey/${item.id}`, {
      method: 'DELETE'
    });

    deleted = true;
  }

  function calcPercent(votes: number) {
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
          <button onclick={del} type="button" class="btn btn-danger">
            {$_('app.surveys.delete')}
          </button>
          {#if item.state === visible}
            <button onclick={hide} type="button" class="btn btn-primary">
              {$_('app.surveys.hide')}
            </button>
          {:else}
            <button onclick={show} type="button" class="btn btn-primary">
              {$_('app.surveys.show')}
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
            ></div>
          </div></label
        >
      {/each}
    </div>
    {#if !item.voted}
      <button onclick={submit} class="btn btn-primary mt-2" disabled={choice == -1}
        >{$_('app.surveys.submit')}</button
      >
    {/if}
  </li>
{/if}
