<script>
  import * as bootstrap from "bootstrap";

  let includeHidden = false;
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
        <h5 class="modal-title" id="exportModalLabel">Export questions</h5>
        <button
          type="button"
          class="btn-close"
          data-bs-dismiss="modal"
          aria-label="Close"
        />
      </div>
      <div class="modal-body">
        <p>You can export all questions as a CSV file.</p>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal"
          >Close</button
        >
        <a type="button" class="btn btn-primary" role="button" href="api/export"
          >Export</a
        >
      </div>
    </div>
  </div>
</div>
