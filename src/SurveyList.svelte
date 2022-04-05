<script>
  import Survey from "./Survey.svelte";

  export let surveyItems;
  export let loggedIn;
</script>

{#if surveyItems}
  {#each surveyItems as item (item.id)}
    <Survey {item} {loggedIn} />
  {/each}
{/if}
