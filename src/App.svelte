<script>
  import * as bootstrap from "bootstrap";
  import { onMount } from "svelte";

  import Ask from "./Ask.svelte";
  import List from "./List.svelte";
  import Export from "./Export.svelte";

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
  let deleteModalAlert = "";
  let alertSuccess = "";
  let alertDanger = "";

  async function updateQuestions() {
    updating = true;
    await fetch(`api/questions`)
      .then((response) => {
        if (!response.ok) {
          throw new Error(
            `Error fetching questions. Server returned ${response.status} ${response.statusText}.`
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
    await fetch(`api/login`)
      .then((response) => response.json())
      .then((data) => {
        loggedIn = data.loggedIn;
      })
      .catch((error) => (alertDanger = error));
  }

  async function login() {
    await fetch(`api/login`, {
      method: "POST",
      body: JSON.stringify({ password: password }),
    })
      .then((response) => {
        if (response.status === 403) {
          throw new Error("Wrong password");
        } else if (!response.ok) {
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
    await fetch(`api/logout`, { method: "POST" })
      .then((response) => {
        if (!response.ok) {
          throw new Error("Error while logging out");
        }

        loggedIn = false;
        updateQuestions();
      })
      .catch((error) => (alertDanger = error));
  }

  async function deleteAllQuestions() {
    await fetch(`api/questions`, { method: "DELETE" })
      .then((response) => {
        if (!response.ok) {
          throw new Error("Error while deleting all questions");
        }

        items = [];
        deleteModalAlert = "";
        var deleteModal = bootstrap.Modal.getOrCreateInstance(
          document.getElementById("deleteModal"),
          {}
        );
        deleteModal.hide();
      })
      .catch((error) => (deleteModalAlert = error));
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

<nav class="navbar">
  <div class="container">
    <span class="navbar-brand mb-0 h1">Questions</span>
    {#if loggedIn}
      <button type="button" on:click={logout} class="btn">Logout</button>
    {:else}
      <button
        type="button"
        class="btn"
        data-bs-toggle="modal"
        data-bs-target="#loginModal">Moderator Login</button
      >
    {/if}
  </div>
</nav>
<main>
  <div class="container">
    {#if alertSuccess !== ""}
      <div class="alert alert-success alert-dismissible" role="alert">
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
      <div class="alert alert-danger alert-dismissible" role="alert">
        {alertDanger}
        <button
          on:click={dismissAlertDanger}
          type="button"
          class="btn-close"
          aria-label="Close"
        />
      </div>
    {/if}

    <div class="pb-2">
      <div class="btn-group" role="group" aria-label="Controls">
        <button
          type="button"
          on:click={updateQuestions}
          class="btn btn-outline-primary"
          disabled={updating}
        >
          Refresh
        </button>
        {#if loggedIn}
          <button
            type="button"
            class="btn btn-outline-danger"
            data-bs-toggle="modal"
            data-bs-target="#deleteModal"
          >
            Delete all questions
          </button>
          <button
            type="button"
            class="btn btn-outline-primary"
            data-bs-toggle="modal"
            data-bs-target="#exportModal"
          >
            Export
          </button>
        {/if}
      </div>
    </div>
    <ul class="list-group">
      <Ask on:success={submitSuccess} on:error={submitError} />
      <List {items} {loggedIn} />
    </ul>
  </div>
  <div class="mt-3">
    <p class="text-center text-muted fst-italic">
      This software is <a href="https://github.com/joachimschmidt557/nochfragen"
        >open source</a
      >.
    </p>
  </div>
</main>

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
            <div class="alert alert-danger" role="alert">
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
<div
  class="modal fade"
  id="deleteModal"
  tabindex="-1"
  aria-labelledby="deleteModalLabel"
  aria-hidden="true"
>
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="deleteModalLabel">Delete all questions</h5>
        <button
          type="button"
          class="btn-close"
          data-bs-dismiss="modal"
          aria-label="Close"
        />
      </div>
      <div class="modal-body">
        {#if deleteModalAlert !== ""}
          <div class="alert alert-danger" role="alert">
            {deleteModalAlert}
          </div>
        {/if}
        <p>
          Are you sure you want to delete all questions? This cannot be undone.
        </p>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-primary" data-bs-dismiss="modal"
          >Close</button
        >
        <button
          type="submit"
          class="btn btn-danger"
          on:click={deleteAllQuestions}>Delete</button
        >
      </div>
    </div>
  </div>
</div>
<Export />
