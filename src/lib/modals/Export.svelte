<script>
  import * as bootstrap from 'bootstrap';
  import { _, t, format } from 'svelte-i18n';
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
          {$_('app.exportmodal.title')}
        </h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <p>{$_('app.exportmodal.description')}</p>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal"
          >{$_('app.exportmodal.exit')}</button
        >
        <a type="button" class="btn btn-primary" role="button" href="api/export" rel="external"
          >{$_('app.exportmodal.action')}</a
        >
      </div>
    </div>
  </div>
</div>
