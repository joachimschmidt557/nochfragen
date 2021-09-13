<script>
  import Item from "./Item.svelte";

  export let items;
  export let loggedIn;
</script>

{#if items}
  {#each items as item (item.id)}
    <Item {item} {loggedIn} />
  {/each}
{/if}
