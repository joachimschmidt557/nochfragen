<script lang="ts">
  import { m } from '$lib/paraglide/messages.js';

  interface Props {
    onDeleteAll: () => void;
    askQuestionsEnabled: boolean;
  }

  let { onDeleteAll, askQuestionsEnabled = $bindable() }: Props = $props();

  let deleteAlert = $state('');
  let deleteConfirm = $state(false);

  let settingAlert = $state('');

  let currentPassword = $state('');
  let newPassword = $state('');
  let confirmPassword = $state('');
  let passwordAlert = $state('');
  let passwordSuccess = $state('');

  async function toggleAskQuestions(event: Event) {
    const target = event.target as HTMLInputElement;
    const newValue = target.checked;
    const previousValue = askQuestionsEnabled;

    askQuestionsEnabled = newValue;

    try {
      const response = await fetch(`/api/settings/ask_questions_enabled`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ enabled: newValue })
      });

      if (!response.ok) {
        throw new Error(`Server returned ${response.status} ${response.statusText}`);
      }

      settingAlert = '';
    } catch (error) {
      askQuestionsEnabled = previousValue;
      target.checked = previousValue;
      const toggleError = `${error}`;
      settingAlert = toggleError;
    }
  }

  function confirmDelete() {
    deleteConfirm = true;
  }

  function cancelDelete() {
    deleteConfirm = false;
  }

  async function changePassword(ev: SubmitEvent) {
    ev.preventDefault();

    if (newPassword === '') {
      passwordAlert = m.app_changepassword_error_empty();
      passwordSuccess = '';
      return;
    }

    if (newPassword !== confirmPassword) {
      passwordAlert = m.app_changepassword_error_mismatch();
      passwordSuccess = '';
      return;
    }

    try {
      const response = await fetch(`/api/settings/moderator_password`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ currentPassword, newPassword })
      });

      if (response.status === 403) {
        throw new Error(m.app_changepassword_error_wrongcurrent());
      } else if (!response.ok) {
        throw new Error(
          m.app_changepassword_error_general({
            status: response.status,
            statusText: response.statusText
          })
        );
      }

      passwordAlert = '';
      passwordSuccess = m.app_changepassword_success();
      currentPassword = '';
      newPassword = '';
      confirmPassword = '';
    } catch (error) {
      passwordSuccess = '';
      passwordAlert = `${error}`;
    }
  }

  async function deleteAllQuestions() {
    try {
      const response = await fetch(`/api/questions`, { method: 'DELETE' });

      if (!response.ok) {
        throw new Error(m.response_error_question_deleteall());
      }

      deleteAlert = '';
      onDeleteAll();
    } catch (error) {
      deleteAlert = `${error}`;
    }
  }
</script>

<div
  class="modal fade"
  id="settingsModal"
  tabindex="-1"
  aria-labelledby="settingsModalLabel"
  aria-hidden="true"
>
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="settingsModalLabel">
          {m.app_settings()}
        </h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <div class="mb-4">
          <h6 class="mb-1">{m.app_ask_settings_title()}</h6>
          <p class="mb-2">{m.app_ask_settings_description()}</p>
          <div class="form-check form-switch">
            <input
              class="form-check-input"
              type="checkbox"
              role="switch"
              id="askQuestionsSwitch"
              checked={askQuestionsEnabled}
              onchange={toggleAskQuestions}
            />
            <label class="form-check-label" for="askQuestionsSwitch">
              {m.app_ask_settings_label()}
            </label>
          </div>
          {#if settingAlert !== ''}
            <div class="alert alert-danger mt-2" role="alert">
              {settingAlert}
            </div>
          {/if}
        </div>
        <hr />
        <div class="mb-4">
          <h6 class="mb-1">{m.app_exportmodal_title()}</h6>
          <p class="mb-2">{m.app_exportmodal_description()}</p>
          <a
            type="button"
            class="btn btn-sm btn-primary"
            role="button"
            href="/api/export"
            rel="external"
          >
            {m.app_exportmodal_action()}
          </a>
        </div>
        <hr />
        <div class="mb-4">
          <h6 class="mb-1">{m.app_changepassword_title()}</h6>
          <p class="mb-2">{m.app_changepassword_description()}</p>
          <form onsubmit={changePassword}>
            <div class="mb-3">
              <label for="currentPassword" class="form-label">
                {m.app_changepassword_currentlabel()}
              </label>
              <input
                bind:value={currentPassword}
                type="password"
                class="form-control"
                id="currentPassword"
                autocomplete="current-password"
              />
            </div>
            <div class="mb-3">
              <label for="newPassword" class="form-label">
                {m.app_changepassword_newlabel()}
              </label>
              <input
                bind:value={newPassword}
                type="password"
                class="form-control"
                id="newPassword"
                autocomplete="new-password"
              />
            </div>
            <div class="mb-3">
              <label for="confirmPassword" class="form-label">
                {m.app_changepassword_confirmlabel()}
              </label>
              <input
                bind:value={confirmPassword}
                type="password"
                class="form-control"
                id="confirmPassword"
                autocomplete="new-password"
              />
            </div>
            <button type="submit" class="btn btn-sm btn-primary">
              {m.app_changepassword_action()}
            </button>
          </form>
          {#if passwordAlert !== ''}
            <div class="alert alert-danger mt-2" role="alert">
              {passwordAlert}
            </div>
          {/if}
          {#if passwordSuccess !== ''}
            <div class="alert alert-success mt-2" role="alert">
              {passwordSuccess}
            </div>
          {/if}
        </div>
        <hr />
        <div>
          <h6 class="mb-1">{m.app_deleteallmodal_title()}</h6>
          {#if deleteConfirm}
            <div class="alert alert-danger" role="alert">
              {m.app_deleteallmodal_warning()}
            </div>
            <div class="d-flex gap-2">
              <button type="button" class="btn btn-sm btn-danger" onclick={deleteAllQuestions}>
                {m.app_deleteallmodal_confirm()}
              </button>
              <button type="button" class="btn btn-sm btn-secondary" onclick={cancelDelete}>
                {m.app_questions_item_edit_cancel()}
              </button>
            </div>
          {:else}
            <button type="button" class="btn btn-sm btn-danger" onclick={confirmDelete}>
              {m.app_deleteallmodal_action()}
            </button>
          {/if}
          {#if deleteAlert !== ''}
            <div class="alert alert-danger mt-2" role="alert">
              {deleteAlert}
            </div>
          {/if}
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">
          {m.app_deleteallmodal_exit()}
        </button>
      </div>
    </div>
  </div>
</div>
