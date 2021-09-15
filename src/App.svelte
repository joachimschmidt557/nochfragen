<script>
  import { onMount } from "svelte";

  import Ask from "./Ask.svelte";
  import List from "./List.svelte";

  onMount(() => {
    const interval = setInterval(() => {
      updateQuestions();
    }, 3000);

    updateQuestions();
    getLoginStatus();

    return () => clearInterval(interval);
  });

  let updating = true;
  let loggedIn = false;
  let items = [];
  let password = "";
  let passwordModalAlert = "";
  let alertSuccess = "";
  let alertDanger = "";

  async function updateQuestions() {
    updating = true;
    await fetch(`/api/questions`)
      .then((response) => {
        if (response.status !== 200) {
          throw new Error(
            `Error fetching questions. Server returned ${response.status}.`
          );
        }

        return response.json();
      })
      .then((data) => {
        data.sort((a, b) => b.upvotes - a.upvotes);
        items = data;
        updating = false;
      })
      .catch((error) => (alertDanger = error));
  }

  async function getLoginStatus() {
    await fetch(`/api/login`)
      .then((response) => response.json())
      .then((data) => {
        loggedIn = data.loggedIn;
      })
      .catch((error) => (alertDanger = error));
  }

  async function login() {
    await fetch(`/api/login`, {
      method: "POST",
      body: JSON.stringify({ password: password }),
    })
      .then((response) => {
        if (response.status === 403) {
          throw new Error("Wrong password");
        } else if (response.status !== 200) {
          throw new Error("Error while logging in");
        }

        loggedIn = true;
        passwordModalAlert = "";
        password = "";

        var loginModal = bootstrap.Modal.getOrCreateInstance(
          document.getElementById("loginModal"),
          {}
        );
        loginModal.hide();
        updateQuestions();
      })
      .catch((error) => (passwordModalAlert = error));
  }

  async function logout() {
    await fetch(`/api/logout`, { method: "POST" })
      .then(() => {
        loggedIn = false;
        updateQuestions();
      })
      .catch((error) => (alertDanger = error));
  }

  async function submitSuccess() {
    alertSuccess = "Question submitted successfully";
    await updateQuestions();
  }

  function submitError(event) {
    alertDanger = `Error submitting question: ${event.detail}`;
  }

  function dismissAlertSuccess() {
    alertSuccess = "";
  }

  function dismissAlertDanger() {
    alertDanger = "";
  }
</script>

<main>
  <div class="container">
    <h1>Questions</h1>

    {#if alertSuccess !== ""}
      <div class="alert alert-success alert-dismissable" role="alert">
        {alertSuccess}
        <button
          on:click={dismissAlertSuccess}
          type="button"
          class="btn-close"
          aria-label="Close"
        />
      </div>
    {/if}

    {#if alertDanger !== ""}
      <div class="alert alert-danger alert-dismissable" role="alert">
        {alertDanger}
        <button
          on:click={dismissAlertDanger}
          type="button"
          class="btn-close"
          aria-label="Close"
        />
      </div>
    {/if}

    <button
      type="button"
      on:click={updateQuestions}
      class="btn"
      disabled={updating}
    >
      {#if updating}
        <span
          class="spinner-border spinner-border-sm"
          role="status"
          aria-hidden="true"
        />
        Loading...
      {:else}
        Refresh
      {/if}
    </button>
    <ul class="list-group">
      <Ask on:success={submitSuccess} on:error={submitError} />
      <List {items} {loggedIn} />
    </ul>
    {#if loggedIn}
      <button type="button" on:click={logout} class="btn">Log out</button>
    {:else}
      <button
        type="button"
        class="btn"
        data-bs-toggle="modal"
        data-bs-target="#loginModal">Log in</button
      >
    {/if}
  </div>

  <div
    class="modal fade"
    id="loginModal"
    tabindex="-1"
    aria-labelledby="loginModalLabel"
    aria-hidden="true"
  >
    <div class="modal-dialog">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title" id="loginModalLabel">Login</h5>
          <button
            type="button"
            class="btn-close"
            data-bs-dismiss="modal"
            aria-label="Close"
          />
        </div>
        <form on:submit|preventDefault={login}>
          <div class="modal-body">
            {#if passwordModalAlert !== ""}
              <div class="alert alert-warning" role="alert">
                {passwordModalAlert}
              </div>
            {/if}
            <label for="password" class="form-label">Password</label>
            <input
              bind:value={password}
              type="password"
              class="form-control"
              id="password"
            />
          </div>
          <div class="modal-footer">
            <button
              type="button"
              class="btn btn-secondary"
              data-bs-dismiss="modal">Close</button
            >
            <button type="submit" class="btn btn-primary">Login</button>
          </div>
        </form>
      </div>
    </div>
  </div>
</main>
