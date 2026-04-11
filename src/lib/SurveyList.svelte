<script lang="ts">
  import SurveyComponent from '$lib/Survey.svelte';
  import type { Survey } from './types';

  interface Props {
    surveyItems: Survey[];
    loggedIn: boolean;
  }

  let { surveyItems, loggedIn }: Props = $props();
</script>

{#if surveyItems}
  {#each surveyItems as item (item.id)}
    <SurveyComponent {item} {loggedIn} />
  {/each}
{/if}
