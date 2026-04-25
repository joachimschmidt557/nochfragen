<script lang="ts">
  import * as bootstrap from 'bootstrap';
  import { onMount } from 'svelte';

  import type { Pathname } from '$app/types';
  import { page } from '$app/state';
  import { resolve } from '$app/paths';
  import { locales, localizeHref } from '$lib/paraglide/runtime';
  import { m } from '$lib/paraglide/messages.js';

  import type { Question, Survey } from '$lib/types';

  import CreateQuestion from '$lib/CreateQuestion.svelte';
  import QuestionList from '$lib/QuestionList.svelte';
  import CreateSurvey from '$lib/CreateSurvey.svelte';
  import SurveyList from '$lib/SurveyList.svelte';

  import Export from '$lib/modals/Export.svelte';

  import { PUBLIC_IMPRINT_URL, PUBLIC_PRIVACY_POLICY_URL } from '$env/static/public';

  onMount(() => {
    poll();
    getLoginStatus();
  });

  let updating = $state(true);
  let loggedIn = $state(false);
  let openidConnectAvailable = $state(false);

  let items: Question[] = $state([]);
  let answeredItems: Question[] = $state([]);
  let hiddenItems: Question[] = $state([]);
  let hiddenAnsweredItems: Question[] = $state([]);
  let surveyItems: Survey[] = $state([]);

  let connected = $state(true);
  let password = $state('');
  let passwordModalAlert = $state('');
  let deleteModalAlert = $state('');
  let alertSuccess = $state('');
  let alertDanger = $state('');

  class ServerError extends Error {
    statusCode: number;

    constructor(message: string, statusCode: number) {
      super(message);
      this.statusCode = statusCode;
    }
  }

  async function poll() {
    await updateQuestionsAndSurveys();
    setTimeout(poll, 3000);
  }

  function questionOrder(a: Question, b: Question) {
    const answering = 2;
    const answered = 3;

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

    try {
      const [questionsResponse, surveysResponse] = await Promise.all([
        fetch(`/api/questions`),
        fetch(`/api/surveys`)
      ]);

      connected = true;

      if (!questionsResponse.ok) {
        throw new ServerError(m.response_error_question_general(), questionsResponse.status);
      }
      if (!surveysResponse.ok) {
        throw new ServerError(m.response_error_survey_general(), surveysResponse.status);
      }

      const [questions, surveys] = [
        (await questionsResponse.json()) as Question[],
        (await surveysResponse.json()) as Survey[]
      ];

      const hidden = 0;
      const answered = 3;
      const hiddenAnswered = 4;

      questions.sort(questionOrder);
      items = questions.filter(
        (x) => x.state !== answered && x.state !== hidden && x.state !== hiddenAnswered
      );
      answeredItems = questions.filter((x) => x.state === answered);
      hiddenItems = questions.filter((x) => x.state === hidden);
      hiddenAnsweredItems = questions.filter((x) => x.state === hiddenAnswered);
      surveyItems = surveys;

      updating = false;
    } catch (error) {
      if (error instanceof ServerError) {
        alertDanger = error.message;
      } else {
        // initial fetch failed
        connected = false;
      }

      updating = false;
    }
  }

  async function getLoginStatus() {
    try {
      const response = await fetch(`/api/login`);
      const data = await response.json();
      loggedIn = data.loggedIn;
      openidConnectAvailable = data.openidConnectAvailable;
    } catch (error) {
      alertDanger = `${error}`;
    }
  }

  async function login(ev: SubmitEvent) {
    ev.preventDefault();

    try {
      const response = await fetch(`/api/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ password: password })
      });

      if (response.status === 403) {
        throw new Error(m.response_error_password());
      } else if (!response.ok) {
        throw new Error(
          m.response_error_login_serverreturn({
            status: response.status,
            statusText: response.statusText
          })
        );
      }

      loggedIn = true;
      passwordModalAlert = '';
      password = '';

      var loginModal = bootstrap.Modal.getOrCreateInstance(
        document.getElementById('loginModal'),
        {}
      );
      loginModal.hide();
      updateQuestionsAndSurveys();
    } catch (error) {
      passwordModalAlert = `${error}`;
    }
  }

  async function logout() {
    try {
      const response = await fetch(`/api/logout`, { method: 'POST' });

      if (!response.ok) {
        throw new Error(m.response_error_logout());
      }

      loggedIn = false;
      updateQuestionsAndSurveys();
    } catch (error) {
      alertDanger = `${error}`;
    }
  }

  async function deleteAllQuestions() {
    try {
      const response = await fetch(`/api/questions`, { method: 'DELETE' });

      if (!response.ok) {
        throw new Error(m.response_error_question_deleteall());
      }

      items = [];
      deleteModalAlert = '';
      var deleteModal = bootstrap.Modal.getOrCreateInstance(
        document.getElementById('deleteModal'),
        {}
      );
      deleteModal.hide();
    } catch (error) {
      deleteModalAlert = `${error}`;
    }
  }

  async function submitSuccess() {
    alertSuccess = m.response_success_question_submit();
    await updateQuestionsAndSurveys();
  }

  function submitError(detail: string) {
    alertDanger = m.response_error_question_submit({ detail });
  }

  function dismissAlertSuccess() {
    alertSuccess = '';
  }

  function dismissAlertDanger() {
    alertDanger = '';
  }

  // Source https://dev.to/jorik/country-code-to-flag-emoji-a21
  function getFlagEmoji(locale: string) {
    let countryCode = '';
    if (locale == 'en') {
      countryCode = 'us';
    } else if (locale == 'de') {
      countryCode = 'de';
    }

    return countryCode
      .toUpperCase()
      .replace(/./g, (char) => String.fromCodePoint(127397 + char.charCodeAt(0)));
  }
</script>

<nav class="navbar">
  <div class="container">
    <span class="navbar-brand mb-0 h1">{m.app_title()}</span>
    <span class="ms-auto">
      <div class="dropdown">
        <button
          class="btn dropdown-toggle"
          type="button"
          id="languageDropdownMenuButton"
          data-bs-toggle="dropdown"
          aria-expanded="false"
        >
          Language
        </button>
        <ul class="dropdown-menu" aria-labelledby="languageDropdownMenuButton">
          {#each locales as locale}
            <li>
              <a
                class="dropdown-item"
                href={resolve(localizeHref(page.url.pathname, { locale }) as Pathname)}
                data-sveltekit-reload
              >
                {getFlagEmoji(locale)}
                {locale}
              </a>
            </li>
          {/each}
        </ul>
      </div>
    </span>

    <span class="navbar-brand mb-0 h1">
      {#if loggedIn}
        <button type="button" onclick={logout} class="btn">{m.app_moderator_logout()}</button>
      {:else}
        <button type="button" class="btn" data-bs-toggle="modal" data-bs-target="#loginModal"
          >{m.app_moderator_login()}</button
        >
      {/if}
    </span>
  </div>
</nav>
<main>
  <div class="container">
    {#if alertSuccess !== ''}
      <div class="alert alert-success alert-dismissible" role="alert">
        {alertSuccess}
        <button onclick={dismissAlertSuccess} type="button" class="btn-close" aria-label="Close"
        ></button>
      </div>
    {/if}

    {#if alertDanger !== ''}
      <div class="alert alert-danger alert-dismissible" role="alert">
        {alertDanger}
        <button onclick={dismissAlertDanger} type="button" class="btn-close" aria-label="Close"
        ></button>
      </div>
    {/if}

    <div class="pb-2 d-flex justify-content-between">
      <div>
        <button
          type="button"
          onclick={updateQuestionsAndSurveys}
          class="btn btn-outline-primary"
          disabled={updating}
        >
          {m.app_refresh()}
        </button>
        {#if !connected}
          <span class="text-center text-muted fst-italic">
            {m.status_disconnected()}
          </span>
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
            {m.app_moderator_export()}
          </button>
          <button
            type="button"
            class="btn btn-outline-danger"
            data-bs-toggle="modal"
            data-bs-target="#deleteModal"
          >
            {m.app_moderator_deleteall()}
          </button>
        </div>
      {/if}
    </div>

    <ul class="list-group pb-2">
      {#if loggedIn}
        <!-- TODO handle success and error -->
        <CreateSurvey success={() => {}} error={() => {}} />
      {/if}
      <SurveyList {surveyItems} {loggedIn} />
    </ul>

    <ul class="list-group">
      <CreateQuestion success={submitSuccess} error={submitError} />
      <QuestionList {items} {loggedIn} />
    </ul>

    {#if answeredItems.length > 0}
      <div class="mt-3">
        {m.app_questions_answered()}
        <ul class="list-group">
          <QuestionList items={answeredItems} {loggedIn} />
        </ul>
      </div>
    {/if}

    {#if hiddenItems.length > 0}
      <div class="mt-3">
        {m.app_questions_hidden()}
        <ul class="list-group">
          <QuestionList items={hiddenItems} {loggedIn} />
        </ul>
      </div>
    {/if}

    {#if hiddenAnsweredItems.length > 0}
      <div class="mt-3">
        Hidden and Answered
        <ul class="list-group">
          <QuestionList items={hiddenAnsweredItems} {loggedIn} />
        </ul>
      </div>
    {/if}
  </div>
  <div class="mt-3">
    <p class="text-center text-muted fst-italic">
      {m.app_opensource()}
      <a href="https://github.com/joachimschmidt557/nochfragen" target="_blank">open source</a>.

      <a href={PUBLIC_IMPRINT_URL} rel="external" target="_blank">{m.app_imprint()}</a>
      <a href={PUBLIC_PRIVACY_POLICY_URL} rel="external" target="_blank">{m.app_privacy_policy()}</a
      >
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
        <h5 class="modal-title" id="loginModalLabel">
          {m.app_login_title()}
        </h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <form onsubmit={login}>
        <div class="modal-body">
          {#if openidConnectAvailable}
            <div class="mb-3">
              <a class="btn btn-primary" href="/api/openid-connect/login">Sign in with SSO</a>
            </div>

            <hr />
          {/if}

          <div class="mb-3">
            {#if passwordModalAlert !== ''}
              <div class="alert alert-danger" role="alert">
                {passwordModalAlert}
              </div>
            {/if}
            <label for="password" class="form-label">{m.app_login_passwordtitle()}</label>
            <input bind:value={password} type="password" class="form-control" id="password" />
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-bs-dismiss="modal"
            >{m.app_login_exit()}</button
          >
          <button type="submit" class="btn btn-primary">{m.app_login_action()}</button>
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
        <h5 class="modal-title" id="deleteModalLabel">
          {m.app_deleteallmodal_title()}
        </h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        {#if deleteModalAlert !== ''}
          <div class="alert alert-danger" role="alert">
            {deleteModalAlert}
          </div>
        {/if}
        <p>
          {m.app_deleteallmodal_warning()}
        </p>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-primary" data-bs-dismiss="modal"
          >{m.app_deleteallmodal_exit()}</button
        >
        <button type="submit" class="btn btn-danger" onclick={deleteAllQuestions}
          >{m.app_deleteallmodal_action()}</button
        >
      </div>
    </div>
  </div>
</div>
<Export />
