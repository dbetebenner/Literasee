renderDOCX <- function(
  input,
  self_contained = FALSE,
  number_sections = TRUE,
  number_section_depth = 3,
  docx_css = "default",
  bibliography = "default",
  csl = "default",
  pandoc_args = NULL) {

  ###   Determine .Rmd/.md inputs

  #  rmd_input is same as rmd_input in renderMultiDocument, or has full YAML
  rmd_input <- sub("-Knitted.Rmd", ".Rmd", sub(file.path("Markdown", "raw_knitted", ""), "", input))

  #  Use HTML rendered .md file if it exists
  input.md <- file.path("HTML", "markdown", gsub(".Rmd", ".md", rmd_input, ignore.case=TRUE))
  if (!file.exists(input.md)) {
    input.md <- input
  }

  ### Create DOCX directory right away so that we can copy css to it.
  if (!dir.exists(file.path("DOCX", "markdown"))) {
    dir.create(file.path("DOCX", "markdown"), recursive=TRUE, showWarnings=FALSE)
  }

  ##
  ### Initial checks of alternative css
  ##

  ##  CSS check from Gmisc--docx_document - credit to Max Gordon/Gforge https://github.com/gforge

  if (docx_css != "default") {
    if (!all(sapply(docx_css, file.exists))) {
      alt_docx_css <- list.files(pattern = ".css$")
      if (length(alt_docx_css) > 0) {
        alt_docx_css <- paste0("\n You do have alternative file name(s) in current directory that you may intend to use.",
                               " You may want to have a YAML section that looks something like:",
                               "\n---", "\noutput:", "\n  Literasee::multi_document:",
                               "\n    docx_css: \"", paste(alt_docx_css, collapse = "\", \""),
                               "\"", "\n---")
      } else {
        alt_docx_css <- ""
      }
      stop("One or more of the css-file(s) that you've specified can't be identified.",
           "The file(s) '", paste(docx_css[!sapply(docx_css, file.exists)],
                                  collapse = "', '"), "'", " can't be found in the file path provided.")
    }
  } else {
    docx_css <- system.file("rmarkdown", "docx.css", package = "Gmisc") # default for docx_document
  }

  tmp_render_dir <- ifelse(self_contained, file.path("DOCX", "markdown"), "DOCX")
  file.copy(from = docx_css, to = ".", overwrite = TRUE)
  file.copy(from = docx_css, to = tmp_render_dir, overwrite = TRUE)
  docx_css <- "docx.css"

  if (self_contained)  file.copy("img/", tmp_render_dir, recursive = TRUE)

  ##  Check csl file
  if (!is.null(csl)) {
    if (csl != "default") {
      if (!file.exists(csl)) {
        stop("The csl file that you've specified can't be found in the file path provided.")
      } else pandoc_args <- c(pandoc_args, "--csl", csl) # Use pandoc_args here since docx_document passes that to html_document
    } else pandoc_args <- c(pandoc_args, "--csl", system.file("rmarkdown", "content", "bibliography", "apa-5th-edition.csl" , package = "Literasee"))
  }

  ##  pandoc args
  if(!is.null(pandoc_args)){
    if(any(grepl("--highlight-style", pandoc_args))) {
      highlight <- pandoc_args[grepl("--highlight-style", pandoc_args)]
      pandoc_args <- pandoc_args[!grepl("--highlight-style", pandoc_args)]
    } else {
      highlight <- "--highlight-style pygments"
    }
  }  #  END 'Initial Checks'

  ##
  ###   DOCX Drafts
  ##

  ###  Get YAML from .Rmd file
  file <- file(rmd_input) # input file
  rmd.text <- read_utf8(file)
  close(file)
  # Valid YAML could end in "---" or "..."  - test for both.
  rmd.yaml <- rmd.text[grep("---", rmd.text)[1]:ifelse(length(grep("---", rmd.text))>=2, grep("---", rmd.text)[2], grep("[.][.][.]", rmd.text)[1])]

  if (any(grepl("output:", rmd.yaml))) docx.rmd.yaml <- c(rmd.yaml[1:(grep("output:", rmd.yaml)-1)], "---") else docx.rmd.yaml <- rmd.yaml

  ###  Get .md file rendered from .rmd for html output
  file <- file(input.md)
  md.text <- read_utf8(file)
  close(file)

  ###   Check SGP_Report validity of markdown text
  if (any(grepl("<!-- HTML_Start", md.text))) {
    if (length(grep("<!-- HTML_Start", md.text)) != length(grep("<!-- LaTeX_Start", md.text))){
      stop("There must be equal number of '<!-- HTML_Start' and '<!-- LaTeX_Start' elements in the .Rmd file.")
    }
  }

  ##  Scrub LaTeX code
  while(any(grepl("<!-- LaTeX_Start", md.text))) {
    latex.start<-grep("<!-- LaTeX_Start", md.text)[1]
    latex.end <- grep("LaTeX_End -->", md.text)[1]
    md.text <- md.text[-(latex.start:latex.end)]
  }

  if (any(grepl("<!--SGPreport-->", md.text))) {
  	start.index <- grep("<!--SGPreport-->", md.text)
  	md.text <- c(docx.rmd.yaml, md.text[(start.index-1):length(md.text)])
  } else md.text <- c(docx.rmd.yaml, md.text)

  ### Clean out remaining HTML/markdown comments
  while(any(grepl("<!--", md.text))) {
    comment.start<-grep("<!--", md.text)[1]
    comment.end <- grep("-->", md.text)[1]
    md.text <- md.text[-(comment.start:comment.end)]
  }

  writeLines(md.text, file.path("DOCX", "markdown", gsub(".Rmd|.md", "-docx.md", rmd_input, ignore.case=TRUE)))

  ### Bibliography

  if (!is.null(bibliography)) {
  	my.pandoc_citeproc <- pandoc_citeproc()
  	if (bibliography == "default") {
      pandoc_args <-c(pandoc_args, "--filter", my.pandoc_citeproc, "--bibliography",
                      system.file("rmarkdown", "content", "bibliography", "Literasee.bib" , package = "Literasee"))
      bibliography <- NULL
    } else {
      if(file.exists(bibliography)) {
        pandoc_args <-c(pandoc_args, "--filter", my.pandoc_citeproc, "--bibliography", bibliography)
        file.copy(from = bibliography, to = file.path("DOCX", "markdown"), overwrite = TRUE)
        file.copy(from = bibliography, to = tmp_render_dir, overwrite = TRUE)
        bibliography <- NULL
      } else stop("'bibliography' file not found.")
    }
  }

  message("\n\tRendering DOCX with call to render(... Gmisc::docx_document):\n\tIntermediate file used: ", input.md, "\n")

  docx.file <- file.path("DOCX", gsub(".Rmd|.md", "-docx.md", rmd_input, ignore.case=TRUE))
  render(docx.file,
         Gmisc::docx_document(self_contained = self_contained, css=docx_css, number_sections=number_sections, pandoc_args=pandoc_args),
         output_dir="..")

  ##
  ###   Additional post-processing
  ##

  file <- file(docx.file)
  html.text <- readLines(file)

  for (header.level in (which(1:6 > number_section_depth))) {
    index <- grep(paste("<h", header.level, sep=""), html.text)
    for (i in index) {
      if (grepl("header-section-number", html.text[i])) {
        html.text[i] <- paste("<h", gsub(".*<h|><span.*", "", html.text[i]), ">",gsub("<span.*|.*span>", "", html.text[i]), sep="")
      }
    }
  }

  for(j in grep("<e2><86><a9>", html.text)) html.text[j] <- gsub("<e2><86><a9>", "", html.text[j])

  writeLines(html.text, file)
  close(file)

  file.copy("img", "DOCX", recursive = TRUE)
  if (self_contained)  unlink(file.path(tmp_render_dir, "img"), recursive = TRUE)
}  # End 'renderDOCX' function
