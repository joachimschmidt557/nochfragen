<script>
  import { createEventDispatcher } from "svelte";
  import { _, t, format } from "svelte-i18n";

  const dispatch = createEventDispatcher();

  let questionText = "";

  async function submitQuestion() {
    await fetch(`api/questions`, {
      method: "POST",
      body: JSON.stringify({ text: questionText }),
    })
      .then((response) => {
        if (!response.ok) {
          throw new Error(
            $_("response.error.ask.serverreturn", {
              values: {
                status: response.status,
                statusText: response.statusText,
              },
            })
          );
        }

        questionText = "";
        dispatch("success", "");
      })
      .catch((error) => dispatch("error", error));
  }
</script>

<div class="list-group-item">
  <form on:submit|preventDefault={submitQuestion}>
    <label for="questionText" class="form-label">{$_("app.ask.title")}</label>
    <div class="d-flex justify-content-between">
      <input bind:value={questionText} class="form-control" id="questionText" />
      <button
        type="submit"
        class="btn btn-primary ms-2"
        disabled={questionText === ""}>{$_("app.ask.action")}</button
      >
    </div>
    <div id="moderationLabel" class="form-text">
      {$_("app.ask.moderationnotice")}
    </div>
  </form>
</div>
