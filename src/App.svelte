<script>
  import * as bootstrap from "bootstrap";
  import { onMount } from "svelte";

  import Ask from "./Ask.svelte";
  import Item from "./Item.svelte";
  import List from "./List.svelte";
  import SurveyList from "./SurveyList.svelte";
  import CreateSurvey from "./CreateSurvey.svelte";
  import Export from "./Export.svelte";

  onMount(() => {
    poll();
    getLoginStatus();
  });

  let updating = true;
  let loggedIn = false;

  let items = [];
  let answeredItems = [];
  let hiddenItems = [];
  let surveyItems = [];

  let connected = true;
  let password = "";
  let passwordModalAlert = "";
  let deleteModalAlert = "";
  let alertSuccess = "";
  let alertDanger = "";

  class ServerError extends Error {
    constructor(message, statusCode) {
      super(message);
      this.statusCode = statusCode;
    }
  }

  async function poll() {
    await updateQuestionsAndSurveys();
    setTimeout(poll, 3000);
  }

  function questionOrder(a, b) {
    const answering = 3;
    const answered = 4;

    if (a.state === answering) {
      return -1;
    } else if (b.state === answering) {
      return 1;
    } else if (a.state === answered) {
      return 1;
    } else if (b.state === answered) {
      return -1;
    } else {
      return b.upvotes - a.upvotes;
    }
  }

  async function updateQuestionsAndSurveys() {
    updating = true;
    await Promise.all([fetch(`api/questions`), fetch(`api/surveys`)])
      .then(async ([questions, surveys]) => {
        connected = true;

        if (!questions.ok) {
          throw new ServerError(`Error fetching questions`, statusCode);
        }
        if (!surveys.ok) {
          throw new ServerError(`Error fetching surveys`, statusCode);
        }

        return [await questions.json(), await surveys.json()];
      })
      .then(([questions, surveys]) => {
        const hidden = 0;
        const answered = 4;

        questions.sort(questionOrder);
        items = questions.filter(
          (x) => x.state !== answered && x.state !== hidden
        );
        answeredItems = questions.filter((x) => x.state === answered);
        hiddenItems = questions.filter((x) => x.state === hidden);
        surveyItems = surveys;

        updating = false;
      })
      .catch((error) => {
        if (error instanceof ServerError) {
          alertDanger = error;
        } else {
          // initial fetch failed
          connected = false;
        }

        updating = false;
      });
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
          throw new Error(
            "Error while logging in. Server returned ${response.status} ${response.statusText}"
          );
        }

        loggedIn = true;
        passwordModalAlert = "";
        password = "";

        var loginModal = bootstrap.Modal.getOrCreateInstance(
          document.getElementById("loginModal"),
          {}
        );
        loginModal.hide();
        updateQuestionsAndSurveys();
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
        updateQuestionsAndSurveys();
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
    alertSuccess = "Question submitted";
    await updateQuestionsAndSurveys();
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

    <div class="pb-2 d-flex justify-content-between">
      <div>
        <button
          type="button"
          on:click={updateQuestionsAndSurveys}
          class="btn btn-outline-primary"
          disabled={updating}
        >
          Refresh
        </button>
        {#if !connected}
          <span class="text-center text-muted fst-italic"> disconnected </span>
        {/if}
      </div>
      {#if loggedIn}
        <div class="btn-group" role="group" aria-label="Controls">
          <button
            type="button"
            class="btn btn-outline-secondary"
            data-bs-toggle="modal"
            data-bs-target="#exportModal"
          >
            Export
          </button>
          <button
            type="button"
            class="btn btn-outline-danger"
            data-bs-toggle="modal"
            data-bs-target="#deleteModal"
          >
            Delete all questions
          </button>
        </div>
      {/if}
    </div>

    <ul class="list-group pb-2">
      {#if loggedIn}
        <CreateSurvey />
      {/if}
      <SurveyList {surveyItems} {loggedIn} />
    </ul>

    <ul class="list-group">
      <Ask on:success={submitSuccess} on:error={submitError} />
      <List {items} {loggedIn} />
    </ul>

    {#if answeredItems.length > 0}
      <div class="mt-3">
        Answered questions
        <ul class="list-group">
          <List items={answeredItems} {loggedIn} />
        </ul>
      </div>
    {/if}

    {#if hiddenItems.length > 0}
      <div class="mt-3">
        Hidden questions
        <ul class="list-group">
          <List items={hiddenItems} {loggedIn} />
        </ul>
      </div>
    {/if}
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
