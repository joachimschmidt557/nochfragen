<script>
  import * as bootstrap from "bootstrap";

  let exportModalAlert = "";
  let includeHidden = false;

  async function exportQuestions() {
    await fetch(`api/export`, {
      method: "GET",
      body: JSON.stringify({ includeHidden: includeHidden }),
    })
      .then((response) => {
        if (response.status !== 200) {
          throw new Error("Error while exporting questions");
        }

        exportModalAlert = "";
        var exportModal = bootstrap.Modal.getOrCreateInstance(
          document.getElementById("exportModal"),
          {}
        );
        exportModal.hide();
      })
      .catch((error) => (exportModalAlert = error));
  }
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
        {#if exportModalAlert !== ""}
          <div class="alert alert-danger" role="alert">
            {exportModalAlert}
          </div>
        {/if}
        <p>You can export all questions as a plain text file.</p>
        <div class="form-check form-switch">
          <input
            bind:checked={includeHidden}
            class="form-check-input"
            type="checkbox"
            id="includeHidden"
          />
          <label class="form-check-label" for="includeHidden"
            >Include hidden questions</label
          >
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal"
          >Close</button
        >
        <a
          type="button"
          class="btn btn-primary"
          role="button"
          href={includeHidden ? "api/exportall" : "api/export"}>Export</a
        >
      </div>
    </div>
  </div>
</div>
