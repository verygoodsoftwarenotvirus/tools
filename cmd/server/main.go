package main

import (
	"log/slog"
	"net/http"
	"os"
	"text/template"
)

const (
	baseTemplate = `<!DOCTYPE html>
<html lang="en">
   <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>{{ .Title }}</title>
      <script src="https://unpkg.com/htmx.org@1.9.10"></script>
      <style>
         /* from https://www.joshwcomeau.com/css/custom-css-reset/ */
         *, *::before, *::after {
           box-sizing: border-box;
         }
         * {
           margin: 0;
         }
         body {
           line-height: 1.5;
           -webkit-font-smoothing: antialiased;
         }
         img, picture, video, canvas, svg {
           display: block;
           max-width: 100%;
         }
         input, button, textarea, select {
           font: inherit;
         }
         p, h1, h2, h3, h4, h5, h6 {
           overflow-wrap: break-word;
         }
         #root, #__next {
           isolation: isolate;
         }
      </style>
   </head>
   <body>
      {{ .Body }}
   </body>
</html>
`

	indexTemplate = `<h1>Tools</h1>`
)

type basePage struct {
	Title string
	Body  string
}

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelDebug,
	}))
	serveMux := http.NewServeMux()

	serveMux.HandleFunc("/ids", buildIDsPageHandler(logger))
	serveMux.HandleFunc(newIDAPIPath, buildIDGenerationPageHandler(logger))

	serveMux.HandleFunc("/", func(res http.ResponseWriter, req *http.Request) {
		bp := &basePage{
			Title: "Home",
			Body:  indexTemplate,
		}
		if err := template.Must(template.New("base").Parse(baseTemplate)).Execute(res, bp); err != nil {
			logger.Error("failed to execute template", slog.Any("error", err))
		}
	})

	if err := http.ListenAndServe(":8080", serveMux); err != nil {
		logger.Error("failed to listen and serve", slog.Any("error", err))
	}
}
