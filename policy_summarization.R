# Load Libraries ----
library(ragnar)
library(ellmer)
library(fs)
library(tidyverse)
library(glue)
library(blastula)
library(RDCOMClient)

store_location <- "pdf.ragnar.duckdb"
store <- ragnar_store_create(
  store_location,
  embed = \(x) embed_ollama(x, model = "nomic-embed-text:latest"),
  overwrite = TRUE
)

# Files ----
anthem_files_path <- "W:/PATACCT/BusinessOfc/Revenue Cycle Analyst/Payer_Policies/Anthem_PDFs/"
anthem_files <- list.files(anthem_files_path, full.names = TRUE)

# System Prompt ----
system_prompt <- stringr::str_squish(
  "You are an expert assistant in document summarization.
  When responding, you first quote relevant material from the documents in the store,
  provide links to the sources, and then add your own context and interpretation.
  You will provide the following for every document passed to you:
    1. Title of Policy
    2. At least three (3) bullet points
    3. A table of information
    4. Summary of the policy
    Be concise but thorough."
)

# Create Group Split tibble ----
file_split_tbl <- tibble(
  file_path = anthem_files
) |>
  mutate(
    file_name = path_file(file_path),
    file_extension = path_ext(file_path),
    file_size = file_size(file_path),
    file_date = file_info(file_path)$modification_time
  ) |>
  group_split(file_name)

# Map over the files and insert into storage ----
llm_resp_list <- file_split_tbl[2:3] |>
  imap(
    .f = function(obj, id) {
      # File path
      file_path <- obj$file_path[[1]]

      # Storage
      store_location <- "pdf.ragnar.duckdb"
      store <- ragnar_store_create(
        store_location,
        embed = \(x) embed_ollama(x, model = "nomic-embed-text:latest"),
        overwrite = TRUE
      )

      # Chunking
      chunks <- file_path |>
        read_as_markdown() |>
        markdown_chunk()

      # Insert into storage
      ragnar_store_insert(store, chunks)

      # Build index
      ragnar_store_build_index(store)

      # Chat Client
      client <- chat_ollama(
        model = "qwen3:0.6b",
        system_prompt = system_prompt,
        params = list(temperature = 0.1)
      )

      # Set Tool
      ragnar_register_tool_retrieve(
        chat = client,
        store = store
      )

      # Get response
      res <- client$chat("Please summarize the policy.", echo = "all")

      # Add response to obj tibble
      rec <- obj |> mutate(llm_resp = res)

      return(rec)
    }
  )


for (file in anthem_files_subset) {
  chunks <- file |>
    read_as_markdown() |>
    markdown_chunk()

  ragnar_store_insert(store, chunks)
}

ragnar_store_build_index(store)


client <- chat_ollama(
  model = "qwen3:0.6b",
  system_prompt = system_prompt,
  params = list(temperature = 0.1)
)

ragnar_register_tool_retrieve(
  chat = client,
  store = store
)

res <- client$chat("Please summarize the policy.", echo = "none")
file_extension <- path_ext(anthem_files_subset)
file_size <- file_size(anthem_files_subset)
file_date <- file_info(anthem_files_subset)$modification_time
file_name <- path_file(anthem_files_subset)
email_body <- md(glue(
  "
  Please see summary for {file_name}:

  Name: {file_name}
  Extension: {file_extension}
  Size: {file_size} bytes
  Date: {file_date}

  Summary Response: {res}
  "
))
email_body

Outlook <- COMCreate("Outlook.Application")
Email <- Outlook$CreateItem(0)
Email[["subject"]] <- "Payer Policy Files"
Email[["body"]] <- email_body
attachment <- anthem_files_subset
Email[["to"]] <- "steven.sanderson@stonybrookmedicine.edu"
Email[["attachments"]]$Add(attachment)
Email$Send()
rm(Outlook)
rm(Email)
