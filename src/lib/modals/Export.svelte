<script lang="ts">
  import { m } from '$lib/paraglide/messages.js';
</script>

<div
  class="modal fade"
  id="exportModal"
  tabindex="-1"
  aria-labelledby="exportModalLabel"
  aria-hidden="true"
>
  <div class="modal-dialog">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="exportModalLabel">
          {m.app_exportmodal_title()}
        </h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <p>{m.app_exportmodal_description()}</p>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">
          {m.app_exportmodal_exit()}
        </button>
        <a type="button" class="btn btn-primary" role="button" href="/api/export" rel="external">
          {m.app_exportmodal_action()}
        </a>
      </div>
    </div>
  </div>
</div>
