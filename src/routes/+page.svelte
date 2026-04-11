<script>
  import * as bootstrap from 'bootstrap';
  import { onMount } from 'svelte';
  import { _, init, addMessages, getLocaleFromNavigator } from 'svelte-i18n';

  import Ask from '$lib/Ask.svelte';
  import List from '$lib/List.svelte';
  import SurveyList from '$lib/SurveyList.svelte';
  import CreateSurvey from '$lib/CreateSurvey.svelte';

  import Export from '$lib/modals/Export.svelte';

  import en from '$lib/locales/en.json';
  import de from '$lib/locales/de.json';

  import { PUBLIC_IMPRINT_URL, PUBLIC_PRIVACY_POLICY_URL } from '$env/static/public';

  addMessages('en', en);
  addMessages('de', de);

  let languages = [
    { id: 0, locale: 'us', text: `English` },
    { id: 1, locale: 'de', text: `Deutsch` }
  ];

  let selected = $state(0);

  languages.forEach((l) => {
    if (l.locale === getLocaleFromNavigator()) {
      selected = l.id;
    }
  });

  init({
    fallbackLocale: 'en',
    initialLocale: getLocaleFromNavigator()
  });

  function switchLanguage() {
    let s = languages[selected];
    init({
      fallbackLocale: 'en',
      initialLocale: s.locale
    });
  }

  onMount(() => {
    poll();
    getLoginStatus();
  });

  let updating = $state(true);
  let loggedIn = $state(false);

  let items = $state([]);
  let answeredItems = $state([]);
  let hiddenItems = $state([]);
  let hiddenAnsweredItems = $state([]);
  let surveyItems = $state([]);

  let connected = $state(true);
  let password = $state('');
  let passwordModalAlert = $state('');
  let deleteModalAlert = $state('');
  let alertSuccess = $state('');
  let alertDanger = $state('');

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
        fetch(`api/questions`),
        fetch(`api/surveys`)
      ]);

      connected = true;

      if (!questionsResponse.ok) {
        throw new ServerError($_('response.error.question.general'), statusCode);
      }
      if (!surveysResponse.ok) {
        throw new ServerError($_('response.error.survey.general'), statusCode);
      }

      const [questions, surveys] = [await questionsResponse.json(), await surveysResponse.json()];

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
        alertDanger = error;
      } else {
        // initial fetch failed
        connected = false;
      }

      updating = false;
    }
  }

  async function getLoginStatus() {
    try {
      const response = await fetch(`api/login`);
      const data = await response.json();
      loggedIn = data.loggedIn;
    } catch (error) {
      alertDanger = error;
    }
  }

  async function login(ev) {
    ev.preventDefault();

    try {
      const response = await fetch(`api/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ password: password })
      });

      if (response.status === 403) {
        throw new Error($_('response.error.password'));
      } else if (!response.ok) {
        throw new Error(
          $_('response.error.login.serverreturn', {
            values: {
              status: response.status,
              statusText: response.statusText
            }
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
      passwordModalAlert = error;
    }
  }

  async function logout() {
    try {
      const response = await fetch(`api/logout`, { method: 'POST' });

      if (!response.ok) {
        throw new Error($_('response.error.passwordlogout'));
      }

      loggedIn = false;
      updateQuestionsAndSurveys();
    } catch (error) {
      alertDanger = error;
    }
  }

  async function deleteAllQuestions() {
    try {
      const response = await fetch(`api/questions`, { method: 'DELETE' });

      if (!response.ok) {
        throw new Error($_('response.error.question.deleteall'));
      }

      items = [];
      deleteModalAlert = '';
      var deleteModal = bootstrap.Modal.getOrCreateInstance(
        document.getElementById('deleteModal'),
        {}
      );
      deleteModal.hide();
    } catch (error) {
      deleteModalAlert = error;
    }
  }

  async function submitSuccess() {
    alertSuccess = $_('response.success.question.submit');
    await updateQuestionsAndSurveys();
  }

  function submitError(error) {
    alertDanger = $_('response.error.question.submit', {
      values: { detail: error }
    });
  }

  function dismissAlertSuccess() {
    alertSuccess = '';
  }

  function dismissAlertDanger() {
    alertDanger = '';
  }

  function translateAlertDanger(error) {
    console.log(error.message);
    switch (error.message) {
      case 'NetworkError when attempting to fetch resource.':
        return 'response.error.type.network';
      default:
        // Could not translate in this case
        return 'response.error.type.network';
    }
  }

  // Source https://dev.to/jorik/country-code-to-flag-emoji-a21
  function getFlagEmoji(countryCode) {
    return countryCode
      .toUpperCase()
      .replace(/./g, (char) => String.fromCodePoint(127397 + char.charCodeAt()));
  }
</script>

<nav class="navbar">
  <div class="container">
    <span class="navbar-brand mb-0 h1">{$_('app.title')} </span>
    <span class="ms-auto">
      <select class="form-select" bind:value={selected} onchange={switchLanguage}>
        {#each languages as lang}
          {#if lang.id === 0}
            <option value={lang.id} selected="selected">
              {getFlagEmoji(lang.locale)}
              {lang.text}
            </option>
          {:else}
            <option value={lang.id} selected="">
              {getFlagEmoji(lang.locale)}
              {lang.text}
            </option>
          {/if}
        {/each}
      </select>
    </span>

    <span class="navbar-brand mb-0 h1">
      {#if loggedIn}
        <button type="button" onclick={logout} class="btn">{$_('app.moderator.logout')}</button>
      {:else}
        <button type="button" class="btn" data-bs-toggle="modal" data-bs-target="#loginModal"
          >{$_('app.moderator.login')}</button
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
        {$_(translateAlertDanger(alertDanger))}
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
          {$_('app.refresh')}
        </button>
        {#if !connected}
          <span class="text-center text-muted fst-italic">
            {$_('status.disconnected')}
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
            {$_('app.moderator.export')}
          </button>
          <button
            type="button"
            class="btn btn-outline-danger"
            data-bs-toggle="modal"
            data-bs-target="#deleteModal"
          >
            {$_('app.moderator.deleteall')}
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
      <Ask success={submitSuccess} error={submitError} />
      <List {items} {loggedIn} />
    </ul>

    {#if answeredItems.length > 0}
      <div class="mt-3">
        {$_('app.questions.answered')}
        <ul class="list-group">
          <List items={answeredItems} {loggedIn} />
        </ul>
      </div>
    {/if}

    {#if hiddenItems.length > 0}
      <div class="mt-3">
        {$_('app.questions.hidden')}
        <ul class="list-group">
          <List items={hiddenItems} {loggedIn} />
        </ul>
      </div>
    {/if}

    {#if hiddenAnsweredItems.length > 0}
      <div class="mt-3">
        Hidden and Answered
        <ul class="list-group">
          <List items={hiddenAnsweredItems} {loggedIn} />
        </ul>
      </div>
    {/if}
  </div>
  <div class="mt-3">
    <p class="text-center text-muted fst-italic">
      {$_('app.opensource')}
      <a href="https://github.com/joachimschmidt557/nochfragen" target="_blank">open source</a>.

      <a href={PUBLIC_IMPRINT_URL} rel="external" target="_blank">{$_('app.imprint')}</a>
      <a href={PUBLIC_PRIVACY_POLICY_URL} rel="external" target="_blank"
        >{$_('app.privacy_policy')}</a
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
          {$_('app.login.title')}
        </h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <form onsubmit={login}>
        <div class="modal-body">
          {#if passwordModalAlert !== ''}
            <div class="alert alert-danger" role="alert">
              {passwordModalAlert}
            </div>
          {/if}
          <label for="password" class="form-label">{$_('app.login.passwordtitle')}</label>
          <input bind:value={password} type="password" class="form-control" id="password" />
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-bs-dismiss="modal"
            >{$_('app.login.exit')}</button
          >
          <button type="submit" class="btn btn-primary">{$_('app.login.action')}</button>
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
          {$_('app.deleteallmodal.title')}
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
          {$_('app.deleteallmodal.warning')}
        </p>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-primary" data-bs-dismiss="modal"
          >{$_('app.deleteallmodal.exit')}</button
        >
        <button type="submit" class="btn btn-danger" onclick={deleteAllQuestions}
          >{$_('app.deleteallmodal.action')}</button
        >
      </div>
    </div>
  </div>
</div>
<Export />
