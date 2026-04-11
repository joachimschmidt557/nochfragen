<script>
  import Question from '$lib/Question.svelte';

  let { items, loggedIn } = $props();
</script>

{#if items}
  {#each items as item (item.id)}
    <Question {item} {loggedIn} />
  {/each}
{/if}
