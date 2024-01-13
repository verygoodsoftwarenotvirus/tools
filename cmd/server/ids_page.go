package main

import (
	"encoding/base64"
	"log/slog"
	"net/http"
	"text/template"
	"time"

	"github.com/rs/xid"
)

const (
	newIDAPIPath = "/api/ids/new"

	idsPageTemplate = `
		<h1>IDs</h1>
<select hx-post="/api/ids/new" hx-trigger="change" hx-target="#generated-id">
	<option></option>
	<option value="xid">xid</option>
</select>

<div id="generated-id"></div>
`

	xidGeneratedResultTemplate = `
<table id="idResultTable">
  <tr>
	<td style="text-align: left">ID</td>
    <td style="text-align: right"><button onClick="copyText()">Copy</button><input id="generatedIDValue" type="text" disabled value="{{ .ID }}" /></td>
  </tr>
  <tr>
	<td style="text-align: left">Time</td>
    <td style="text-align: right"><input type="text" disabled value="{{ .Time }}" /></td>
  </tr>
  <tr>
	<td style="text-align: left">Machine</td>
     <td style="text-align: right"><input type="text" disabled value="{{ .Machine }}" /></td>
  </tr>
  <tr>
	<td style="text-align: left">Pid</td>
    <td style="text-align: right"><input type="text" disabled value="{{ .Pid }}" /></td>
  </tr>
  <tr>
	<td style="text-align: left">Counter</td>
    <td style="text-align: right"><input type="text" disabled value="{{ .Counter }}" /></td>
  </tr>
</table>
<script>
	async function copyText() {
		const x = document.getElementById('generatedIDValue').value;
		await navigator.clipboard.writeText(x || '');
	}
</script>
`
)

type xidGeneratedResult struct {
	ID      string
	Time    time.Time
	Machine string
	Pid     uint16
	Counter int32
}

func buildIDsPageHandler(logger *slog.Logger) http.HandlerFunc {
	return func(res http.ResponseWriter, req *http.Request) {
		bp := &basePage{
			Title: "Home",
			Body:  idsPageTemplate,
		}

		if err := template.Must(template.New("base").Parse(baseTemplate)).Execute(res, bp); err != nil {
			logger.Error("failed to execute template", slog.Any("error", err))
		}
	}
}

func buildIDGenerationPageHandler(logger *slog.Logger) http.HandlerFunc {
	tmpl := template.Must(template.New("id-result").Parse(xidGeneratedResultTemplate))

	return func(res http.ResponseWriter, req *http.Request) {
		baseID := xid.New()

		result := &xidGeneratedResult{
			ID:      baseID.String(),
			Time:    baseID.Time(),
			Machine: base64.URLEncoding.EncodeToString(baseID.Machine()),
			Pid:     baseID.Pid(),
			Counter: baseID.Counter(),
		}

		// render the template to a string
		if err := tmpl.Execute(res, result); err != nil {
			logger.Error("failed to execute template", slog.Any("error", err))
			return
		}
	}
}
