<script lang="ts">
  import QuestionComponent from '$lib/Question.svelte';
  import type { Question } from './types';

  interface Props {
    items: Question[];
    loggedIn: boolean;
  }

  let { items, loggedIn }: Props = $props();
</script>

{#if items}
  {#each items as item (item.id)}
    <QuestionComponent {item} {loggedIn} />
  {/each}
{/if}
